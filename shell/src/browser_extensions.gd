extends Node

signal completed(action: String, result: Dictionary)

const ROOT := "user://browser-extensions"
const HELPER := "/usr/lib/marwanos/browser_extensions.py"
var _worker: Thread

static func installed_entries() -> Array:
	var profile := OS.get_environment("HOME").path_join(".local/share/marwanos/mowser/Default")
	var preferences: Variant = JSON.parse_string(FileAccess.get_file_as_string(profile.path_join("Preferences"))) if FileAccess.file_exists(profile.path_join("Preferences")) else {}
	var registered: Dictionary = preferences.get("extensions", {}).get("settings", {}) if preferences is Dictionary else {}
	var result: Array = []
	var packages := profile.path_join("Extensions")
	for uid in DirAccess.get_directories_at(packages):
		var valid_id := uid.length() == 32
		for value in uid.to_ascii_buffer():
			if value < 97 or value > 112: valid_id = false
		if not valid_id: continue
		var state: Dictionary = registered.get(uid, {})
		if state.is_empty(): continue
		var reasons: Variant = state.get("disable_reasons", [])
		if (reasons is Array and not reasons.is_empty()) or (reasons is int and reasons != 0): continue
		var versions := Array(DirAccess.get_directories_at(packages.path_join(uid)))
		versions.sort_custom(func(a: String, b: String): return a.naturalnocasecmp_to(b) > 0)
		for version: String in versions:
			var root := packages.path_join(uid).path_join(version)
			var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("manifest.json")))
			if not manifest is Dictionary: continue
			var page := str(manifest.get("action", manifest.get("browser_action", {})).get("default_popup", ""))
			if page.is_empty(): page = str(manifest.get("options_ui", {}).get("page", manifest.get("options_page", "")))
			if page.is_empty() or page.begins_with("/") or page.contains(":") or page.contains("\\") or page.split("/").has(".."): break
			var caption := str(manifest.get("name", "Extension"))
			if caption.begins_with("__MSG_") and caption.ends_with("__"):
				var locale := str(manifest.get("default_locale", "en"))
				if locale.is_valid_identifier():
					var messages: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("_locales").path_join(locale).path_join("messages.json")))
					if messages is Dictionary: caption = str(messages.get(caption.trim_prefix("__MSG_").trim_suffix("__"), {}).get("message", caption))
			result.append({"id": "open:" + uid, "label": caption, "url": "chrome-extension://" + uid + "/" + page})
			break
	return result

static func entries() -> Array:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT.path_join("extensions.json"))) if FileAccess.file_exists(ROOT.path_join("extensions.json")) else []
	return saved if saved is Array else []

static func enabled_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for entry: Dictionary in entries():
		var uid := str(entry.get("uid", ""))
		if entry.get("enabled", false) and uid.length() == 32 and uid.is_valid_hex_number():
			paths.append(ProjectSettings.globalize_path(ROOT.path_join(uid)))
	return paths

static func page_url(entry: Dictionary, active_paths: PackedStringArray) -> String:
	for path in active_paths:
		if path.get_file() != str(entry.get("uid", "")): continue
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("manifest.json")))
		if not manifest is Dictionary: return ""
		var page := str(manifest.get("options_page", ""))
		var options: Variant = manifest.get("options_ui", {})
		if options is Dictionary: page = str(options.get("page", page))
		var action: Variant = manifest.get("action", {})
		if page.is_empty() and action is Dictionary: page = str(action.get("default_popup", ""))
		if page.is_empty() or page.begins_with("/") or page.contains(":") or page.contains("\\") or page.split("/").has(".."):
			return ""
		# Chromium hashes an unpacked package's canonical path unless its
		# manifest supplies a stable public key. The engine returns that path.
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(Marshalls.base64_to_raw(str(manifest.key)) if manifest.has("key") else path.to_utf8_buffer())
		var id := ""
		for byte in hash.finish().slice(0, 16):
			id += "abcdefghijklmnop"[byte >> 4] + "abcdefghijklmnop"[byte & 15]
		return "chrome-extension://" + id + "/" + page
	return ""

static func run_helper(action: String, value: String = "", digest: String = "") -> Dictionary:
	var helper := OS.get_environment("MARWANOS_BROWSER_EXTENSIONS_HELPER")
	if helper.is_empty(): helper = HELPER
	var python := OS.get_environment("MARWANOS_BROWSER_EXTENSIONS_PYTHON")
	if python.is_empty(): python = "python3"
	if not FileAccess.file_exists(helper):
		return {"ok": false, "error": "The extension installer is missing from this image."}
	var output: Array = []
	var code := OS.execute(python, PackedStringArray([helper, "--root", ProjectSettings.globalize_path(ROOT), action, value, digest]), output, false)
	var result: Variant = JSON.parse_string("".join(output))
	if result is Dictionary: return result
	return {"ok": false, "error": "The extension installer could not run (%d)." % code}

func start(action: String, value: String = "", digest: String = "") -> bool:
	if _worker != null: return false
	_worker = Thread.new()
	_worker.start(func():
		var result := run_helper(action, value, digest)
		_finish.call_deferred(action, result))
	return true

func _finish(action: String, result: Dictionary) -> void:
	if _worker == null: return
	_worker.wait_to_finish()
	_worker = null
	if is_inside_tree(): completed.emit(action, result)

func _exit_tree() -> void:
	if _worker != null:
		_worker.wait_to_finish()
		_worker = null
