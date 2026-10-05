extends Node

## ============================================================================
## THE STATUS SEAM -- what the system says is true, read-only.
##
## The shell is a renderer, and this file is that rule applied to system state:
## it opens no sockets, probes nothing, and runs nothing. System services write
## small files and this autoload polls them -- marwanos-netcheck writes
## /run/marwanos/network.state (`online`/`offline`) and network.info (one line
## describing the link, e.g. `wifi HomeNet`), and marwanos-flatpak-install
## writes /run/marwanos/install.<app-id>.state (`waiting-network`,
## `no-network`, `downloading`, `no-space`, `failed`), replacing it with the
## durable stamp /var/marwanos/installed.<app-id> on success. This seam reads
## only Steam's pair, because Steam is the only app with a store page; every
## other app's install reaches the rail through installed.gd instead. The desk
## harness runs the shell
## under --network=none, and nothing here would notice: the network's absence
## at the desk is a missing FILE, which renders as "no claim" rather than as a
## false Offline.
##
## "No claim" is a real state, not an error. A boot too early for netcheck to
## have written, an image predating it, or a desk run all look identical here
## -- no file -- and the honest render for a machine that cannot say is
## nothing, not either answer. The consumers treat "unknown" accordingly.
##
## Phase 1 replaces the files with marwand pushing state over the WebSocket;
## the two signals below survive that rewiring, the polling does not. Same
## shape as the launch seam: consumers cannot tell the transport changed.
## ============================================================================

## Emitted when the one-word answer in network.state changes, including to and
## from "unknown". States: "online", "offline", "unknown".
signal network_changed(state: String)

## Emitted when the Steam install's state changes. States: "installed" (the
## stamp exists), the state file's word passed through verbatim, or "unknown"
## when neither file has anything to say. Verbatim on purpose -- a new word
## from a future installer version reaches the consumers without a shell
## release, and they fall back sanely on words they do not know.
signal steam_changed(state: String)

## Emitted when the link description in network.info changes. Free text from
## netcheck -- "wifi <name>", "ethernet <name>", "link <device>", "none" --
## passed through verbatim for the settings screen to parse; empty when the
## file has nothing to say.
signal network_info_changed(info: String)

## Two seconds between file polls. The files are one word on a tmpfs -- the
## read costs nothing -- and the slowest writer (netcheck) only re-answers
## every 15s, so polling faster would be reading the same word more often.
const POLL_SECONDS := 2.0

const NETWORK_STATE_FILE := "/run/marwanos/network.state"
const NETWORK_INFO_FILE := "/run/marwanos/network.info"
## Steam's install, for the stores screen's page. Named by application id
## because marwanos-flatpak-install is templated on that id and writes one pair
## of files per app -- Steam is simply the one this seam happens to care about,
## since it is the only app with a store page. The rail learns about every
## other app's install through the scanner instead (see installed.gd).
const STEAM_STATE_FILE := "/run/marwanos/install.com.valvesoftware.Steam.state"
const STEAM_STAMP_FILE := "/var/marwanos/installed.com.valvesoftware.Steam"

## Desk-run lever, same shape as MARWANOS_SHELL_WINDOWED in kiosk.gd: a
## variable nothing on the appliance sets. When set, all three files are read
## from this directory instead (keeping their basenames), so a harness can
## write fixtures into a bind-mounted directory and watch the shell react.
const STATUS_DIR_ENV := "MARWANOS_SHELL_STATUS_DIR"

var network: String = "unknown"
var network_info: String = ""
var steam: String = "unknown"

## The installer's live progress line for Steam, or empty. Read alongside the
## state word rather than through its own signal: the store page redraws on
## steam_changed, and a detail that moved while the word did not still needs to
## reach the screen -- so the poll emits on either changing.
var steam_detail: String = ""

var _network_state_path := NETWORK_STATE_FILE
var _network_info_path := NETWORK_INFO_FILE
var _steam_state_path := STEAM_STATE_FILE
var _steam_stamp_path := STEAM_STAMP_FILE


func _ready() -> void:
	var override := OS.get_environment(STATUS_DIR_ENV)
	if not override.is_empty():
		_network_state_path = override.path_join(NETWORK_STATE_FILE.get_file())
		_network_info_path = override.path_join(NETWORK_INFO_FILE.get_file())
		_steam_state_path = override.path_join(STEAM_STATE_FILE.get_file())
		_steam_stamp_path = override.path_join(STEAM_STAMP_FILE.get_file())
		ShellLog.warn("status files redirected to %s (%s is set; a desk run, never the appliance)"
			% [override, STATUS_DIR_ENV])

	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)

	# Poll once now rather than a timer-tick from now: shell_root's _ready runs
	# after this one and reads the properties directly, and the first frame the
	# TV shows should already carry whatever the system had written by then.
	_poll()


func _poll() -> void:
	_set_network(_read_network())
	_set_network_info(_read_word(_network_info_path))
	_set_steam(_read_steam())


func _read_network() -> String:
	var word := _read_word(_network_state_path)
	# The vocabulary is closed on this file: netcheck writes two words, and
	# anything else is a torn write or a stranger's file, neither of which is
	# worth rendering as a claim about the network.
	if word == "online" or word == "offline":
		return word
	return "unknown"


func _read_steam() -> String:
	# The stamp outranks the state file. It is the durable record the installer
	# proves before writing, and during the success handover (stamp written,
	# state not yet removed) this ordering is what makes the overlap read as
	# "installed" rather than a minute of stale "downloading".
	if FileAccess.file_exists(_steam_stamp_path):
		steam_detail = ""
		return "installed"
	# The installer writes `<state>TAB<name>TAB<detail>`. The name is there for
	# the rail's pending cards; the detail is the live progress line, which the
	# store page shows for the same reason the rail does -- a screen that says
	# the same sentence for half an hour reads as a hung machine.
	var line := _read_word(_steam_state_path)
	var word := line.get_slice("\t", 0)
	steam_detail = line.get_slice("\t", 2)
	if word.is_empty():
		return "unknown"
	return word


func _read_word(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_line().strip_edges()


func _set_network(state: String) -> void:
	if state == network:
		return
	network = state
	ShellLog.info("network is %s" % state)
	network_changed.emit(state)


func _set_network_info(info: String) -> void:
	if info == network_info:
		return
	network_info = info
	ShellLog.info("network link: %s" % (info if not info.is_empty() else "<no claim>"))
	network_info_changed.emit(info)


var _last_steam_detail := ""


## Emits when the WORD or the DETAIL changes. Gating on the word alone would
## freeze the store page's progress line at whatever it said when
## "downloading" first appeared -- which is the exact defect this whole change
## exists to fix, reintroduced one layer up.
func _set_steam(state: String) -> void:
	if state == steam and steam_detail == _last_steam_detail:
		return
	var word_changed := state != steam
	steam = state
	_last_steam_detail = steam_detail
	if word_changed:
		ShellLog.info("steam install state: %s" % state)
	steam_changed.emit(state)
