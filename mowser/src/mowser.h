#pragma once

// MOWSER -- the appliance's browser, which is an ENGINE AND NOTHING ELSE.
//
// WHAT THIS IS, stated once here because every file below assumes it. Chromium's
// engine runs inside the shell's own process, renders off-screen into a buffer,
// and that buffer becomes a texture on a Godot control. There is no browser
// window, no tab strip, no address bar, no settings page and no menu -- not
// hidden, not disabled: not built. Everything a person sees around a page is
// drawn by the shell in the same theme as the rail, and everything they can do
// to it is a method on MowserView that the shell decides to call.
//
// WHY THIS RATHER THAN A BROWSER IN KIOSK MODE, which this repo shipped for
// about a day (see the Chromium headstone in shipped-apps). Kiosk mode is a
// flag on somebody else's application: their profile, their update cadence,
// their crash dialogs, their idea of what a keyboard shortcut should do -- and
// one keystroke or one changed default away from a UI the owner never asked
// for. The owner asked for a browser that is ours. This is that: the engine is
// a library we link, and the browser around it is this project's code.
//
// STEAM'S OWN UI IS THIS EXACT FRAMEWORK, which is the honest measure of what
// is being given up by not shipping a browser's face: nothing a checkout needs.
//
// ---------------------------------------------------------------------------
// THE THREE PROCESSES, because CEF is not a library in the way that word
// usually promises. Chromium is multi-process by design (a renderer crash must
// not take the browser with it, and a compromised renderer must not be able to
// read the disk), so linking libcef into the shell gets us the BROWSER process
// only. The renderer, GPU and utility processes are separate executables that
// CEF starts itself.
//
// Ordinarily a CEF application re-executes its own binary with a --type= flag,
// which requires calling CefExecuteProcess as the very first thing in main().
// We do not own main() -- Godot does -- so that is not available, and doing it
// late is not "less correct", it crashes. Hence mowser-helper: a separate
// executable whose entire body is CefExecuteProcess (see subprocess.cpp),
// named to CefSettings::browser_subprocess_path. The alternative -- patching
// Godot's main -- would fork the engine to avoid forking the browser.
//
// ---------------------------------------------------------------------------
// THE COST OF BEING IN-PROCESS, STATED PLAINLY BECAUSE IT IS PERMANENT.
//
// Chromium reports a fatal initialisation error by calling abort(). It is not
// an exception, not a return code, and nothing here can catch it -- so a CEF
// failure does not degrade the browser, it kills THE SHELL. On this appliance
// that is a black television, which is the one failure mode this whole project
// is organised against.
//
// It has already happened once, on 2026-08-11, and the cause is instructive:
// the payload shipped its .pak files under a resources/ subdirectory, which
// reads better than a flat directory and is not where Chromium looks for ICU
// data. Every file was present, every path this file checks existed, and the
// shell died the first time somebody pressed Buy.
//
// A BROWSER IN ITS OWN WINDOW WOULD NOT HAVE THIS PROBLEM -- the launch seam
// would notice a client that exited and hand the screen back, which is what it
// already does for Steam. That was the trade accepted when the owner chose the
// engine inside the launcher over a separate window, and it is the right trade
// for what it buys (no foreign UI, no xdotool, a page that is a Control). But
// it means the checks below are not belt-and-braces: they are the only thing
// standing between a mis-assembled payload and a dead appliance, and anything
// that can be verified BEFORE CefInitialize is called must be.
//
// THE SANDBOX STAYS ON. This renders arbitrary web content: a Steam checkout,
// and whatever else somebody navigates to. --no-sandbox is the one-line way to
// make CEF start on a machine where the namespace sandbox is unavailable, and
// it is the wrong line: it removes the boundary between a hostile page and the
// session user's home directory. The image instead ships chrome-sandbox SUID
// root at build time (the same class of build-time-only fix as gamescope's
// CAP_SYS_NICE -- /usr is composefs and read-only at runtime, so it cannot be
// done later). See the Containerfile.

#include <cstdint>
#include <string>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_render_handler.h"

namespace mowser {

// Where the image puts the engine's own files. Absolute because CEF resolves
// none of these relative to anything useful, and a resource CEF cannot find is
// a renderer that starts and shows a blank page with nothing in the journal.
constexpr const char *kInstallRoot = "/usr/lib/marwanos/mowser";

// The desk/harness override, in the spirit of MARWANOS_SHELL_STATUS_DIR: point
// it at an unpacked CEF distribution and mowser runs on a machine that has no
// /usr/lib/marwanos at all. Nothing on the appliance sets it.
constexpr const char *kInstallRootEnv = "MARWANOS_MOWSER_ROOT";

// The harness's sandbox escape, honoured ONLY in a process running as root --
// which the appliance's shell never is. See Runtime::ensure_started for why
// that second condition is the one doing the work.
constexpr const char *kNoSandboxEnv = "MARWANOS_MOWSER_NO_SANDBOX";

// Resolved install root -- the env override where set, kInstallRoot otherwise.
std::string install_root();

// ---------------------------------------------------------------------------
// THE RUNTIME: one CefInitialize per process, and one message pump.
//
// CEF is a process-wide singleton -- CefInitialize twice is a crash, and
// CefShutdown while a browser is alive is a different crash -- so the lifecycle
// cannot belong to a node that can be freed and rebuilt. It belongs here, and
// the nodes only say "I need this up" and "I am done with it".
class Runtime {
public:
    // Brings CEF up if it is not already, and says whether the engine is
    // usable. False is a normal answer on a machine whose image is missing
    // the payload; every caller draws something honest instead of crashing.
    static bool ensure_started();

    // Whether ensure_started has succeeded. Cheap; safe before startup.
    static bool running();

    // Why the engine is not up, for the one line the shell puts on screen.
    // Empty while it is running or has not been asked for yet.
    static const std::string &failure();

    // ONE PUMP PER FRAME, ACROSS EVERY VIEW. CefDoMessageLoopWork drives the
    // whole browser process -- timers, IPC, and the paint callbacks -- and it
    // must be called from exactly one place per frame. Views all call this and
    // it de-duplicates on Godot's own frame counter, so two pages open at once
    // do not pump the loop twice as fast (which starves nothing but does make
    // every timing in the engine wrong by a factor of the view count).
    //
    // PUMPING FROM THE SHELL'S MAIN THREAD IS WHAT MAKES THE REST SAFE: every
    // CEF callback below therefore arrives on Godot's main thread, so painting
    // into a texture and emitting a signal need no marshalling. The tradeoff
    // is that the engine only gets to run when the shell draws a frame; at TV
    // framerate that is fine, and it is why windowless_frame_rate is set to
    // something a television can actually show rather than to 60 on principle.
    // The token is the shell's own frame number; see the de-duplication note.
    static void pump(uint64_t frame_token);

    // Called when the extension unloads. Ends the browser process cleanly;
    // after this the engine cannot be started again in this process.
    static void shutdown();
};

}  // namespace mowser
