extends Control

## Dolphin's Places column: Home and the standard folders inside it, then every
## drive that is plugged in. Attached on the left, or opened as a drawer when
## the file listing needs the full width of a compact window.
##
## THIS REPLACES A VIEW AND THAT IS THE POINT. The single-pane version made
## Places a *screen* -- B at a place's root took the whole listing away and
## replaced it with a two-row menu, and getting from a stick to Downloads was
## back, down, into Home, down, into Downloads. Dolphin's answer is a column
## that is simply always there, and on a pad it is better than it is with a
## mouse: it is one axis, it is the leftmost thing on screen, and left from
## anywhere reaches it.
##
## THE DRIVE LIST IS LIVE. A stick is plugged in WHILE someone is looking at
## this -- that is the whole gesture -- so the mount set is polled and a drive
## arriving or leaving redraws the column under the cursor. See MOUNT_POLL_
## SECONDS and the note in files_screen.gd about the two halves of "the files
## app did not recognize it at all".

const TvTheme = preload("res://src/tv_theme.gd")
const ActionRow = preload("res://src/file_place.gd")
const FileItem = preload("res://src/file_item.gd")
const FileTrash = preload("res://src/file_trash.gd")

## A place was chosen. The screen decides which pane it lands in, because a
## column cannot know which side is active.
signal place_chosen(place: Dictionary)

## Anything here took focus.
signal became_active()

## The mount set changed. The screen uses it for the status line and to notice
## that the drive a pane is inside has gone.
signal mounts_changed(arrived: Array, departed: Array)

## The desk and harness override, in the spirit of MARWANOS_SHELL_STORE_DIR:
## point it at any directory and the Home place browses that instead of $HOME.
## The Xvfb harness needs it because its container pins HOME to an empty
## tmpfs, and a file manager verified only against an empty folder is a file
## manager whose listing code has never run.
const FILES_HOME_ENV := "MARWANOS_SHELL_FILES_HOME"

## Where removable media lands on the appliance. marwanos-usbmount mounts under
## /run/media/<user>/<label>, which is udisks2's own convention and therefore
## the one a desktop would use on the same stick; the user directory is
## enumerated rather than guessed from $USER because the shell does not get to
## assume whose session mounted the stick.
##
## No environment override, unlike FILES_HOME: /run is a tmpfs in the harness's
## container, so fake drives are bind-mounted at the real path (MEDIA_DIR in
## scripts/xvfb-shell-verify.sh). An override would be a second code path that
## only the harness ever took, to reach a place the harness can already reach.
const MEDIA_ROOT := "/run/media"

## The folders tmpfiles.d guarantees inside Home (see 50-marwanos.conf). Listed
## as places for the reason Dolphin lists them: they are where things land --
## the browser's downloads, a stick's films -- and reaching Downloads should not be two
## presses into a directory listing.
##
## A folder that does not exist is NOT drawn. tmpfiles re-asserts all four every
## boot, so absence means someone deliberately removed one on a machine where
## /var is theirs, and a place that opens onto nothing is worse than no place.
const HOME_FOLDERS := [
	{"name": "Downloads", "icon": "download"},
	{"name": "Videos", "icon": "folder"},
	{"name": "Music", "icon": "folder"},
	{"name": "Pictures", "icon": "folder"},
]

## How often the mount set is re-read. A directory listing of /run/media/<user>
## is two getdents on a tmpfs -- cheap enough that the interval is chosen by how
## long a person will hold a stick in a port wondering whether it worked, not by
## cost. Two seconds is under that.
const MOUNT_POLL_SECONDS := 2.0

var _list: VBoxContainer = null
var _rows: Array = []
var _known_mounts: Array = []
var _location := ""
var _pad: MarginContainer
var include_trash := true


func _ready() -> void:
	custom_minimum_size = Vector2(360, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var background := ColorRect.new()
	background.color = TvTheme.SURFACE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var pad := MarginContainer.new()
	_pad = pad
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 32)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", TvTheme.SAFE_MARGIN_Y)
	pad.add_theme_constant_override("margin_bottom", 24)
	add_child(pad)
	resized.connect(_fit_places)
	_fit_places()
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 24)
	pad.add_child(column)

	var heading := Label.new()
	heading.text = "Places"
	heading.add_theme_font_size_override("font_size", TvTheme.SIZE_BODY)
	heading.add_theme_color_override("font_color", TvTheme.TEXT_SECONDARY)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)

	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	_known_mounts = _mounts()
	_rebuild()

	var timer := Timer.new()
	timer.wait_time = MOUNT_POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_poll_mounts)
	add_child(timer)


