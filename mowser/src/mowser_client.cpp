#include "mowser_client.h"
#include "mowser_extensions.h"

#include <cstdio>
#include <algorithm>
#include <cstring>
#include <filesystem>
#include <cctype>
#include "include/cef_parser.h"

namespace mowser {

void Client::GetViewRect(CefRefPtr<CefBrowser> browser, CefRect &rect) {
    int width = 0;
    int height = 0;
    if (sink_ != nullptr) {
        sink_->sink_view_size(width, height);
    }
    // NEVER ZERO. CEF treats an empty view rect as a programming error and
    // stops painting the browser entirely -- permanently, not until the next
    // resize -- and a Control legitimately reports zero size for a frame or
    // two between being added to the tree and being laid out. Falling back to
    // the design surface means the first paint may be the wrong size, which
    // the next OnPaint corrects; the alternative is a page that never draws
    // and no error anywhere explaining why.
    rect.x = 0;
    rect.y = 0;
    rect.width = width > 0 ? width : 1920;
    rect.height = height > 0 ? height : 1080;
}

void Client::OnPaint(CefRefPtr<CefBrowser> browser, PaintElementType type,
                     const RectList &dirtyRects, const void *buffer, int width,
                     int height) {
    if (sink_ == nullptr || !buffer || width <= 0 || height <= 0) {
        return;
    }
    if (type == PET_POPUP) {
        if (!popup_visible_ || page_pixels_.empty()) return;
        auto pixels = page_pixels_;
        const auto *source = static_cast<const uint8_t *>(buffer);
        for (int row = 0; row < height; ++row) {
            int y = popup_rect_.y + row;
            if (y < 0 || y >= page_height_) continue;
            int start = std::max(0, -popup_rect_.x);
            int end = std::min(width, page_width_ - popup_rect_.x);
            if (end > start) std::memcpy(pixels.data() + (y * page_width_ + popup_rect_.x + start) * 4,
                source + (row * width + start) * 4, (end - start) * 4);
        }
        sink_->sink_paint(pixels.data(), page_width_, page_height_);
        return;
    }
    page_width_ = width; page_height_ = height;
    const auto *source = static_cast<const uint8_t *>(buffer);
    page_pixels_.assign(source, source + static_cast<size_t>(width) * height * 4);
    (void)dirtyRects;  // The whole buffer arrives every time; see sink_paint.
    // SAID ONCE, and it is the single most useful line in this file when
    // something is wrong. "The page is blank" has two completely different
    // causes -- the engine never painted, or it painted and the texture never
    // reached the screen -- and they are indistinguishable from a screenshot.
    // One line at the boundary tells them apart.
    if (!painted_once_) {
        painted_once_ = true;
        std::fprintf(stderr, "<6>mowser: first paint %dx%d\n", width, height);
    }
    sink_->sink_paint(buffer, width, height);
}

void Client::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
    // Held so the view can reach the host for navigation and input. This is
    // the only reference the browser process keeps to the page besides CEF's
    // own, which is why OnBeforeClose has to clear it.
    browser_ = browser;
    devtools_registration_ = browser->GetHost()->AddDevToolsMessageObserver(this);
    std::fprintf(stderr, "<6>mowser: browser created\n");
    if (sink_ != nullptr) {
        sink_->sink_browser_ready();
    }
}

void Client::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
    devtools_registration_ = nullptr;
    browser_ = nullptr;
}

bool Client::OnBeforePopup(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                           int popup_id, const CefString &target_url,
                           const CefString &target_frame_name,
                           cef_window_open_disposition_t target_disposition, bool user_gesture,
                           const CefPopupFeatures &popupFeatures, CefWindowInfo &windowInfo,
                           CefRefPtr<CefClient> &client, CefBrowserSettings &settings,
                           CefRefPtr<CefDictionaryValue> &extra_info,
                           bool *no_javascript_access) {
    // Only user-initiated new windows become shell tabs. CEF must never create
    // a separate native browser window that a controller cannot dismiss.
    if (sink_ != nullptr && user_gesture && !target_url.empty()) {
        sink_->sink_popup(target_url.ToString());
    }
    return true;  // true CANCELS the popup
}

void Client::OnPopupShow(CefRefPtr<CefBrowser>, bool show) {
    popup_visible_ = show;
    if (!show && sink_ && !page_pixels_.empty())
        sink_->sink_paint(page_pixels_.data(), page_width_, page_height_);
}

void Client::cancel_dialogs() {
    upload_token_.clear(); upload_paths_.clear();
    auto file = file_dialog_; file_dialog_ = nullptr;
    auto script = script_dialog_; script_dialog_ = nullptr;
    if (file) file->Cancel();
    if (script) script->Continue(false, "");
}

