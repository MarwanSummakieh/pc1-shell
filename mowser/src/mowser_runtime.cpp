#include "mowser.h"

#include <cstdio>
#include <cstdlib>
#include <sys/stat.h>
#include <unistd.h>

#include "include/cef_command_line.h"
#include "include/wrapper/cef_helpers.h"

namespace mowser {
namespace {

bool g_started = false;
bool g_attempted = false;
std::string g_failure;
uint64_t g_last_pumped_frame = 0;

bool exists(const std::string &path) {
    struct stat st {};
    return ::stat(path.c_str(), &st) == 0;
}

// THE APP OBJECT, whose only job is the command line.
//
// Every switch here is a decision about a machine with no keyboard, one
// compositor and one screen, and each is load-bearing:
//
//   --disable-gpu / --disable-gpu-compositing
//       Chromium would otherwise bring up its own GPU compositor inside the
//       shell's process, under gamescope, alongside the shell's Vulkan
//       renderer. This project has already paid once for stacking compositors
//       (the nested-gamescope detour: a crash three minutes into a game, see
//       catalogue.gd's STEAM_STORE note), and the off-screen path we actually
//       consume is the SOFTWARE one -- OnPaint with a pixel buffer. Accelerated
//       paint would hand us a shared texture we are not reading, so the GPU
//       stack here would cost startup time and risk to produce something
//       nothing looks at.
//
//   --disable-dev-shm-usage
//       /dev/shm is small in a container and on this appliance; Chromium's
//       default use of it produces renderer crashes that read as "the page
//       went blank" with nothing obvious in the journal.
//
//   --autoplay-policy=document-user-activation-required
//       A store page that starts playing a trailer with audio the moment it
//       opens is not what pressing "Buy" asked for.
class MowserApp : public CefApp, public CefBrowserProcessHandler {
public:
    MowserApp() = default;

    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
        return this;
    }

    void OnBeforeCommandLineProcessing(const CefString &process_type,
                                       CefRefPtr<CefCommandLine> command_line) override {
        // Browser process only: the helper gets its command line from CEF
        // itself and appending to it is how you break a renderer.
        if (!process_type.empty()) {
            return;
        }
        command_line->AppendSwitch("disable-gpu");
        command_line->AppendSwitch("disable-gpu-compositing");
        command_line->AppendSwitch("disable-dev-shm-usage");
        // CEF 151's reading-mode observer assumes every WebContents has a Chrome
        // tab and segfaults on SPA navigation in an off-screen/Alloy browser.
        // Our symbolicated bench crashes match CEF issue 4234 exactly.
        // https://github.com/chromiumembedded/cef/issues/4234
        command_line->AppendSwitchWithValue("disable-features", "ImmersiveReadAnything");
        command_line->AppendSwitchWithValue("autoplay-policy",
                                            "document-user-activation-required");
    }

private:
    IMPLEMENT_REFCOUNTING(MowserApp);
    DISALLOW_COPY_AND_ASSIGN(MowserApp);
};

CefRefPtr<MowserApp> g_app;

}  // namespace

std::string install_root() {
    const char *override_root = ::getenv(kInstallRootEnv);
    if (override_root != nullptr && *override_root != '\0') {
        return std::string(override_root);
    }
    return std::string(kInstallRoot);
}

bool Runtime::running() { return g_started; }

const std::string &Runtime::failure() { return g_failure; }