func _fit_places() -> void:
	var viewport := get_viewport_rect().size
	_pad.add_theme_constant_override("margin_left", maxi(20, roundi(viewport.x * 0.05)))
	_pad.add_theme_constant_override("margin_top", maxi(20, roundi(viewport.y * 0.05)))


# ---------------------------------------------------------------------------
# The list
# ---------------------------------------------------------------------------

## Every place, as {name, path, root, root_label, removable, icon, volume}.
##
## `root` is the floor a pane opened at this place will not walk above -- Home's
## subfolders all share Home as their root, so B out of Downloads lands in Home
## rather than leaving the pane, which is what a person means by "up".
##
## `root_label` is what that floor is CALLED, and it travels with the root for
## the same reason the root travels with the path: a pane draws the floor as
## the first breadcrumb, and /var/home/player is not a name to put on a
## television. Carried here rather than worked out by the pane, so the $HOME
## fallback chain exists once, in the object whose job is knowing where places
## are.
func places() -> Array:
	var result: Array = []
	var home := home_path()
	# The folder glyph rather than the house: this row IS a folder -- the one
	# the person owns -- and the icon language should say what a thing is, not
	# where the metaphor came from.
	result.append({"name": "Home", "path": home, "root": home,
		"root_label": "Home", "removable": false, "icon": "folder", "volume": true})

	# THE FOLDERS SHOW NO FREE SPACE, and that is the fix for a screenshot in
	# which the column said "737.5 GB free" five times over. All four of these
	# live on the same filesystem as Home, so four repetitions of Home's number
	# is not information -- it is the same fact, crowding out the names, on the
	# one column where the name is the whole point. `volume` marks the rows that
	# are a distinct filesystem and therefore have something of their own to
	# report.
	for folder in HOME_FOLDERS:
		var full := home.path_join(str(folder["name"]))
		if not DirAccess.dir_exists_absolute(full):
			continue
		result.append({"name": str(folder["name"]), "path": full, "root": home,
			"root_label": "Home", "removable": false,
			"icon": str(folder["icon"]), "volume": false})

	result.append({"name": "Filesystem", "path": "/", "root": "/",
		"root_label": "Filesystem", "removable": false, "icon": "folder", "volume": false})
	if include_trash:
		result.append({"name": "Trash bin", "path": FileTrash.LOCATION, "root": FileTrash.LOCATION,
			"root_label": "Trash bin", "removable": false, "icon": "trash", "volume": false})

	for mount_path in _mounts():
		result.append({"name": mount_path.get_file(), "path": mount_path,
			"root": mount_path, "root_label": mount_path.get_file(),
			"removable": true, "icon": "usb", "volume": true})
	return result


func _rebuild(focus_path: String = "") -> void:
	for row in _rows:
		_list.remove_child(row)
		row.queue_free()
	_rows.clear()

	for place in places():
		var row := ActionRow.new()
		# FREE SPACE ON A VOLUME ROW, because "will this fit" is the question a
		# person asks of a stick before they copy anything to it, and the only
		# other way to find out on this machine is to copy and see. Home shows
		# it too -- the appliance's root filesystem is 15 GB and a person
		# pulling a season off a stick should be able to see that.
		var value := ""
		if bool(place.get("volume", false)):
			value = _free_space_text(str(place["path"]))
		elif str(place["path"]) == FileTrash.LOCATION:
			value = _trash_count_text()
		row.setup(str(place["name"]), value, str(place["icon"]))
		row.set_meta("place", place)
		row.activated.connect(_on_row_activated.bind(row))
		row.focus_entered.connect(_on_any_focus)
		_list.add_child(row)
		_rows.append(row)

	_wire_focus()
	set_location(_location)

	if not focus_path.is_empty():
		for row in _rows:
			var place: Dictionary = row.get_meta("place")
			if str(place.get("path", "")) == focus_path:
				row.grab_focus()
				break


## The settings list's table: one axis, hard stops, and right leaving the
## column for whatever the screen put beside it.
func _wire_focus() -> void:
	var count := _rows.size()
	for index in count:
		var row: Control = _rows[index]
		var up := index - 1 if index > 0 else index
		var down := index + 1 if index + 1 < count else index

		row.focus_neighbor_top = row.get_path_to(_rows[up])
		row.focus_neighbor_bottom = row.get_path_to(_rows[down])
		# BOTH SIDES ARE HARD STOPS, pointed at self. Left because this is the
		# leftmost thing on the screen; right because crossing into a pane is
		# done by files_screen rather than by a stored path -- see
		# FilePane._wire_focus for why a path into a rebuilt region is a path
		# to a node that will not exist.
		row.focus_neighbor_left = row.get_path_to(row)
		row.focus_neighbor_right = row.get_path_to(row)


