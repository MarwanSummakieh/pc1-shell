extends Node

signal opened()
signal closed()

const ListMenu = preload("res://src/list_menu.gd")
var _menu: Control
var _prompted: Dictionary = {}
var _pending: Callable

func _ready() -> void:
	Notifications.received.connect(_on_notification)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)

func completed(path: String, torrent: bool = false) -> void:
	WindowsInstall._request({"verb": "download", "path": path, "torrent": torrent})

func _on_notification(event: Dictionary) -> void:
	if event.get("app", "") not in ["FDM Controller", "Downloads"] or event.get("summary", "") != "Download complete":
		return
	var download: Dictionary = event.get("download", {})
	completed(str(download.get("path", event.get("body", ""))), bool(download.get("torrent", false)))

func _poll() -> void:
	# A completed download must not replace a running game or interrupt a wizard.
	var home := get_tree().current_scene
	if home is Control and not home.visible:
		return
	if _menu != null or Downloads.is_open() or WindowsInstall.is_busy() or WindowsInstall.is_open() or Browser.is_open() or Files.is_open() or Settings.is_open() or Power.is_open() or Info.is_open():
		return
	if Launcher.is_busy() and not Launcher.is_minimized():
		return
	for receipt: Dictionary in WindowsInstall.snapshot.get("downloads", []):
		var stage := str(receipt.get("status", ""))
		var key := str(receipt.get("id", "")) + ":" + stage
		if stage not in ["ready", "installed"] or _prompted.has(key):
			continue
		_prompted[key] = true
		_show(receipt)
		return

func _action(receipt: Dictionary, action: String) -> void:
	WindowsInstall._request({"verb": "download-action", "download_id": receipt.id, "action": action})

func _show(receipt: Dictionary) -> void:
	_menu = ListMenu.new()
	var installed := str(receipt.get("status", "")) == "installed"
	_menu.title_text = "Installation complete" if installed else "Download ready"
	if installed:
		_menu.items = [{"id": "keep", "label": "Keep downloaded files", "icon": "folder"}]
		if bool(receipt.get("torrent", false)):
			_menu.note_text = "Torrent files stay available for seeding. Stop seeding in Downloads when ready."
		else:
			_menu.note_text = "Remove the downloaded setup file? The installed program and multipart payloads are kept."
			_menu.items.append({"id": "cleanup", "label": "Remove downloaded installer files", "icon": "close"})
	else:
		_menu.note_text = str(receipt.get("source", "")).get_file()
		_menu.items = [{"id": "start", "label": "Install", "icon": "download"}, {"id": "defer", "label": "Later", "icon": "close"}]
	_pending = Callable()
	_menu.chosen.connect(func(action: String):
		_pending = func():
			_action(receipt, action)
			if action == "start":
				WindowsInstall.open_download(str(receipt.source)))
	_menu.closed.connect(_finish, CONNECT_ONE_SHOT)
	opened.emit()
	get_tree().root.add_child(_menu)

func _finish() -> void:
	_finish_deferred.call_deferred()

func _finish_deferred() -> void:
	if is_instance_valid(_menu):
		_menu.get_parent().remove_child(_menu)
		_menu.queue_free()
	_menu = null
	closed.emit()
	if _pending.is_valid():
		_pending.call_deferred()
	_pending = Callable()
