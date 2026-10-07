extends Node

## ============================================================================
## WHAT IS INSTALLED, read from what the system says.
##
## This is what replaced catalogue.gd's twelve placeholders. Same contract as
## the status seam next door: marwanos-appscan enumerates desktop entries the
## way a desktop's app launcher does and writes /run/marwanos/apps.tsv; this
## autoload polls the file and hands the home rail a list. The shell walks no
## directories and parses no desktop entries -- it is a renderer.
##
## AN EMPTY LIST IS A REAL ANSWER, and on a fresh stick it is the usual one.
## The rail draws an empty state for it rather than falling back to invented
## content. A missing file means the same thing as an empty one here, which is
## a deliberate difference from the status seam: "no claim about the network"
## has to be distinguishable from "offline" because the two lead somewhere
## different, whereas "the scanner has not run" and "nothing is installed" both
## mean there is nothing to put on the rail.
##
## Phase 1 deletes this file. marwand's `ListInstalled` returns the same shape
## over JSON-RPC -- an opaque id, a title, a one-line summary, something to
## draw, and how to start it -- so the rail is rewired by changing this seam
## and nothing else.
## ============================================================================

## Emitted whenever the installed list changes, including to and from empty.
signal apps_changed(apps: Array)

## Two seconds, matching the status seam. The file changes rarely -- only when
## something is installed or removed -- and reading a few short lines off a
## tmpfs costs nothing.
const POLL_SECONDS := 2.0

const APPS_FILE := "/run/marwanos/apps.tsv"

## The desk-run lever, shared with the status seam so one directory of fixtures
## drives every file the shell reads. Nothing on the appliance sets it.
const STATUS_DIR_ENV := "MARWANOS_SHELL_STATUS_DIR"

## Number of tab-separated fields in a record: id, name, comment, icon, exec,
## state. A line with fewer is malformed and skipped rather than guessed at.
const FIELD_COUNT := 6

# Desktop utilities need the controller pointer and native window sizing.
# Use stable app IDs so games retain their ordinary controller routing.
const INPUT_MODES := {
	"org.freedownloadmanager.Manager": "pointer",
}

## What a card says about an app that is on its way but not here yet. The words
## live HERE rather than in the scanner for the same reason the store page's
## do: the system reports a state, the shell decides how to say it, and the two
## can be retuned for a TV without touching a systemd unit.
##
## "unknown" doubles as the fallback, so a state word from a newer installer
## renders as an unspecific card rather than a silent one.
const PENDING_SUBTITLES := {
	# SOURCE-NEUTRAL SINCE STEAM GAMES ARRIVE HERE TOO. This used to name
	# Flathub, which was true when the only pending cards were the shipped
	# applications; appscan now publishes a Steam game with an appmanifest and no
	# StateFlags bit 4 as `downloading` as well, and a Witcher 3 card claiming to
	# be coming from Flathub would be a confident lie. Both sources fill the
	# comment column with a live line anyway -- see _pending_subtitle -- so this
	# is only ever the first second or two.
	"downloading": "Installing -- this is a large download, give it minutes",
	"waiting-network": "Waiting for a network before installing",
	"no-network": "No network found -- will install once there is one",
	"no-space": "Not enough free space on the drive to install this",
	"failed": "Install failed -- journalctl -t marwanos-install has the story",
	"unknown": "Installing",
}

var apps: Array = []

var _apps_path := APPS_FILE

## Whether _poll has ever completed. Without it the first poll of a machine
## with nothing installed is silent: `_last_raw` would start equal to what a
## missing file reads as, the change guard below would short-circuit, and the
## journal would never carry the "0 applications" line. On an appliance whose
## only debugging surface is journalctl, "the scan found nothing" and "the
## shell never looked" have to be distinguishable.
var _loaded := false
var _last_raw := ""
var _last_managed := ""


func _managed_library() -> Array:
	# WindowsInstall is later in autoload order; the first poll precedes it.
	var manager := get_node_or_null("/root/WindowsInstall")
	return manager.library() if manager != null else []


func _ready() -> void:
	Metadata.changed.connect(func(): _loaded = false; _poll())
	PlayHistory.changed.connect(func(): _loaded = false; _poll())
	var override := OS.get_environment(STATUS_DIR_ENV)
	if not override.is_empty():
		_apps_path = override.path_join(APPS_FILE.get_file())

	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)

	# Polled once here rather than a tick from now, so shell_root's _ready --
	# which runs after this one and reads `apps` directly -- builds the real
	# rail on the first frame instead of an empty one that fills in later.
	_poll()


func _poll() -> void:
	var raw := _read_file(_apps_path)
	var managed := _managed_library()
	var managed_raw := JSON.stringify(managed)
	# Compared as raw text rather than by diffing parsed lists: the file is
	# small, string equality is exact, and it means an unchanged scan costs one
	# comparison instead of rebuilding the rail every two seconds. The first
	# poll always goes through, however it compares -- see _loaded.
	if _loaded and raw == _last_raw and managed_raw == _last_managed:
		return
	_loaded = true
	_last_raw = raw
	_last_managed = managed_raw

	apps = _parse(raw)
	apps.append_array(managed)
	for index in apps.size():
		apps[index] = Metadata.enrich(apps[index])
	apps = PlayHistory.recently_played(apps)
	ShellLog.info("installed applications: %d" % apps.size())
	for app in apps:
		ShellLog.info("  %s (%s) [%s]"
			% [str(app.get("title", "")), str(app.get("id", "")), str(app.get("state", ""))])
	apps_changed.emit(apps)


func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


## One entry per well-formed line, in the shape the rail and the launch seam
## already speak -- so nothing downstream can tell this list came from a file
## rather than from the deleted catalogue.
func _parse(raw: String) -> Array:
	var result: Array = []
	for line in raw.split("\n", false):
		var fields := line.split("\t", true)
		if fields.size() < FIELD_COUNT:
			if not line.strip_edges().is_empty():
				ShellLog.warn("skipping malformed apps.tsv line: %s" % line)
			continue

		var exec_parts: Array = []
		for part in fields[4].split(" ", false):
			exec_parts.append(part)

		var state := fields[5]
		var installed := state == "installed"

		# An installed app with nothing to run is the one shape that cannot be
		# rendered usefully: a card that looks ready and does nothing. A
		# PENDING app with no exec is expected -- it has not arrived yet.
		if installed and exec_parts.is_empty():
			ShellLog.warn("skipping %s: installed but carries no exec" % fields[0])
			continue

		result.append({
			"id": fields[0],
			"title": fields[1],
			"subtitle": fields[2] if installed else _pending_subtitle(state, fields[2]),
			"icon": fields[3],
			"exec": exec_parts,
			"state": state,
			"input_mode": str(INPUT_MODES.get(fields[0], "")),
		})
	return result


## The scanner puts a LIVE progress line in the comment column of a pending
## record ("1240 MB fetched, 4100 MB free"). Preferring it over the table is
## the whole point: the table's wording is fixed, and a card that says the same
## sentence for half an hour reads as a hung machine even while a multi-gigabyte
## download is going perfectly. The table stays as the fallback for the states
## that have nothing to count -- waiting for a network, no space, failed.
func _pending_subtitle(state: String, detail: String) -> String:
	if not detail.is_empty():
		return detail
	return str(PENDING_SUBTITLES.get(state, PENDING_SUBTITLES["unknown"]))
