#pragma once
#include "include/cef_client.h"
#include <string>

namespace mowser {
// Chrome owns installation, signature verification, permissions, updates and
// the extension registry. Its side panel shares the OSR pages' profile.
bool open_extension_window(const std::string &url);
bool extension_window_open();
void extension_window_command(const std::string &command);
void set_extension_panel_bounds(int x, int y, int width, int height);
unsigned long extension_panel_handle();
std::string extension_page_url();
bool is_extension_store_url(const std::string &url);
CefRefPtr<CefClient> extension_default_client();
}
