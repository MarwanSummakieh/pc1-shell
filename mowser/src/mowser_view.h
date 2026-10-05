#pragma once

// MowserView -- a web page as a Control, with the shell in charge of it.
//
// THE WHOLE POINT OF THIS CLASS IS WHAT IT DOES NOT DO. It navigates, paints
// and takes input, and it has no opinion about any of the rest: no cursor is
// drawn here, no error page is rendered here, no keyboard is summoned here, no
// button is bound here. Every one of those is the shell's, in GDScript, in the
// same theme and the same focus tables as the rail -- because the reason for
// embedding the engine at all was to stop a browser making those decisions on
// this machine's behalf. What this exposes is the smallest surface that lets
// browser_screen.gd be the browser.
//
// THE PAD DRIVES THIS BY METHOD CALL, NOT BY INJECTION, and that is the second
// thing embedding bought. The pad bridge (shell/src/pad_keys.gd) exists because
// the shell could not reach inside a foreign X client: it spawns an xdotool
// process per event -- twenty a second for a held stick -- and aims them at
// whatever gamescope has focused, which is a guess dressed as a mechanism.
// A page inside the shell's own process needs none of that. move_pointer and
// click below are function calls into the engine, with real coordinates in this
// control's own space, delivered to the page that is actually on screen.

#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

#include "mowser_client.h"

namespace mowser {

class MowserView : public godot::Control {
    GDCLASS(MowserView, godot::Control)

public:
    MowserView();
    ~MowserView() override;

    void _ready() override;
    void _process(double delta) override;
    void _draw() override;
    void _exit_tree() override;

    // --- Navigation. Each is a no-op with a warning when the engine is down,
    // rather than a crash: an image missing its payload must still give the
    // shell a screen it can draw something honest on.
    void load_url(const godot::String &url);
    void reload();
    void stop_loading();
    void go_back();
    void go_forward();
    bool can_go_back() const;
    bool can_go_forward() const;
    bool is_loading() const;
    bool is_popup_open() const;
    godot::String get_page_url() const;
    godot::String get_page_title() const;

    // --- Whether there is an engine at all, for the shell's honest sentence.
    bool is_engine_running() const;
    godot::String get_engine_failure() const;

    // --- Input, in this control's own pixel space.
    void set_pointer(const godot::Vector2 &position);
    godot::Vector2 get_pointer() const;
    void move_pointer(const godot::Vector2 &delta);
    // button: 1 left, 2 middle, 3 right -- X's numbering, which is what the
    // pad bridge's "pointer" dialect already speaks, so the shell's existing
    // vocabulary carries over unchanged.
    void click(int button, bool pressed);
    void scroll(const godot::Vector2 &delta);
    // Text from the shell's on-screen keyboard. The engine has no idea a
    // keyboard exists; this is just characters arriving at whatever the page
    // has focused.
    void type_text(const godot::String &text);
    // The editing keys a keyboard would send that are not characters:
    // "Return", "BackSpace", "Tab", "Up", "Down", "Left", "Right", "Escape".
    void send_editing_key(const godot::String &key_name);
    void reveal_focused_field();
    void set_download_directory(const godot::String &path);
    void cancel_download(int64_t id);
    void respond_file_dialog(const godot::PackedStringArray &paths);
    void respond_script_dialog(bool accepted, const godot::String &text);

protected:
    static void _bind_methods();

private:
    // The client cannot hold the node directly -- it outlives it during
    // teardown -- so it holds this, and this is cleared before the node dies.
    // See mowser_client.h.
    class Sink : public ViewSink {
    public:
        explicit Sink(MowserView *view) : view_(view) {}
        void detach() { view_ = nullptr; }
        void sink_view_size(int &width, int &height) override;
        void sink_paint(const void *buffer, int width, int height) override;
        void sink_browser_ready() override;
        void sink_load_started(const std::string &url) override;
        void sink_load_finished(const std::string &url, int http_status) override;
        void sink_load_failed(const std::string &url, const std::string &reason) override;
        void sink_title(const std::string &title) override;
        void sink_url(const std::string &url) override;
        void sink_keyboard_context(bool editable, const std::string &type,
            const std::string &mode, const std::string &label, const std::string &action) override;
        void sink_download(uint32_t id, const std::string &path, int64_t received,
            int64_t total, const std::string &state, const std::string &detail) override;
        void sink_file_dialog(const std::string &title, bool multiple,
            const std::vector<CefString> &extensions) override;
        void sink_script_dialog(const std::string &origin, const std::string &type,
            const std::string &message, const std::string &default_text) override;
        void sink_popup(const std::string &url) override;

    private:
        MowserView *view_;
    };

    // Called by the sink on the shell's main thread with one BGRA frame.
    void _on_engine_paint(const void *buffer, int width, int height);

    void ensure_browser();
    void close_browser();
    CefRefPtr<CefBrowserHost> host() const;
    CefMouseEvent mouse_event() const;

    Sink *sink_ = nullptr;
    CefRefPtr<Client> client_;

    godot::Ref<godot::ImageTexture> texture_;
    godot::Ref<godot::Image> image_;
    godot::PackedByteArray pixels_;
    int painted_width_ = 0;
    int painted_height_ = 0;

    godot::Vector2 pointer_;
    godot::Vector2i last_size_;

    // Said once each, at the two boundaries a blank page can hide behind.
    bool logged_paint_ = false;
    bool logged_draw_ = false;

    // Set before the browser exists so the shell can call load_url in the same
    // frame it adds the node, which is how every other screen in this shell is
    // written.
    godot::String pending_url_;
    godot::String page_url_;
    godot::String page_title_;
    bool loading_ = false;
    godot::String download_directory_;
};

}  // namespace mowser
