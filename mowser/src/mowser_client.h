#pragma once

// The CEF side of one page: what the engine calls when it has pixels, when a
// load starts or ends, and when the page renames itself.
//
// A CLIENT OUTLIVES ITS VIEW, WHICH IS WHY THIS INDIRECTION EXISTS. CEF holds
// its own reference to the client and keeps calling it while a browser closes,
// which on this appliance happens when somebody backs out of a page -- so a
// client holding a Godot node pointer would call into a freed node during
// teardown. The view detaches itself first (see MowserView::_exit_tree), and
// every callback below is null-guarded on that pointer. This is the same rule
// the launch seam already follows for a process that outlives its splash.

#include "mowser.h"
#include "include/cef_download_handler.h"
#include "include/cef_dialog_handler.h"
#include "include/cef_jsdialog_handler.h"
#include "include/cef_permission_handler.h"
#include "include/cef_request_handler.h"
#include "include/cef_devtools_message_observer.h"
#include <map>

namespace mowser {

// What a view exposes to the engine. Deliberately narrow: pixels in, four
// facts out. Anything richer belongs in the shell, in GDScript, where the rest
// of this project's UI decisions live.
class ViewSink {
public:
    virtual ~ViewSink() = default;

    // The size CEF should render at, in pixels. Never zero: CEF treats a
    // zero-sized view as an error and stops painting entirely, and a control
    // that has not been laid out yet legitimately reports zero for a frame or
    // two after it is added to the tree.
    virtual void sink_view_size(int &width, int &height) = 0;

    // One frame, BGRA32, `width * height * 4` bytes. Called on the shell's own
    // main thread -- see Runtime::pump -- so this may touch Godot objects
    // directly.
    virtual void sink_paint(const void *buffer, int width, int height) = 0;

    // THE BROWSER EXISTS NOW, which is not the same moment the view asked for
    // one. CefBrowserHost::CreateBrowser is asynchronous -- it returns before
    // there is a browser, and the object only arrives in OnAfterCreated, some
    // pumps later. Everything the shell asked for in between (a URL, a size)
    // has to be replayed here or it is simply lost, which is how a page ends
    // up sitting on about:blank while the log cheerfully reports a finished
    // load.
    virtual void sink_browser_ready() = 0;