void Client::respond_file_dialog(const std::vector<CefString> &paths) {
    auto callback = file_dialog_; file_dialog_ = nullptr;
    if (!callback && upload_token_.empty()) return;
    for (const auto &path : paths) {
        const std::filesystem::path file(path.ToString());
        std::error_code error;
        if (!file.is_absolute() || !std::filesystem::is_regular_file(file, error)) {
            if (callback) callback->Cancel();
            upload_token_.clear(); return;
        }
    }
    if (callback) {
        if (paths.empty()) callback->Cancel(); else callback->Continue(paths);
        return;
    }
    if (paths.empty()) { upload_token_.clear(); return; }
    upload_paths_ = paths;
    auto params = CefDictionaryValue::Create();
    params->SetInt("depth", -1); params->SetBool("pierce", true);
    upload_stage_ = 0; upload_request_id_ = ++devtools_id_;
    browser_->GetHost()->ExecuteDevToolsMethod(upload_request_id_, "DOM.getDocument", params);
}

void Client::OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser, int message_id,
    bool success, const void *result, size_t result_size) {
    if (message_id != upload_request_id_ || upload_token_.empty()) return;
    auto value = CefParseJSON(result, result_size, JSON_PARSER_RFC);
    auto data = value ? value->GetDictionary() : nullptr;
    if (!success || !data) {
        std::fprintf(stderr, "<4>mowser: upload failed at stage %d: %.*s\n", upload_stage_, int(result_size), static_cast<const char *>(result));
        upload_token_.clear(); upload_paths_.clear(); return;
    }
    auto params = CefDictionaryValue::Create();
    std::string method;
    if (upload_stage_ == 0) {
        params->SetString("query", "input[data-mowser-upload=\"" + upload_token_ + "\"]");
        method = "DOM.performSearch"; upload_stage_ = 1;
    } else if (upload_stage_ == 1) {
        if (data->GetInt("resultCount") != 1) { upload_token_.clear(); return; }
        upload_search_ = data->GetString("searchId");
        params->SetString("searchId", upload_search_);
        params->SetInt("fromIndex", 0); params->SetInt("toIndex", 1);
        method = "DOM.getSearchResults"; upload_stage_ = 2;
    } else if (upload_stage_ == 2) {
        auto nodes = data->GetList("nodeIds");
        if (!nodes || nodes->GetSize() != 1) { upload_token_.clear(); return; }
        auto paths = CefListValue::Create();
        for (size_t i = 0; i < upload_paths_.size(); ++i) paths->SetString(i, upload_paths_[i]);
        params->SetList("files", paths); params->SetInt("nodeId", nodes->GetInt(0));
        method = "DOM.setFileInputFiles"; upload_stage_ = 3;
    } else {
        params->SetString("searchId", upload_search_);
        browser->GetHost()->ExecuteDevToolsMethod(++devtools_id_, "DOM.discardSearchResults", params);
        upload_token_.clear(); upload_paths_.clear(); return;
    }
    upload_request_id_ = ++devtools_id_;
    browser->GetHost()->ExecuteDevToolsMethod(upload_request_id_, method, params);
}

void Client::respond_script_dialog(bool accepted, const std::string &text) {
    auto callback = script_dialog_; script_dialog_ = nullptr;
    if (callback) callback->Continue(accepted, text);
}

bool Client::OnFileDialog(CefRefPtr<CefBrowser>, FileDialogMode mode,
    const CefString &title, const CefString &, const std::vector<CefString> &filters,
    const std::vector<CefString> &extensions, const std::vector<CefString> &,
    CefRefPtr<CefFileDialogCallback> callback) {
    std::fprintf(stderr, "<6>mowser: file chooser requested, mode=%d filters=%zu extensions=%zu\n", int(mode), filters.size(), extensions.size());
    if (!sink_ || file_dialog_ || (mode != FILE_DIALOG_OPEN && mode != FILE_DIALOG_OPEN_MULTIPLE)) {
        callback->Cancel(); return true;
    }
    file_dialog_ = callback;
    std::vector<CefString> accepted = extensions;
    if (accepted.empty()) accepted = filters;
    sink_->sink_file_dialog(title.ToString(), mode == FILE_DIALOG_OPEN_MULTIPLE, accepted);
    return true;
}

bool Client::OnJSDialog(CefRefPtr<CefBrowser>, const CefString &origin, JSDialogType type,
    const CefString &message, const CefString &text, CefRefPtr<CefJSDialogCallback> callback,
    bool &suppress) {
    if (!sink_ || script_dialog_) { suppress = true; return false; }
    script_dialog_ = callback;
    sink_->sink_script_dialog(origin.ToString(), type == JSDIALOGTYPE_PROMPT ? "prompt" :
        (type == JSDIALOGTYPE_CONFIRM ? "confirm" : "alert"), message.ToString(), text.ToString());
    return true;
}

