#include "mowser_extensions.h"
#include "mowser.h"
#include "include/cef_id_mappers.h"
#include "include/cef_keyboard_handler.h"
#include "include/cef_parser.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_browser_view_delegate.h"
#include "include/views/cef_box_layout.h"
#include "include/views/cef_window.h"
#include "include/views/cef_window_delegate.h"
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <map>
#include <utility>

namespace mowser {
namespace {
constexpr const char *kStore = "https://chromewebstore.google.com/category/extensions";
CefRefPtr<CefBrowser> g_extension_browser;
CefRefPtr<CefWindow> g_extension_window;
CefRect g_panel_bounds(840, 104, 760, 796);
bool g_open_requested = false;
bool g_creation_pending = false;
std::string g_extension_url;
std::map<int, CefRefPtr<CefBrowser>> g_auxiliary_browsers;

class PanelBrowserDelegate : public CefBrowserViewDelegate {
public:
    cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
private:
    IMPLEMENT_REFCOUNTING(PanelBrowserDelegate);
};

class PanelWindowDelegate : public CefWindowDelegate {
public:
    explicit PanelWindowDelegate(CefRefPtr<CefBrowserView> view) : view_(view) {}
    void OnWindowCreated(CefRefPtr<CefWindow> window) override {
        g_extension_window = window;
        window->SetTitle("Bench extensions");
        CefBoxLayoutSettings layout;
        layout.horizontal = false;
        auto column = window->SetToBoxLayout(layout);
        window->AddChildView(view_);
        column->SetFlexForView(view_, 1);
        window->SetAlwaysOnTop(true);
        window->Show();
        view_->RequestFocus();
    }
    void OnWindowDestroyed(CefRefPtr<CefWindow>) override {
        g_extension_window = nullptr;
        view_ = nullptr;
    }
    CefRect GetInitialBounds(CefRefPtr<CefWindow>) override {
        const char *compositor = std::getenv("MARWANOS_COMPOSITOR");
        // Gamescope must see the overlay property before the window grows.
        return compositor && std::strcmp(compositor, "x11") == 0 ? g_panel_bounds : CefRect(0, 0, 1, 1);
    }
    bool IsFrameless(CefRefPtr<CefWindow>) override { return true; }
    bool CanResize(CefRefPtr<CefWindow>) override { return false; }
    bool CanMaximize(CefRefPtr<CefWindow>) override { return false; }
    bool CanMinimize(CefRefPtr<CefWindow>) override { return false; }
    bool CanClose(CefRefPtr<CefWindow>) override {
        return !g_extension_browser || g_extension_browser->GetHost()->TryCloseBrowser();
    }
    cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
private:
    CefRefPtr<CefBrowserView> view_;
    IMPLEMENT_REFCOUNTING(PanelWindowDelegate);
};

class ExtensionClient : public CefClient,
                        public CefLifeSpanHandler,
                        public CefLoadHandler,
                        public CefKeyboardHandler {
public:
    explicit ExtensionClient(std::string initial_url, bool primary = true)
        : initial_url_(std::move(initial_url)), primary_(primary) {}
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        if (!primary_ || primary_id_ != 0) {
            // Extension APIs create setup tabs without OnBeforePopup. Keep
            // them until their first real URL arrives, then show it in the
            // panel. Action popup content also stays in the panel for setup.
            g_auxiliary_browsers[browser->GetIdentifier()] = browser;
            if (!g_open_requested) browser->GetHost()->CloseBrowser(true);
            return;
        }
        primary_id_ = browser->GetIdentifier();
        g_creation_pending = false;
        g_extension_browser = browser;
        if (!g_open_requested) browser->GetHost()->CloseBrowser(true);
        else if (initial_url_ != g_extension_url)
            browser->GetMainFrame()->LoadURL(g_extension_url);
    }
    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
        if (!primary_ || browser->GetIdentifier() != primary_id_) {
            g_auxiliary_browsers.erase(browser->GetIdentifier());
            return;
        }
        g_extension_browser = nullptr;
        g_open_requested = false;
    }
    void OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                     TransitionType) override {
        if (!frame->IsMain() || (primary_ && browser->GetIdentifier() == primary_id_)) return;
        const auto url = frame->GetURL().ToString();
        if (browser->IsPopup() && !url.starts_with("chrome-extension://")) return;
        if (url.empty() || url == "about:blank") return;
        if (g_open_requested && g_extension_browser &&
            (url.starts_with("chrome-extension://") || url.starts_with("https://") || url.starts_with("http://"))) {
            g_extension_browser->GetMainFrame()->LoadURL(url);
            if (g_extension_window) g_extension_window->Activate();
        }
        browser->GetHost()->CloseBrowser(true);
    }
    bool OnKeyEvent(CefRefPtr<CefBrowser> browser, const CefKeyEvent &event,
                   CefEventHandle) override {
        if (event.type == KEYEVENT_RAWKEYDOWN && event.windows_key_code == 27) {
            browser->GetHost()->CloseBrowser(true);
            return true;
        }
        return false;
    }
    bool OnBeforePopup(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>, int,
        const CefString &url, const CefString &, cef_window_open_disposition_t,
        bool user_gesture, const CefPopupFeatures &, CefWindowInfo &,
        CefRefPtr<CefClient> &, CefBrowserSettings &, CefRefPtr<CefDictionaryValue> &,
        bool *) override {
        // User-requested options and sign-in pages stay beside the current tab.
        if (user_gesture && !url.empty()) browser->GetMainFrame()->LoadURL(url);
        return true;
    }