func grab_places_focus() -> void:
	if _rows.is_empty():
		return
	var first: Control = _rows[0]
	for row in _rows:
		if row.active:
			first = row
			break
	first.grab_focus()


func set_location(folder: String) -> void:
	_location = folder
	var best := ""
	for row in _rows:
		var candidate := str(row.get_meta("place").get("path", ""))
		if (folder == candidate or folder.begins_with(candidate.trim_suffix("/") + "/")) and candidate.length() > best.length():
			best = candidate
	for row in _rows:
		var active: bool = str(row.get_meta("place").get("path", "")) == best
		if row.active != active:
			row.active = active


func focused_place() -> Dictionary:
	var owner := get_viewport().gui_get_focus_owner()
	for row in _rows:
		if row == owner:
			return row.get_meta("place")
	return {}


func has_focus_inside() -> bool:
	var owner := get_viewport().gui_get_focus_owner()
	return owner != null and is_ancestor_of(owner)


func _on_row_activated(row: Control) -> void:
	place_chosen.emit(row.get_meta("place"))


func _on_any_focus() -> void:
	became_active.emit()


# ---------------------------------------------------------------------------
# Drives coming and going
# ---------------------------------------------------------------------------

## Every mount under /run/media/<any user>/. No /run/media at all -- a desk, a
## container, a machine with nothing plugged in -- is the normal case and
## returns the normal answer: nothing.
func _mounts() -> Array:
	var result: Array = []
	var media := DirAccess.open(MEDIA_ROOT)
	if media == null:
		return result
	for user_name in media.get_directories():
		var user_dir := DirAccess.open(MEDIA_ROOT.path_join(user_name))
		if user_dir == null:
			continue
		for mount_name in user_dir.get_directories():
			result.append(MEDIA_ROOT.path_join(user_name).path_join(mount_name))
	result.sort()
	return result


func _poll_mounts() -> void:
	refresh_trash()
	var now := _mounts()
	if now == _known_mounts:
		return

	var arrived: Array = []
	for mount_path in now:
		if not _known_mounts.has(mount_path):
			arrived.append(mount_path)
	var departed: Array = []
	for mount_path in _known_mounts:
		if not now.has(mount_path):
			departed.append(mount_path)
	_known_mounts = now

	for mount_path in arrived:
		ShellLog.info("files: drive appeared at %s" % mount_path)
	for mount_path in departed:
		ShellLog.info("files: drive went away from %s" % mount_path)

	# Rebuilt by PATH, so the cursor stays on the row it was on rather than on
	# the row that is now at that index -- a stick appearing above the one you
	# were about to open must not move the selection onto it.
	var keep := str(focused_place().get("path", ""))
	_rebuild(keep)
	mounts_changed.emit(arrived, departed)


func refresh_trash() -> void:
	for row in _rows:
		if str(row.get_meta("place").get("path", "")) == FileTrash.LOCATION:
			row.set_value(_trash_count_text())
			return


func _trash_count_text() -> String:
	var count := FileTrash.entries().size()
	return "%d item%s" % [count, "" if count == 1 else "s"]


func home_path() -> String:
	var override := OS.get_environment(FILES_HOME_ENV)
	if not override.is_empty():
		return override
	var home := OS.get_environment("HOME")
	if not home.is_empty():
		return home
	# The appliance's session always exports HOME; this is the desk fallback,
	# and on the desks this repo runs on the desk user is root.
	return "/root"


## "12.4 GB free", or empty when the volume will not answer.
##
## DirAccess.get_space_left reports the free space of the filesystem the open
## directory lives on -- a statvfs, not a walk -- so it costs the same on a
## 2 GB stick and a 4 TB disk. A directory that will not open (a mount that
## vanished between the listing and this call, which the poll makes a real
## race) renders no number rather than a zero, because "0 B free" is a claim
## and "nothing" is an absence.
func _free_space_text(place_path: String) -> String:
	var dir := DirAccess.open(place_path)
	if dir == null:
		return ""
	# FileItem's, not a second copy: that one is static precisely so the
	# listing, the properties panel and this column round a size the same way,
	# and a private copy here is exactly the drift its comment warns about.
	return "%s free" % FileItem.human_size(dir.get_space_left())