bool Client::OnBeforeUnloadDialog(CefRefPtr<CefBrowser> browser, const CefString &message,
    bool, CefRefPtr<CefJSDialogCallback> callback) {
    if (!sink_ || script_dialog_) { callback->Continue(false, ""); return true; }
    script_dialog_ = callback;
    sink_->sink_script_dialog(browser->GetMainFrame()->GetURL().ToString(), "confirm",
        "Leave this page? " + message.ToString(), "");
    return true;
}

bool Client::OnBeforeBrowse(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
    CefRefPtr<CefRequest> request, bool, bool) {
    if (!frame->IsMain()) return false;
    std::string url = request->GetURL().ToString();
    // The OSR/Alloy view cannot host Chromium's native install prompt. Route
    // store navigation through the same-profile Chrome window before it loads.
    if (is_extension_store_url(url)) {
        open_extension_window(url);
        return true;
    }
    if (frame->IsMain()) cancel_dialogs();
    std::transform(url.begin(), url.end(), url.begin(), [](unsigned char c) { return std::tolower(c); });
    const bool allowed = url.starts_with("https://") || url.starts_with("http://") ||
        url.starts_with("file://") || url.starts_with("chrome-extension://") ||
        url == "about:blank" || url.starts_with("about:blank#") || url.starts_with("blob:");
    if (!allowed && sink_ && frame->IsMain())
        sink_->sink_load_failed(request->GetURL().ToString(), "unsupported address type");
    return !allowed;
}

void Client::OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                         TransitionType transition_type) {
    // MAIN FRAME ONLY, here and in every handler below. A modern store page is
    // dozens of iframes -- adverts, video embeds, payment widgets -- and each
    // one starting and finishing would have the shell's status line flickering
    // through a dozen "loading" states for one navigation a person made.
    if (!frame->IsMain() || sink_ == nullptr) {
        return;
    }
    sink_->sink_load_started(frame->GetURL().ToString());
}

void Client::OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                       int httpStatusCode) {
    if (!frame->IsMain() || sink_ == nullptr) {
        return;
    }
    sink_->sink_load_finished(frame->GetURL().ToString(), httpStatusCode);
}

void Client::OnLoadError(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                         ErrorCode errorCode, const CefString &errorText,
                         const CefString &failedUrl) {
    if (!frame->IsMain() || sink_ == nullptr) {
        return;
    }
    // ERR_ABORTED is what a navigation that was replaced by another one
    // reports, which happens on every redirect and every time somebody presses
    // back quickly. It is not a failure and must not put an error on the TV.
    if (errorCode == ERR_ABORTED) {
        return;
    }
    std::string reason = errorText.ToString();
    if (reason.empty()) {
        reason = "the page could not be loaded";
    }
    sink_->sink_load_failed(failedUrl.ToString(), reason);
}

void Client::OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) {
    if (sink_ != nullptr) {
        sink_->sink_title(title.ToString());
    }
}

void Client::OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                             const CefString &url) {
    if (!frame->IsMain() || sink_ == nullptr) {
        return;
    }
    sink_->sink_url(url.ToString());
}

bool Client::OnProcessMessageReceived(CefRefPtr<CefBrowser> browser,
    CefRefPtr<CefFrame> frame, CefProcessId source_process,
    CefRefPtr<CefProcessMessage> message) {
    if (source_process != PID_RENDERER) return false;
    if (message->GetName() == "mowser.file_input") {
        auto args = message->GetArgumentList();
        if (sink_ && args->GetSize() == 3 && upload_token_.empty()) {
            upload_token_ = args->GetString(0).ToString();
            if (upload_token_.size() > 64 || upload_token_.find_first_not_of("0123456789abcdef") != std::string::npos) {
                upload_token_.clear(); return true;
            }
            std::vector<CefString> extensions;
            std::string accept = args->GetString(1).ToString();
            size_t start = 0;
            while (start < accept.size()) {
                const auto end = accept.find(',', start);
                extensions.emplace_back(accept.substr(start, end == std::string::npos ? end : end - start));
                if (end == std::string::npos) break;
                start = end + 1;
            }
            sink_->sink_file_dialog("Choose file", args->GetBool(2), extensions);
        }
        return true;
    }
    if (message->GetName() != "mowser.keyboard_context")
        return false;
    auto args = message->GetArgumentList();
    if (sink_ && args->GetSize() == 5) {
        sink_->sink_keyboard_context(args->GetBool(0), args->GetString(1).ToString(),
            args->GetString(2).ToString(), args->GetString(3).ToString(),
            args->GetString(4).ToString());
    }
    return true;
}

}  // namespace mowser
