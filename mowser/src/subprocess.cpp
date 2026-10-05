// mowser-helper -- every Chromium process that is not the browser process.
//
// THIS FILE IS SHORT AND IT IS NOT OPTIONAL. Chromium is multi-process: the
// renderer that runs a page's JavaScript, the GPU process, and the utility
// processes are separate programs, and CEF starts them by executing a binary
// with a --type= argument. Ordinarily that binary is the application itself,
// which requires CefExecuteProcess to be the FIRST thing main() does -- before
// any library has initialised anything, because a renderer process must not
// inherit a half-built browser.
//
// The shell's main() belongs to Godot. So this exists instead: a binary whose
// entire job is to be re-executed by CEF, named to CefSettings::
// browser_subprocess_path. It links libcef and NOTHING ELSE -- no godot-cpp,
// no shell code -- both because it needs none of it and because everything
// linked here is loaded into every renderer Chromium spawns.
//
// It must never print. Its stdout and stderr belong to Chromium's own IPC and
// logging, and a stray line here surfaces as a corrupt message on a channel
// somebody else is parsing.

#include "include/cef_app.h"
#include "include/cef_dom.h"
#include "include/cef_process_message.h"
#include "include/cef_render_process_handler.h"
#include "include/cef_v8.h"

class UploadHandler : public CefV8Handler {
public:
    bool Execute(const CefString &, CefRefPtr<CefV8Value>, const CefV8ValueList &args,
        CefRefPtr<CefV8Value> &result, CefString &) override {
        if (args.size() != 3) return false;
        auto frame = CefV8Context::GetCurrentContext()->GetFrame();
        auto message = CefProcessMessage::Create("mowser.file_input");
        auto values = message->GetArgumentList();
        values->SetString(0, args[0]->GetStringValue());
        values->SetString(1, args[1]->GetStringValue());
        values->SetBool(2, args[2]->GetBoolValue());
        frame->SendProcessMessage(PID_BROWSER, message);
        result = CefV8Value::CreateUndefined();
        return true;
    }
private:
    IMPLEMENT_REFCOUNTING(UploadHandler);
};

// Only field metadata crosses IPC. Never copy a field value, selection or
// password into the shell; Chromium remains the owner of the live editor.
class KeyboardContextApp : public CefApp, public CefRenderProcessHandler {
public:
    CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override { return this; }
    void OnContextCreated(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>,
        CefRefPtr<CefV8Context> context) override {
        context->GetGlobal()->SetValue("__mowserUpload", CefV8Value::CreateFunction("upload", new UploadHandler()), V8_PROPERTY_ATTRIBUTE_NONE);
        CefRefPtr<CefV8Value> result;
        CefRefPtr<CefV8Exception> exception;
        // Keep the native bridge in a closure. The page never receives file
        // paths; Chromium sets input.files only after the controller picker.
        context->Eval(R"JS((() => {
            const choose = window.__mowserUpload;
            delete window.__mowserUpload;
            // Native File System Access pickers have no controller surface.
            // Feature detection should fall back to the supported file input.
            for (const name of ['showOpenFilePicker', 'showSaveFilePicker', 'showDirectoryPicker']) {
                Object.defineProperty(window, name, {value: undefined, configurable: false});
            }
            window.addEventListener('click', event => {
                const input = event.composedPath().find(node => node instanceof HTMLInputElement && node.type === 'file');
                if (!input) return;
                event.preventDefault();
                if (input.disabled || !(event.isTrusted || navigator.userActivation.isActive)) return;
                const token = Array.from(crypto.getRandomValues(new Uint32Array(4)), n => n.toString(16)).join('');
                input.setAttribute('data-mowser-upload', token);
                choose(token, input.accept, input.multiple);
            }, true);
            const show = HTMLInputElement.prototype.showPicker;
            HTMLInputElement.prototype.showPicker = function() {
                if (this.type === 'file') this.click(); else show.call(this);
            };
        })())JS", "mowser://upload", 0, result, exception);
    }
    void OnFocusedNodeChanged(CefRefPtr<CefBrowser> browser,
                              CefRefPtr<CefFrame> frame,
                              CefRefPtr<CefDOMNode> node) override {
        if (!frame) return;
        auto message = CefProcessMessage::Create("mowser.keyboard_context");
        auto args = message->GetArgumentList();
        const bool editable = node && node->IsElement() && node->IsEditable() &&
            !node->HasElementAttribute("readonly") && !node->HasElementAttribute("disabled");
        args->SetBool(0, editable);
        for (int i = 1; i <= 4; ++i) args->SetString(i, "");
        if (editable) {
            auto type = node->GetElementAttribute("type");
            if (node->GetElementTagName() == "TEXTAREA") type = "multiline";
            args->SetString(1, type);
            args->SetString(2, node->GetElementAttribute("inputmode"));
            std::string label = node->GetElementAttribute("aria-label").ToString();
            if (label.empty()) label = node->GetElementAttribute("placeholder").ToString();
            args->SetString(3, label.substr(0, 160));
            args->SetString(4, node->GetElementAttribute("enterkeyhint"));
        }
        frame->SendProcessMessage(PID_BROWSER, message);
    }
private:
    IMPLEMENT_REFCOUNTING(KeyboardContextApp);
};

int main(int argc, char *argv[]) {
    CefMainArgs main_args(argc, argv);
    return CefExecuteProcess(main_args, new KeyboardContextApp(), nullptr);
}