private:
    std::string initial_url_;
    bool primary_;
    int primary_id_ = 0;
    IMPLEMENT_REFCOUNTING(ExtensionClient);
};
}

bool is_extension_store_url(const std::string &url) {
    CefURLParts parts;
    if (!CefParseURL(url, parts)) return false;
    const auto host = CefString(&parts.host).ToString();
    return CefString(&parts.scheme) == "https" &&
        (host == "chromewebstore.google.com" ||
         (host == "chrome.google.com" && CefString(&parts.path).ToString().starts_with("/webstore")));
}

bool open_extension_window(const std::string &url) {
    CefURLParts parts;
    const bool extension_page = CefParseURL(url, parts) && CefString(&parts.scheme) == "chrome-extension" &&
        CefString(&parts.host).length() == 32 &&
        CefString(&parts.host).ToString().find_first_not_of("abcdefghijklmnop") == std::string::npos;
    if (!Runtime::running() || !(is_extension_store_url(url) || url == "chrome://extensions/" || extension_page))
        return false;
    g_extension_url = url;
    if (g_extension_browser) {
        g_extension_browser->GetMainFrame()->LoadURL(url);
        g_extension_browser->GetHost()->SetFocus(true);
        return true;
    }
    if (g_open_requested) return true;
    g_open_requested = true;
    g_creation_pending = true;
    CefBrowserSettings settings;
    // nullptr request context deliberately selects the same persistent profile
    // as every embedded page. No second browser, download helper or CRX bypass.
    auto view = CefBrowserView::CreateBrowserView(new ExtensionClient(url), url,
        settings, nullptr, nullptr, new PanelBrowserDelegate());
    if (!view || !CefWindow::CreateTopLevelWindow(new PanelWindowDelegate(view))) {
        g_open_requested = false;
        g_creation_pending = false;
        return false;
    }
    return true;
}

bool extension_window_open() {
    return g_open_requested || g_creation_pending || g_extension_browser || g_extension_window || !g_auxiliary_browsers.empty();
}

CefRefPtr<CefClient> extension_default_client() {
    return new ExtensionClient("", false);
}

void extension_window_command(const std::string &command) {
    if (command == "close") {
        g_open_requested = false;
        if (g_extension_browser) g_extension_browser->GetHost()->CloseBrowser(true);
        // Closing callbacks erase this map, so iterate over a retained copy.
        const auto auxiliary = g_auxiliary_browsers;
        for (const auto &[id, browser] : auxiliary) browser->GetHost()->CloseBrowser(true);
    } else if (command == "store") {
        open_extension_window(kStore);
    } else if (command == "manage") {
        open_extension_window("chrome://extensions/");
    } else if (command == "back" && g_extension_browser && g_extension_browser->CanGoBack()) {
        g_extension_browser->GoBack();
    } else if (command == "hide" && g_extension_window) {
        g_extension_window->Hide();
    } else if (command == "show" && g_extension_window) {
        g_extension_window->Show();
        g_extension_window->Activate();
    }
}

void set_extension_panel_bounds(int x, int y, int width, int height) {
    g_panel_bounds = CefRect(x, y, std::max(1, width), std::max(1, height));
    if (g_extension_window) g_extension_window->SetBounds(g_panel_bounds);
}

unsigned long extension_panel_handle() {
    return g_extension_window ? g_extension_window->GetWindowHandle() : 0;
}

std::string extension_page_url() {
    return g_extension_browser ? g_extension_browser->GetMainFrame()->GetURL().ToString() : "";
}

}