    virtual void sink_load_started(const std::string &url) = 0;
    virtual void sink_load_finished(const std::string &url, int http_status) = 0;
    virtual void sink_load_failed(const std::string &url, const std::string &reason) = 0;
    virtual void sink_title(const std::string &title) = 0;
    virtual void sink_url(const std::string &url) = 0;
    virtual void sink_keyboard_context(bool editable, const std::string &type,
        const std::string &mode, const std::string &label, const std::string &action) = 0;
    virtual void sink_download(uint32_t id, const std::string &path, int64_t received,
        int64_t total, const std::string &state, const std::string &detail) = 0;
    virtual void sink_file_dialog(const std::string &title, bool multiple,
        const std::vector<CefString> &extensions) = 0;
    virtual void sink_script_dialog(const std::string &origin, const std::string &type,
        const std::string &message, const std::string &default_text) = 0;
    virtual void sink_popup(const std::string &url) = 0;
};

class Client : public CefClient,
               public CefRenderHandler,
               public CefLifeSpanHandler,
               public CefLoadHandler,
               public CefDownloadHandler,
               public CefDialogHandler,
               public CefJSDialogHandler,
               public CefPermissionHandler,
               public CefRequestHandler,
               public CefDevToolsMessageObserver,
               public CefDisplayHandler {
public:
    explicit Client(ViewSink *sink) : sink_(sink) {}

    // Called by the view before it goes away. After this the client is inert
    // and safe for CEF to keep calling for as long as it likes.
    void detach();
    void set_download_directory(const std::string &path) { download_directory_ = path; }
    void cancel_download(uint32_t id);
    void respond_file_dialog(const std::vector<CefString> &paths);
    void respond_script_dialog(bool accepted, const std::string &text);
    void cancel_dialogs();

    CefRefPtr<CefBrowser> browser() const { return browser_; }
    bool is_popup_open() const { return popup_visible_; }

    // CefClient
    CefRefPtr<CefRenderHandler> GetRenderHandler() override { return this; }
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
    CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
    CefRefPtr<CefDialogHandler> GetDialogHandler() override { return this; }
    CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
    CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
    CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
    bool OnFileDialog(CefRefPtr<CefBrowser>, FileDialogMode, const CefString &,
        const CefString &, const std::vector<CefString> &, const std::vector<CefString> &,
        const std::vector<CefString> &, CefRefPtr<CefFileDialogCallback>) override;
    bool OnJSDialog(CefRefPtr<CefBrowser>, const CefString &, JSDialogType,
        const CefString &, const CefString &, CefRefPtr<CefJSDialogCallback>, bool &) override;
    bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser>, const CefString &, bool,
        CefRefPtr<CefJSDialogCallback>) override;
    void OnResetDialogState(CefRefPtr<CefBrowser>) override { respond_script_dialog(false, ""); }
    bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>,
        const CefString &, uint32_t, CefRefPtr<CefMediaAccessCallback> callback) override {
        callback->Cancel(); return true;
    }
    bool OnShowPermissionPrompt(CefRefPtr<CefBrowser>, uint64_t, const CefString &,
        uint32_t, CefRefPtr<CefPermissionPromptCallback> callback) override {
        callback->Continue(CEF_PERMISSION_RESULT_DENY); return true;
    }
    bool OnBeforeBrowse(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>,
        CefRefPtr<CefRequest>, bool, bool) override;
    void OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser,
        TerminationStatus, int, const CefString &) override {
        cancel_dialogs();
        if (sink_) sink_->sink_load_failed(browser->GetMainFrame()->GetURL().ToString(),
            "the page process stopped");
    }
    void OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int message_id,
        bool success, const void *result, size_t result_size) override;
    bool OnBeforeDownload(CefRefPtr<CefBrowser> browser,
        CefRefPtr<CefDownloadItem> item, const CefString &suggested_name,
        CefRefPtr<CefBeforeDownloadCallback> callback) override;
    void OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
        CefRefPtr<CefDownloadItem> item,
        CefRefPtr<CefDownloadItemCallback> callback) override;
    bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser,
        CefRefPtr<CefFrame> frame, CefProcessId source_process,
        CefRefPtr<CefProcessMessage> message) override;

    // CefRenderHandler
    void GetViewRect(CefRefPtr<CefBrowser> browser, CefRect &rect) override;
    void OnPaint(CefRefPtr<CefBrowser> browser, PaintElementType type,
                 const RectList &dirtyRects, const void *buffer, int width,
                 int height) override;
    void OnPopupShow(CefRefPtr<CefBrowser>, bool show) override;
    void OnPopupSize(CefRefPtr<CefBrowser>, const CefRect &rect) override { popup_rect_ = rect; }

    // CefLifeSpanHandler
    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override;
    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override;
    // A PAGE MAY NOT OPEN A WINDOW. There is no window system here to open one
    // into: returning true cancels the popup, and target_url is navigated in
    // the page instead by the shell if it ever wants that. Without this, a
    // checkout's "open in new tab" is a click that silently does nothing while
    // CEF waits for an embedder that never answers.
    bool OnBeforePopup(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                       int popup_id, const CefString &target_url,
                       const CefString &target_frame_name,
                       cef_window_open_disposition_t target_disposition,
                       bool user_gesture, const CefPopupFeatures &popupFeatures,
                       CefWindowInfo &windowInfo, CefRefPtr<CefClient> &client,
                       CefBrowserSettings &settings,
                       CefRefPtr<CefDictionaryValue> &extra_info,
                       bool *no_javascript_access) override;

    // CefLoadHandler
    void OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                     TransitionType transition_type) override;
    void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                   int httpStatusCode) override;
    void OnLoadError(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                     ErrorCode errorCode, const CefString &errorText,
                     const CefString &failedUrl) override;

    // CefDisplayHandler
    void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) override;
    void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                         const CefString &url) override;

private:
    ViewSink *sink_ = nullptr;
    CefRefPtr<CefBrowser> browser_;
    bool painted_once_ = false;
    CefRefPtr<CefFileDialogCallback> file_dialog_;
    CefRefPtr<CefJSDialogCallback> script_dialog_;
    CefRefPtr<CefRegistration> devtools_registration_;
    std::string upload_token_, upload_search_;
    std::vector<CefString> upload_paths_;
    int devtools_id_ = 0, upload_request_id_ = 0, upload_stage_ = 0;
    CefRect popup_rect_;
    bool popup_visible_ = false;
    std::vector<uint8_t> page_pixels_;
    int page_width_ = 0, page_height_ = 0;
    struct Download {
        std::string path;
        uint64_t device = 0;
        uint64_t inode = 0;
        CefRefPtr<CefDownloadItemCallback> callback;
    };
    std::string download_directory_;
    std::map<uint32_t, Download> downloads_;
    static void remove_reservation(const Download &download);

    IMPLEMENT_REFCOUNTING(Client);
    DISALLOW_COPY_AND_ASSIGN(Client);
};

}  // namespace mowser
