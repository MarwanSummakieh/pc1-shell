#include "mowser_view.h"
#include "mowser_extensions.h"

#include <algorithm>
#include <filesystem>

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace mowser {
namespace {

// What CEF is asked to paint at, at most. The shell runs on a television and
// the page is a document, not a game: a store page repainting 60 times a second
// would spend the machine's memory bandwidth on a scroll animation nobody can
// see the smoothness of from a sofa. This also bounds the swizzle cost below.
constexpr int kFrameRate = 30;

// Virtual-key codes for the editing keys. These are Windows VK values because
// that is what CefKeyEvent::windows_key_code means on every platform -- CEF
// normalises to them -- and spelling them as numbers with names next to them is
// clearer here than pulling in a header of 200 we do not use.
struct EditingKey {
    const char *name;
    int vk;
};
constexpr EditingKey kEditingKeys[] = {
    {"Return", 0x0D},   {"BackSpace", 0x08}, {"Tab", 0x09},   {"Escape", 0x1B},
    {"Left", 0x25},     {"Up", 0x26},        {"Right", 0x27}, {"Down", 0x28},
    {"Home", 0x24},     {"End", 0x23},       {"PageUp", 0x21}, {"PageDown", 0x22},
    {"Delete", 0x2E},
};

}  // namespace

// ---------------------------------------------------------------------------
// The sink: engine callbacks, forwarded to the node while it is alive.

void MowserView::Sink::sink_view_size(int &width, int &height) {
    if (view_ == nullptr) {
        width = 0;
        height = 0;
        return;
    }
    const Vector2 size = view_->get_size();
    width = static_cast<int>(size.x);
    height = static_cast<int>(size.y);
}

void MowserView::Sink::sink_paint(const void *buffer, int width, int height) {
    if (view_ != nullptr) {
        view_->_on_engine_paint(buffer, width, height);
    }
}

void MowserView::Sink::sink_browser_ready() {
    if (view_ == nullptr) {
        return;
    }
    // REPLAY WHAT WAS ASKED FOR BEFORE THERE WAS ANYTHING TO ASK. The shell
    // builds this node, tells it what to show and adds it to the tree in the
    // same frame -- which is how every other screen here is written -- and all
    // of that happens while CreateBrowser is still in flight.
    UtilityFunctions::print(String("<6>mowser: browser ready, pending '") +
                            view_->pending_url_ + String("'"));
    if (!view_->pending_url_.is_empty()) {
        // A COPY, not the member by reference. load_url's first act is to
        // assign to pending_url_, so passing the member itself hands a
        // reference to the very thing being overwritten -- self-assignment
        // that is fine today and is exactly the sort of aliasing that stops
        // being fine when the assignment grows a step.
        const String pending = view_->pending_url_;
        view_->load_url(pending);
    }
    if (CefRefPtr<CefBrowserHost> host = view_->host()) {
        // THE SIZE AND THE FIRST FRAME, both explicitly. The control was
        // almost certainly laid out while the browser did not exist, so the
        // engine has never been told what size it is; and a windowless browser
        // does not necessarily paint until something asks it to. Invalidate is
        // what turns "created" into "on screen".
        host->WasResized();
        host->Invalidate(PET_VIEW);
    }
}


void MowserView::Sink::sink_load_started(const std::string &url) {
    if (view_ == nullptr) return;
    view_->loading_ = true;
    view_->page_url_ = String(url.c_str());
    view_->emit_signal("page_started", view_->page_url_);
}

void MowserView::Sink::sink_load_finished(const std::string &url, int http_status) {
    if (view_ == nullptr) return;
    view_->loading_ = false;
    view_->page_url_ = String(url.c_str());
    view_->emit_signal("page_finished", view_->page_url_, http_status);
}

void MowserView::Sink::sink_load_failed(const std::string &url, const std::string &reason) {
    if (view_ == nullptr) return;
    view_->loading_ = false;
    view_->emit_signal("page_failed", String(url.c_str()), String(reason.c_str()));
}

void MowserView::Sink::sink_title(const std::string &title) {
    if (view_ == nullptr) return;
    view_->page_title_ = String(title.c_str());
    view_->emit_signal("title_changed", view_->page_title_);
}

void MowserView::Sink::sink_url(const std::string &url) {
    if (view_ == nullptr) return;
    view_->page_url_ = String(url.c_str());
    view_->emit_signal("url_changed", view_->page_url_);
}

// ---------------------------------------------------------------------------

MowserView::MowserView() { sink_ = new Sink(this); }

MowserView::~MowserView() {
    close_browser();
    delete sink_;
    sink_ = nullptr;
}

void MowserView::Sink::sink_keyboard_context(bool editable, const std::string &type,
    const std::string &mode, const std::string &label, const std::string &action) {
    if (!view_) return;
    godot::Dictionary context;
    context["editable"] = editable;
    context["type"] = String(type.c_str());
    context["mode"] = String(mode.c_str());
    context["label"] = String(label.c_str());
    context["action"] = String(action.c_str());
    view_->emit_signal("keyboard_context_changed", context);
}

void MowserView::reveal_focused_field(const godot::Rect2 &occlusion) {
    if (!client_ || !client_->browser()) return;
    auto frame = client_->browser()->GetFocusedFrame();
    if (!frame) return;
    // Metadata and geometry only: never read the editor's value. Keep the
    // document's width stable and scroll only if the floating keys cover it.
    auto script = String("requestAnimationFrame(()=>{let e=document.activeElement;") +
        "while(e&&e.shadowRoot&&e.shadowRoot.activeElement)e=e.shadowRoot.activeElement;" +
        "if(!e||e===document.body)return;e.scrollIntoView({block:'nearest',inline:'nearest'});" +
        "const r=e.getBoundingClientRect(),x=" + String::num(occlusion.position.x) +
        ",y=" + String::num(occlusion.position.y) + ",w=" + String::num(occlusion.size.x) +
        ",h=" + String::num(occlusion.size.y) + ";" +
        "if(r.right>x&&r.left<x+w&&r.bottom>y&&r.top<y+h){" +
        "const above=y-16,below=y+h+16;" +
        "const delta=above>=r.height?r.bottom-above:r.top-below;" +
        "let p=e.parentElement;while(p&&p!==document.body){" +
        "if(p.scrollHeight>p.clientHeight&&/(auto|scroll)/.test(getComputedStyle(p).overflowY)){p.scrollTop+=delta;return;}p=p.parentElement;}" +
        "window.scrollBy(0,delta);}});";
    frame->ExecuteJavaScript(script.utf8().get_data(), frame->GetURL(), 0);
}

void MowserView::_bind_methods() {
    ClassDB::bind_method(D_METHOD("respond_file_dialog", "paths"), &MowserView::respond_file_dialog);
    ClassDB::bind_method(D_METHOD("respond_script_dialog", "accepted", "text"), &MowserView::respond_script_dialog);
    ADD_SIGNAL(MethodInfo("file_dialog_requested", PropertyInfo(Variant::DICTIONARY, "request")));
    ADD_SIGNAL(MethodInfo("script_dialog_requested", PropertyInfo(Variant::DICTIONARY, "request")));
    ADD_SIGNAL(MethodInfo("popup_requested", PropertyInfo(Variant::STRING, "url")));
    ClassDB::bind_method(D_METHOD("set_download_directory", "path"), &MowserView::set_download_directory);
    ClassDB::bind_method(D_METHOD("cancel_download", "id"), &MowserView::cancel_download);
    ADD_SIGNAL(MethodInfo("download_updated", PropertyInfo(Variant::DICTIONARY, "download")));
    ClassDB::bind_method(D_METHOD("reveal_focused_field", "occlusion"), &MowserView::reveal_focused_field);
    ADD_SIGNAL(MethodInfo("keyboard_context_changed", PropertyInfo(Variant::DICTIONARY, "context")));
    ClassDB::bind_method(D_METHOD("load_url", "url"), &MowserView::load_url);
    ClassDB::bind_method(D_METHOD("reload"), &MowserView::reload);
    ClassDB::bind_method(D_METHOD("stop_loading"), &MowserView::stop_loading);
    ClassDB::bind_method(D_METHOD("go_back"), &MowserView::go_back);
    ClassDB::bind_method(D_METHOD("go_forward"), &MowserView::go_forward);
    ClassDB::bind_method(D_METHOD("can_go_back"), &MowserView::can_go_back);
    ClassDB::bind_method(D_METHOD("can_go_forward"), &MowserView::can_go_forward);
    ClassDB::bind_method(D_METHOD("is_loading"), &MowserView::is_loading);
    ClassDB::bind_method(D_METHOD("is_popup_open"), &MowserView::is_popup_open);
    ClassDB::bind_method(D_METHOD("get_page_url"), &MowserView::get_page_url);
    ClassDB::bind_method(D_METHOD("get_page_title"), &MowserView::get_page_title);
    ClassDB::bind_method(D_METHOD("is_engine_running"), &MowserView::is_engine_running);
    ClassDB::bind_method(D_METHOD("get_engine_failure"), &MowserView::get_engine_failure);
    ClassDB::bind_method(D_METHOD("set_extension_paths", "paths"), &MowserView::set_extension_paths);
    ClassDB::bind_method(D_METHOD("get_active_extension_paths"), &MowserView::get_active_extension_paths);
    ClassDB::bind_method(D_METHOD("open_extensions", "manage"), &MowserView::open_extensions);
    ClassDB::bind_method(D_METHOD("open_extension_page", "url"), &MowserView::open_extension_page);
    ClassDB::bind_method(D_METHOD("get_extension_page_url"), &MowserView::get_extension_page_url);
    ClassDB::bind_method(D_METHOD("is_extension_window_open"), &MowserView::is_extension_window_open);
    ClassDB::bind_method(D_METHOD("extension_command", "command"), &MowserView::extension_command);
    ClassDB::bind_method(D_METHOD("set_extension_panel_rect", "bounds"), &MowserView::set_extension_panel_rect);
    ClassDB::bind_method(D_METHOD("get_extension_panel_handle"), &MowserView::get_extension_panel_handle);
    ClassDB::bind_method(D_METHOD("extension_type_text", "text"), &MowserView::extension_type_text);
    ClassDB::bind_method(D_METHOD("extension_editing_key", "key_name"), &MowserView::extension_editing_key);
    ClassDB::bind_method(D_METHOD("set_pointer", "position"), &MowserView::set_pointer);
    ClassDB::bind_method(D_METHOD("get_pointer"), &MowserView::get_pointer);
    ClassDB::bind_method(D_METHOD("move_pointer", "delta"), &MowserView::move_pointer);
    ClassDB::bind_method(D_METHOD("click", "button", "pressed"), &MowserView::click);
    ClassDB::bind_method(D_METHOD("scroll", "delta"), &MowserView::scroll);
    ClassDB::bind_method(D_METHOD("type_text", "text"), &MowserView::type_text);
    ClassDB::bind_method(D_METHOD("send_editing_key", "key_name"),
                         &MowserView::send_editing_key);

    // The shell renders every one of these; none of them draws itself. See the
    // header for why that division is the whole design.
    ADD_SIGNAL(MethodInfo("page_started", PropertyInfo(Variant::STRING, "url")));
    ADD_SIGNAL(MethodInfo("page_finished", PropertyInfo(Variant::STRING, "url"),
                          PropertyInfo(Variant::INT, "http_status")));
    ADD_SIGNAL(MethodInfo("page_failed", PropertyInfo(Variant::STRING, "url"),
                          PropertyInfo(Variant::STRING, "reason")));
    ADD_SIGNAL(MethodInfo("title_changed", PropertyInfo(Variant::STRING, "title")));
    ADD_SIGNAL(MethodInfo("url_changed", PropertyInfo(Variant::STRING, "url")));
}

bool MowserView::set_extension_paths(const PackedStringArray &paths) {
    const std::string requested_root = ProjectSettings::get_singleton()->globalize_path(
        "user://browser-extensions").utf8().get_data();
    std::error_code root_error;
    const std::string root = std::filesystem::weakly_canonical(requested_root, root_error).string();
    // An empty configuration always disables remembered user extensions,
    // even if the managed directory itself is inaccessible or contains a comma.
    if (paths.is_empty()) return Runtime::set_extension_paths({}, requested_root);
    if (root_error || root.find(',') != std::string::npos) return false;
    std::vector<std::string> selected;
    for (int64_t i = 0; i < paths.size(); ++i) {
        std::filesystem::path path(paths[i].utf8().get_data());
        std::error_code error;
        // Only direct, real package directories managed by the shell may load.
        const auto resolved = std::filesystem::canonical(path, error);
        if (error || resolved.parent_path() != std::filesystem::path(root) ||
            resolved.string().find(',') != std::string::npos ||
            !std::filesystem::is_regular_file(resolved / "manifest.json", error) || error) return false;
        selected.push_back(resolved.string());
    }
    return Runtime::set_extension_paths(selected, root);
}

PackedStringArray MowserView::get_active_extension_paths() const {
    PackedStringArray result;
    for (const auto &path : Runtime::extension_paths()) result.append(String(path.c_str()));
    return result;
}

bool MowserView::open_extensions(bool manage) {
    return open_extension_window(manage ? "chrome://extensions/" :
        "https://chromewebstore.google.com/category/extensions");
}

bool MowserView::is_extension_window_open() const { return extension_window_open(); }

bool MowserView::open_extension_page(const String &url) {
    return open_extension_window(url.utf8().get_data());
}

String MowserView::get_extension_page_url() const {
    return String(extension_page_url().c_str());
}

void MowserView::extension_command(const String &command) {
    extension_window_command(command.utf8().get_data());
}

void MowserView::set_extension_panel_rect(const Rect2 &bounds) {
    set_extension_panel_bounds(int(bounds.position.x), int(bounds.position.y),
                               int(bounds.size.x), int(bounds.size.y));
}

int64_t MowserView::get_extension_panel_handle() const {
    return int64_t(extension_panel_handle());
}

void MowserView::extension_type_text(const String &text) {
    const auto handle = extension_panel_handle();
    if (!handle || text.is_empty()) return;
    // Chrome-style native windows need native X input. SendKeyEvent targets
    // the off-screen renderer and does not edit these native fields.
    Array output;
    OS::get_singleton()->execute("/usr/bin/timeout", PackedStringArray({
        "1", "xdotool", "windowfocus", "--sync", String::num_int64(handle), "type",
        "--clearmodifiers", "--delay", "0", "--", text}), output);
}

void MowserView::extension_editing_key(const String &key_name) {
    for (const EditingKey &key : kEditingKeys) {
        if (key_name == String(key.name)) {
            const auto handle = extension_panel_handle();
            if (!handle) return;
            Array output;
            OS::get_singleton()->execute("/usr/bin/timeout", PackedStringArray({
                "1", "xdotool", "windowfocus", "--sync", String::num_int64(handle),
                "key", "--clearmodifiers", key_name}), output);
            return;
        }
    }
}

void MowserView::_ready() {
    set_process(true);
    // The engine comes up on the first view that needs it rather than at
    // extension load: a boot that never opens a page should not pay 290 MB of
    // page cache and a process tree for one.
    if (!Runtime::ensure_started()) {
        UtilityFunctions::push_warning(
            String("mowser: ") + String(Runtime::failure().c_str()));
        call_deferred("emit_signal", "page_failed", pending_url_, String(Runtime::failure().c_str()));
        return;
    }
    ensure_browser();
}

void MowserView::_process(double delta) {
    (void)delta;
    if (!Runtime::running()) {
        return;
    }
    // See Runtime::pump -- once per frame across every view, and the reason
    // every callback above is safe to touch Godot objects from.
    Runtime::pump(Engine::get_singleton()->get_process_frames());

    // A control that changed shape has to tell the engine, or the page keeps
    // laying out for the old size and the texture is stretched to fit -- which
    // looks like a blurry page rather than like a bug, and is therefore the
    // kind of thing that ships.
    const Vector2i size(static_cast<int>(get_size().x), static_cast<int>(get_size().y));
    if (size != last_size_ && size.x > 0 && size.y > 0) {
        last_size_ = size;
        if (host() != nullptr) {
            host()->WasResized();
        }
    }
}

void MowserView::_draw() {
    if (texture_.is_null()) {
        return;
    }
    // THE SIZE IS THE PART THAT GOES WRONG, so it is drawn from the texture
    // when the control has none. A Control that has not been laid out reports
    // zero, draw_texture_rect into a zero rect is a silent no-op, and the
    // symptom is a black page with a healthy log saying the engine painted --
    // which is exactly the state this cost a build to diagnose.
    Vector2 size = get_size();
    if (size.x <= 0.0 || size.y <= 0.0) {
        size = Vector2(texture_->get_width(), texture_->get_height());
    }
    if (!logged_draw_) {
        logged_draw_ = true;
        UtilityFunctions::print(
            String("<6>mowser: first draw at ") + String::num_int64(int64_t(size.x)) +
            String("x") + String::num_int64(int64_t(size.y)));
    }
    draw_texture_rect(texture_, Rect2(Vector2(), size), false);
}

void MowserView::_exit_tree() {
    // Detach FIRST: from here on the engine may call the client as many times
    // as it likes and reach a sink that answers nothing.
    if (sink_ != nullptr) {
        sink_->detach();
    }
    close_browser();
}

void MowserView::_on_engine_paint(const void *buffer, int width, int height) {
    if (width <= 0 || height <= 0 || buffer == nullptr) {
        return;
    }

    const int64_t needed = static_cast<int64_t>(width) * height * 4;
    if (pixels_.size() != needed) {
        pixels_.resize(needed);
        // Force the texture to be rebuilt at the new size below.
        painted_width_ = 0;
    }

    // BGRA -> RGBA, by hand, because Godot has no BGRA8 image format.
    //
    // THE COST IS REAL AND BOUNDED: eight megabytes a paint at 1080p, and CEF
    // only paints on damage, capped at kFrameRate. The zero-copy alternative is
    // to upload the buffer unswizzled and swap the channels in a canvas shader
    // on the GPU -- which is the right optimisation the first time a page makes
    // this show up in a frame time, and is deliberately not the first version:
    // a shader that silently draws the wrong colours is much harder to notice
    // than a loop that does not.
    const uint8_t *src = static_cast<const uint8_t *>(buffer);
    uint8_t *dst = pixels_.ptrw();
    for (int64_t i = 0; i < needed; i += 4) {
        dst[i + 0] = src[i + 2];
        dst[i + 1] = src[i + 1];
        dst[i + 2] = src[i + 0];
        dst[i + 3] = src[i + 3];
    }

    if (!logged_paint_) {
        logged_paint_ = true;
        // The CONTROL's size next to the ENGINE's, because a mismatch here is
        // the whole bug class: CEF paints at whatever GetViewRect said, and
        // GetViewRect falls back to the design surface when the control has
        // not been laid out.
        UtilityFunctions::print(
            String("<6>mowser: view paint ") + String::num_int64(width) + String("x") +
            String::num_int64(height) + String(", control is ") +
            String::num_int64(int64_t(get_size().x)) + String("x") +
            String::num_int64(int64_t(get_size().y)));
    }

    if (painted_width_ != width || painted_height_ != height || texture_.is_null()) {
        painted_width_ = width;
        painted_height_ = height;
        image_ = Image::create_from_data(width, height, false, Image::FORMAT_RGBA8, pixels_);
        texture_ = ImageTexture::create_from_image(image_);
    } else {
        image_->set_data(width, height, false, Image::FORMAT_RGBA8, pixels_);
        texture_->update(image_);
    }

    queue_redraw();
}

void MowserView::ensure_browser() {
    if (client_ != nullptr || !Runtime::running()) {
        return;
    }

    client_ = new Client(sink_);
    client_->set_download_directory(download_directory_.utf8().get_data());

    CefWindowInfo window_info;
    // WINDOWLESS: no X window, no parent, no compositor involvement. The page
    // exists only as the buffer that arrives in OnPaint. This is the line that
    // makes mowser an engine rather than a browser.
    window_info.SetAsWindowless(0);

    CefBrowserSettings settings;
    settings.windowless_frame_rate = kFrameRate;

    // AN OPAQUE BACKGROUND, AND WITHOUT IT THE PAGE IS INVISIBLE RATHER THAN
    // BLANK. CefBrowserSettings::background_color defaults to 0, which for a
    // windowless browser means TRANSPARENT -- so every pixel the page does not
    // explicitly paint arrives with alpha 0 and draws as nothing at all. On a
    // shell whose own background is nearly black, "nothing at all" and "a page
    // that failed to load" are the same picture, which is how this cost three
    // rounds of diagnostics that all said the paint path was working. It was:
    // it was painting transparency, faithfully.
    //
    // White rather than the shell's colour, because this is what a browser
    // shows for a page with no background of its own, and a document that
    // renders dark-on-dark because the shell chose the backdrop would be this
    // project deciding how somebody else's page looks.
    settings.background_color = CefColorSetARGB(255, 255, 255, 255);

    const String url = pending_url_.is_empty() ? String("about:blank") : pending_url_;
    CefBrowserHost::CreateBrowser(window_info, client_, url.utf8().get_data(), settings,
                                  nullptr, nullptr);
}

void MowserView::close_browser() {
    if (client_ == nullptr) {
        return;
    }
    // CEF callbacks can outlive the Godot node and its Sink allocation.
    client_->detach();
    if (CefRefPtr<CefBrowser> browser = client_->browser()) {
        // force_close: there is nobody to answer a beforeunload prompt on this
        // machine, and a page that refuses to close would hold the screen.
        browser->GetHost()->CloseBrowser(true);
    }
    client_ = nullptr;
}

CefRefPtr<CefBrowserHost> MowserView::host() const {
    if (client_ == nullptr) {
        return nullptr;
    }
    CefRefPtr<CefBrowser> browser = client_->browser();
    return browser ? browser->GetHost() : nullptr;
}

CefMouseEvent MowserView::mouse_event() const {
    CefMouseEvent event;
    event.x = static_cast<int>(pointer_.x);
    event.y = static_cast<int>(pointer_.y);
    event.modifiers = 0;
    return event;
}

// ---------------------------------------------------------------------------
// Navigation

void MowserView::load_url(const String &url) {
    // EVERY CALL, WITH ITS LENGTH AND WHO IS ASKING. The previous version
    // logged only on the branch that had a browser, which meant the one thing
    // worth knowing -- what the shell actually handed across the language
    // boundary, and when -- was invisible on the path that mattered.
    UtilityFunctions::print(String("<6>mowser: load_url(len ") +
                            String::num_int64(url.length()) + String(") '") + url +
                            String("' client=") +
                            String(client_ != nullptr ? "yes" : "no") +
                            String(" browser=") +
                            String((client_ != nullptr && client_->browser()) ? "yes" : "no"));
    pending_url_ = url;
    if (client_ == nullptr) {
        // Called before _ready, which is how the shell writes every other
        // screen: build the node, tell it what to show, add it to the tree.
        return;
    }
    if (CefRefPtr<CefBrowser> browser = client_->browser()) {
        // The URL is logged because "which page is it actually on" is the
        // other half of every blank-page question, and the answer has already
        // been about:blank once (see Sink::sink_browser_ready).
        UtilityFunctions::print(String("<6>mowser: loading ") + url);
        browser->GetMainFrame()->LoadURL(url.utf8().get_data());
    }
}

void MowserView::reload() {
    if (CefRefPtr<CefBrowser> browser = client_ ? client_->browser() : nullptr) {
        browser->Reload();
    }
}

void MowserView::stop_loading() {
    if (CefRefPtr<CefBrowser> browser = client_ ? client_->browser() : nullptr) {
        browser->StopLoad();
    }
}

void MowserView::go_back() {
    if (CefRefPtr<CefBrowser> browser = client_ ? client_->browser() : nullptr) {
        browser->GoBack();
    }
}

void MowserView::go_forward() {
    if (CefRefPtr<CefBrowser> browser = client_ ? client_->browser() : nullptr) {
        browser->GoForward();
    }
}

bool MowserView::can_go_back() const {
    CefRefPtr<CefBrowser> browser = client_ ? client_->browser() : nullptr;
    return browser ? browser->CanGoBack() : false;
}

bool MowserView::can_go_forward() const {
    CefRefPtr<CefBrowser> browser = client_ ? client_->browser() : nullptr;
    return browser ? browser->CanGoForward() : false;
}

bool MowserView::is_loading() const { return loading_; }
bool MowserView::is_popup_open() const { return client_ && client_->is_popup_open(); }

String MowserView::get_page_url() const { return page_url_; }

String MowserView::get_page_title() const { return page_title_; }

bool MowserView::is_engine_running() const { return Runtime::running(); }

String MowserView::get_engine_failure() const {
    return String(Runtime::failure().c_str());
}

// ---------------------------------------------------------------------------
// Input

void MowserView::set_pointer(const Vector2 &position) {
    const Vector2 size = get_size();
    // CLAMPED TO THE PAGE, which is what makes a stick usable: a cursor that
    // can leave the control would stop generating hover and the page would go
    // quietly dead under a thumb that is still moving.
    // real_t rather than double throughout: Godot's float precision is a build
    // option, so mixing in a `0.0` literal is a type error in one configuration
    // and a silent narrowing in the other. Vector2::clamp is the engine's own
    // answer and stays correct in both.
    const Vector2 limit(std::max(size.x - real_t(1), real_t(0)),
                        std::max(size.y - real_t(1), real_t(0)));
    pointer_ = position.clamp(Vector2(), limit);
    if (CefRefPtr<CefBrowserHost> h = host()) {
        h->SendMouseMoveEvent(mouse_event(), false);
    }
}

Vector2 MowserView::get_pointer() const { return pointer_; }

void MowserView::move_pointer(const Vector2 &delta) { set_pointer(pointer_ + delta); }

void MowserView::click(int button, bool pressed) {
    CefRefPtr<CefBrowserHost> h = host();
    if (h == nullptr) {
        return;
    }
    if (pressed) h->SetFocus(true);
    CefBrowserHost::MouseButtonType type = MBT_LEFT;
    if (button == 2) {
        type = MBT_MIDDLE;
    } else if (button == 3) {
        type = MBT_RIGHT;
    }
    h->SendMouseClickEvent(mouse_event(), type, !pressed, 1);
}

void MowserView::scroll(const Vector2 &delta) {
    if (CefRefPtr<CefBrowserHost> h = host()) {
        h->SendMouseWheelEvent(mouse_event(), static_cast<int>(delta.x),
                               static_cast<int>(delta.y));
    }
}

void MowserView::type_text(const String &text) {
    CefRefPtr<CefBrowserHost> h = host();
    if (h == nullptr) {
        return;
    }
    // One CHAR event per character. Not a key press: the shell's keyboard is
    // not a keyboard, it is a picker, and what the page needs to hear is that
    // a character arrived -- which is also why this works for text the person
    // never "typed" at all, like a pasted URL.
    for (int i = 0; i < text.length(); ++i) {
        const char32_t code = text[i];
        CefKeyEvent event;
        event.type = KEYEVENT_CHAR;
        event.character = static_cast<char16_t>(code);
        event.unmodified_character = static_cast<char16_t>(code);
        event.windows_key_code = static_cast<int>(code);
        event.modifiers = 0;
        h->SendKeyEvent(event);
    }
}

void MowserView::send_editing_key(const String &key_name) {
    CefRefPtr<CefBrowserHost> h = host();
    if (h == nullptr) {
        return;
    }
    int vk = 0;
    for (const EditingKey &key : kEditingKeys) {
        if (key_name == String(key.name)) {
            vk = key.vk;
            break;
        }
    }
    if (vk == 0) {
        UtilityFunctions::push_warning(String("mowser: unknown editing key ") + key_name);
        return;
    }

    // DOWN THEN UP, both. A page that only ever sees key-downs will run its
    // handlers but never let a button release, and a form that submits on
    // keyup would simply never submit.
    CefKeyEvent down;
    down.type = KEYEVENT_RAWKEYDOWN;
    down.windows_key_code = vk;
    down.modifiers = 0;
    h->SendKeyEvent(down);

    // Return also has to arrive as a character or most text inputs will not
    // treat it as "the person finished".
    if (vk == 0x0D) {
        CefKeyEvent character;
        character.type = KEYEVENT_CHAR;
        character.windows_key_code = vk;
        character.character = '\r';
        character.unmodified_character = '\r';
        character.modifiers = 0;
        h->SendKeyEvent(character);
    }

    CefKeyEvent up;
    up.type = KEYEVENT_KEYUP;
    up.windows_key_code = vk;
    up.modifiers = 0;
    h->SendKeyEvent(up);
}

void MowserView::set_download_directory(const String &path) {
    download_directory_ = path;
    if (client_) client_->set_download_directory(path.utf8().get_data());
}

void MowserView::cancel_download(int64_t id) {
    if (client_ && id >= 0) client_->cancel_download(static_cast<uint32_t>(id));
}

void MowserView::respond_file_dialog(const PackedStringArray &paths) {
    std::vector<CefString> selected;
    for (int64_t i = 0; i < paths.size(); ++i) selected.emplace_back(paths[i].utf8().get_data());
    if (client_) client_->respond_file_dialog(selected);
}

void MowserView::respond_script_dialog(bool accepted, const String &text) {
    if (client_) client_->respond_script_dialog(accepted, text.utf8().get_data());
}

void MowserView::Sink::sink_file_dialog(const std::string &title, bool multiple,
    const std::vector<CefString> &extensions) {
    if (!view_) return;
    PackedStringArray filters;
    for (const auto &filter : extensions) {
        const auto parts = String(filter.ToString().c_str()).split(";");
        for (int64_t i = 0; i < parts.size(); ++i) if (!parts[i].is_empty()) filters.append(parts[i]);
    }
    Dictionary request;
    request["title"] = String(title.c_str());
    request["multiple"] = multiple;
    request["extensions"] = filters;
    view_->call_deferred("emit_signal", "file_dialog_requested", request);
}

void MowserView::Sink::sink_script_dialog(const std::string &origin, const std::string &type,
    const std::string &message, const std::string &default_text) {
    if (!view_) return;
    Dictionary request;
    request["origin"] = String(origin.c_str()); request["type"] = String(type.c_str());
    request["message"] = String(message.c_str()); request["default"] = String(default_text.c_str());
    view_->call_deferred("emit_signal", "script_dialog_requested", request);
}

void MowserView::Sink::sink_popup(const std::string &url) {
    if (view_) view_->call_deferred("emit_signal", "popup_requested", String(url.c_str()));
}

void MowserView::Sink::sink_download(uint32_t id, const std::string &path,
    int64_t received, int64_t total, const std::string &state, const std::string &detail) {
    if (!view_) return;
    Dictionary download;
    download["id"] = static_cast<int64_t>(id);
    download["path"] = String(path.c_str());
    download["name"] = String(path.c_str()).get_file();
    download["received"] = received;
    download["total"] = total;
    download["state"] = String(state.c_str());
    download["detail"] = String(detail.c_str());
    view_->emit_signal("download_updated", download);
}

}  // namespace mowser
