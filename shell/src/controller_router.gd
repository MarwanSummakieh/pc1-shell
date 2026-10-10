extends Node

## The appliance broker exclusively reads the physical controller. Applications
## see virtual devices for connected player slots, neutral while PC1 owns the foreground.
const DEVICE := 15
var _socket := PacketPeerUDP.new()
var _endpoint: Dictionary = {}
var _buttons: Array = []
var _axes: Array = []
var _last_packet := 0
var _sequence := -1
var _heartbeat := 0.0
var _app_input := false
var _text_input := false
var _connected := false
var _routed := false
var _shell_ready := false
## One-based application slots; only slot one drives ordinary shell navigation.
var players: Array = []

func _ready() -> void:
	_buttons.resize(15)
	_buttons.fill(false)
	_axes.resize(6)
	_axes.fill(0.0)
	_socket.bind(0, "127.0.0.1")
	_read_endpoint()

func is_active() -> bool:
	return _routed

func mark_shell_ready() -> void:
	_shell_ready = true

func set_app_input(enabled: bool) -> void:
	_app_input = enabled
	_send_heartbeat()

func set_text_input(enabled: bool) -> void:
	_text_input = enabled
	_send_heartbeat()

func _read_endpoint() -> void:
	var runtime := OS.get_environment("XDG_RUNTIME_DIR")
	if runtime.is_empty():
		return
	var path := runtime.path_join("marwanos/controller/endpoint.json")
	if not FileAccess.file_exists(path):
		return
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	if value is Dictionary and int(value.get("port", 0)) > 0:
		if value.get("token", "") != _endpoint.get("token", ""):
			_sequence = -1
		_endpoint = value
		_socket.set_dest_address("127.0.0.1", int(value.port))

func _send_heartbeat() -> void:
	if _endpoint.is_empty():
		return
	_socket.put_packet(JSON.stringify({"token": _endpoint.token, "app": _app_input and not _text_input}).to_utf8_buffer())

func _process(delta: float) -> void:
	_heartbeat += delta
	if _heartbeat >= 0.25:
		_heartbeat = 0.0
		_read_endpoint()
		_send_heartbeat()
		if _shell_ready:
			var runtime := OS.get_environment("XDG_RUNTIME_DIR")
			if not runtime.is_empty():
				var directory := runtime.path_join("marwanos")
				DirAccess.make_dir_recursive_absolute(directory)
				var marker := FileAccess.open(directory.path_join("shell.ready"), FileAccess.WRITE)
				if marker != null:
					marker.store_string(str(Time.get_unix_time_from_system()))
					marker.close()
	while _socket.get_available_packet_count() > 0:
		var payload := _socket.get_packet()
		if _socket.get_packet_ip() != "127.0.0.1" or _socket.get_packet_port() != int(_endpoint.get("port", 0)):
			continue
		var state = JSON.parse_string(payload.get_string_from_utf8())
		if not state is Dictionary or state.get("token", "") != _endpoint.get("token", ""):
			continue
		if int(state.get("seq", -1)) <= _sequence:
			continue
		_sequence = int(state.seq)
		_last_packet = Time.get_ticks_msec()
		_routed = true
		_apply_state(state)
	if _routed and Time.get_ticks_msec() - _last_packet > 1500:
		_apply_state({"connected": false})
		_routed = false
		_endpoint.clear()

func _apply_state(state: Dictionary) -> void:
	var connected := bool(state.get("connected", false))
	players = state.get("players", [])
	var player = get_node_or_null("/root/PlayerOne")
	if player != null and (connected != _connected or (connected and player.device != DEVICE)):
		player.set_routed_controller(connected, DEVICE, str(state.get("name", "Controller")))
	_connected = connected
	var buttons: Array = state.get("buttons", [])
	var axes: Array = state.get("axes", []) if connected else []
	for index in 15:
		# Guide on any player still opens Home if player one is unplugged.
		var pressed := bool(buttons[index]) if index < buttons.size() and (connected or index == JOY_BUTTON_GUIDE) else false
		if pressed != bool(_buttons[index]):
			_buttons[index] = pressed
			var event := InputEventJoypadButton.new()
			event.device = DEVICE
			event.button_index = index
			event.pressed = pressed
			Input.parse_input_event(event)
	for index in 6:
		var value := float(axes[index]) if index < axes.size() else 0.0
		if absf(value - float(_axes[index])) > 0.001:
			_axes[index] = value
			var event := InputEventJoypadMotion.new()
			event.device = DEVICE
			event.axis = index
			event.axis_value = value
			Input.parse_input_event(event)

func _exit_tree() -> void:
	_app_input = false
	_send_heartbeat()
	_socket.close()
