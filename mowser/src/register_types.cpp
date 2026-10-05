// The GDExtension entry point: how Godot learns MowserView exists.

#include <gdextension_interface.h>

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "mowser_view.h"

using namespace godot;

void initialize_mowser_module(ModuleInitializationLevel level) {
    if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    GDREGISTER_CLASS(mowser::MowserView);
}

void uninitialize_mowser_module(ModuleInitializationLevel level) {
    if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    // THE ENGINE GOES DOWN WITH THE EXTENSION, and this is the only place it
    // can: CefShutdown must run on the thread that called CefInitialize, with
    // no browsers left alive. By this point the scene tree is gone, so every
    // MowserView has already run _exit_tree and closed its page.
    //
    // Skipped in the editor, where the extension is loaded and unloaded
    // repeatedly by tool scripts and reloads -- CEF cannot be re-initialised
    // in a process that has shut it down, so a shutdown on the first reload
    // would leave the rest of an editor session with a browser that can never
    // start again. The appliance loads this once and exits once.
    if (!Engine::get_singleton()->is_editor_hint()) {
        mowser::Runtime::shutdown();
    }
}

extern "C" {
GDExtensionBool GDE_EXPORT mowser_library_init(
    GDExtensionInterfaceGetProcAddress p_get_proc_address,
    const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library,
                                                   r_initialization);
    init_obj.register_initializer(initialize_mowser_module);
    init_obj.register_terminator(uninitialize_mowser_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}