bool Runtime::ensure_started() {
    if (g_started) {
        return true;
    }
    // ONE ATTEMPT PER PROCESS. CefInitialize cannot be retried after a failure
    // in any way the framework supports, and a view that retried on every
    // frame would fill the journal at 60 lines a second describing a machine
    // that is not going to get better without a reboot.
    if (g_attempted) {
        return false;
    }
    g_attempted = true;

    const std::string root = install_root();

    // NAMED ONE AT A TIME, because "the browser did not start" is useless on a
    // machine with no console and these are the four ways an image can be
    // wrong. Each of these is something the Containerfile asserts at build
    // time as well -- this is the same check from the running end.
    // FLAT, BESIDE libcef.so, which is CEF's own sample layout and not a
    // preference. Chromium finds its ICU data relative to the module and hands
    // the file descriptor to the renderer it forks; a resources/ subdirectory
    // reads better and aborts the process with "Invalid file descriptor to ICU
    // data received" the first time a page is opened. locales/ is the one
    // subdirectory, because that is where CEF looks for it.
    const std::string helper = root + "/mowser-helper";
    const std::string resources = root;
    const std::string locales = root + "/locales";
    const std::string icu = root + "/icudtl.dat";
    for (const auto &required : {helper, resources, locales, icu}) {
        if (!exists(required)) {
            g_failure = "the browser engine is missing " + required;
            return false;
        }
    }

    CefSettings settings;

    // THE SANDBOX IS ON, AND THE ONE EXCEPTION CANNOT REACH THE APPLIANCE.
    //
    // Chromium refuses outright to sandbox a process running as root ("Running
    // as root without --no-sandbox is not supported", crbug.com/638180) and
    // aborts -- which, in-process, is the shell dying. That case is not the
    // appliance: greetd starts the shell as `player`, and it is the invisible
    // harness (scripts/xvfb-shell-verify.sh) that runs a container as root.
    //
    // So the escape hatch is guarded TWICE, and the second guard is the one
    // that matters: an environment variable to ask for it, AND an effective
    // uid of 0 for it to be honoured at all. On any machine where the shell
    // runs as a normal user -- every real one -- setting the variable does
    // nothing, so this cannot be used to quietly unsandbox somebody's
    // television. It only permits what Chromium was going to refuse anyway.
    const char *want_no_sandbox = ::getenv(kNoSandboxEnv);
    const bool asked_no_sandbox =
        want_no_sandbox != nullptr && *want_no_sandbox != '\0' &&
        std::string(want_no_sandbox) != "0";
    if (asked_no_sandbox && ::geteuid() == 0) {
        settings.no_sandbox = true;
        // Said loudly and every time: an unsandboxed browser is a fact about
        // the machine, not a detail, and the journal is where this project
        // reads facts about a machine back afterwards.
        std::fprintf(stderr,
                     "<4>mowser: running WITHOUT the renderer sandbox because this "
                     "process is root and %s is set -- this is the test harness's "
                     "path and must never be an appliance's\n",
                     kNoSandboxEnv);
    } else {
        settings.no_sandbox = false;  // see mowser.h -- the image ships chrome-sandbox SUID
    }
    settings.windowless_rendering_enabled = true;
    // Neither: we drive the loop ourselves from the shell's frame. See
    // Runtime::pump for why that is what makes every callback main-thread.
    settings.multi_threaded_message_loop = false;
    settings.external_message_pump = false;
    settings.log_severity = LOGSEVERITY_WARNING;

    CefString(&settings.browser_subprocess_path) = helper;
    CefString(&settings.resources_dir_path) = resources;
    CefString(&settings.locales_dir_path) = locales;

    // THE PROFILE, and it is deliberately persistent. A checkout that made
    // somebody sign into Steam again for every purchase would be a worse
    // experience than the client this replaced. It lives under the session
    // user's own home because that is the one place on this appliance the
    // shell can write; /var/home/player is provisioned by tmpfiles.d.
    const char *home = ::getenv("HOME");
    const std::string cache =
        std::string(home != nullptr && *home != '\0' ? home : "/var/home/player") +
        "/.local/share/marwanos/mowser";
    CefString(&settings.root_cache_path) = cache;
    CefString(&settings.cache_path) = cache;

    // EMPTY ARGV, ON PURPOSE. The real argv belongs to Godot -- it carries
    // --headless, --path and whatever else started the shell -- and handing
    // that to Chromium's command-line parser means the browser reacting to
    // flags meant for the engine. Everything mowser needs is set above or in
    // OnBeforeCommandLineProcessing.
    CefMainArgs args(0, nullptr);

    g_app = new MowserApp();
    if (!CefInitialize(args, settings, g_app.get(), nullptr)) {
        g_failure = "the browser engine refused to start";
        g_app = nullptr;
        return false;
    }

    g_started = true;
    g_failure.clear();
    return true;
}

void Runtime::pump(uint64_t frame_token) {
    if (!g_started) {
        return;
    }
    if (frame_token == g_last_pumped_frame) {
        return;
    }
    g_last_pumped_frame = frame_token;
    CefDoMessageLoopWork();
}

void Runtime::shutdown() {
    if (!g_started) {
        return;
    }
    g_started = false;
    // Let anything mid-teardown finish before the framework goes away.
    // Browsers are closed by their views before this runs.
    for (int i = 0; i < 10; ++i) {
        CefDoMessageLoopWork();
    }
    CefShutdown();
    g_app = nullptr;
}

}  // namespace mowser
