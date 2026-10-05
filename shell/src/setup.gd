extends Node

## The first-run seam: whether setup is needed, and the profile it writes.
##
## Same shape as Power, Files, Settings and Info -- one screen at a time, opened
## through here, and the peers guard against each other. See setup_screen.gd for
## why first boot is the moment and why nothing on it is load-bearing.
##
## WHERE THE STATE LIVES, and why not /var/marwanos like every other seam: this
## is the ONE thing the shell writes on its own behalf rather than asking root
## for. /var/marwanos is root-owned by tmpfiles and the shell runs as `player`,
## so writing there would need a request/response seam and a privileged helper
## -- an enormous amount of machinery for a display name. The player's own home
## is already writable, already per-machine, and already survives `bootc
## upgrade` because it is under /var.
##
## The DONE MARKER is a separate file from the name on purpose. "Setup has run"
## and "somebody typed a name" are different facts, and a person who skipped
## must not be asked again just because they left the name blank.

signal setup_opened()
signal setup_closed()

const SetupScreen = preload("res://src/setup_screen.gd")

## What the Steam row opens. Duplicated from nowhere -- this is the only place
## the shell names Steam now that it is an RPM in the image rather than a
## flatpak, so `steam` is a plain binary on PATH. -gamepadui because a mouse UI
## on a machine whose only pointer is a thumbstick is not a sign-in anybody can
## complete (ADR 0011).
const STEAM_ENTRY := {
	"id": "steam.signin",
	"title": "Steam",
	"exec": ["/usr/lib/marwanos/steamctl", "signin"],
}

const DIR_NAME := ".local/share/marwanos"
const NAME_FILE := "profile-name"
const DONE_FILE := "setup-done"

var _screen: SetupScreen = null


func is_open() -> bool:
	return _screen != null


## Has first-run setup already happened on this machine?
##
## NOT ON A DESK RUN, and the first spelling of this guard was wrong in a way
## the build caught. It tested for an EMPTY $HOME on the theory that harnesses
## have none -- but the Containerfile's smoke run sets `HOME=/tmp/shell-smoke`,
## a real path, so `needed()` answered true, the setup screen opened during a
## headless start, and the build failed. MARWANOS_SHELL_WINDOWED is the flag
## this shell already uses to mean "not the appliance" (see kiosk.gd, which
## drops fullscreen and the cursor policy on it), and the smoke run sets it.
## Reusing it keeps one answer to "is this a real machine" instead of two.
##
## The empty-HOME case stays as a second guard: with nowhere to write the done
## marker, setup could never be completed, and a screen that cannot be finished
## is worse than one that never appears.
func needed() -> bool:
	if not OS.get_environment("MARWANOS_SHELL_WINDOWED").is_empty():
		return false
	var base := _base_dir()
	if base.is_empty():
		return false
	return not FileAccess.file_exists(base.path_join(DONE_FILE))


func mark_done() -> void:
	_write(DONE_FILE, "1")


func display_name() -> String:
	var base := _base_dir()
	if base.is_empty():
		return ""
	var path := base.path_join(NAME_FILE)
	if not FileAccess.file_exists(path):
		return ""
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return ""
	return handle.get_as_text().strip_edges()


## What the row shows when nobody has typed anything.
func display_name_or_default() -> String:
	var name := display_name()
	return name if not name.is_empty() else "Not set -- press A"


## Stripped of newlines and tabs before it is stored, for the reason every other
## value in this project is: it is read back into a single-line file and pasted
## into UI, and a stray newline turns one fact into two.
func set_display_name(text: String) -> void:
	var clean := text.strip_edges().replace("\n", " ").replace("\t", " ")
	_write(NAME_FILE, clean)
	ShellLog.info("setup: display name set (%d characters)" % clean.length())


func open() -> void:
	if is_open():
		return
	if Launcher.is_busy():
		return
	if Settings.is_open() or Power.is_open() or Info.is_open() or Files.is_open() or Browser.is_open() or WindowsInstall.is_open():
		return

	ShellLog.info("setup opened")

	_screen = SetupScreen.new()
	_screen.closed.connect(_on_closed, CONNECT_ONE_SHOT)

	setup_opened.emit()
	get_tree().root.add_child(_screen)


func _on_closed() -> void:
	_finish.call_deferred()


func _finish() -> void:
	var screen := _screen
	_screen = null
	if is_instance_valid(screen):
		screen.get_parent().remove_child(screen)
		screen.queue_free()
	ShellLog.info("setup closed")
	setup_closed.emit()


func _base_dir() -> String:
	var home := OS.get_environment("HOME")
	if home.is_empty():
		return ""
	return home.path_join(DIR_NAME)


## Best-effort, and a failure is logged rather than raised. Nothing on this
## screen is load-bearing, so a read-only home should cost somebody a saved name
## and not a boot.
func _write(file_name: String, text: String) -> void:
	var base := _base_dir()
	if base.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(base)
	var handle := FileAccess.open(base.path_join(file_name), FileAccess.WRITE)
	if handle == null:
		ShellLog.warn("setup: could not write %s" % file_name)
		return
	handle.store_string(text)
