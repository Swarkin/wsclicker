extends Node

const DELAY_MS := 50

@export var container: Container
@export var disconnected_label: Label
@export var count_label: Label
@export var session_label: Label
@export var players_label: Label

var url := "wss://swarkin.dev/?client=wsclicker"
var t := Thread.new()
var state := State.new()
var update_ui := false
var queued_packets := 0

class State:
	var count: int
	var players: int
	var session_count := 0
	var mutex := Mutex.new()

	func _init(_count := 0, _players := 0, _session := 0) -> void:
		count = _count
		players = _players
		session_count = _session

func _ready() -> void:
	set_process(false)
	ui_toggle(false)

	if OS.has_feature("debug"):
		print("debug mode")
		url = "127.0.0.1:8080"
		await get_tree().create_timer(1.0).timeout

	var err := t.start(start_connection)
	if err:
		prints("t.start", error_string(err))
		return


func _process(_dt: float) -> void:
	state.mutex.lock()
	if update_ui:
		count_label.text = str(state.count)
		session_label.text = "You clicked %s times" % state.session_count
		players_label.text = "You are alone." if state.players == 1 else "One other person is here." if state.players == 2 else str(state.players - 1) + " others are here."
		update_ui = false
	state.mutex.unlock()


func _on_button_pressed() -> void:
	state.mutex.lock()
	queued_packets += 1
	state.session_count += 1
	state.mutex.unlock()


func start_connection() -> void:
	var ws := WebSocketPeer.new()
	var err := ws.connect_to_url(url)
	if err:
		prints("ws.connect_to_url", error_string(err))
		return

	set_process.call_deferred(true)
	var prev_state := ws.STATE_CLOSED

	while true:
		ws.poll()

		var ws_state := ws.get_ready_state()
		match ws_state:
			ws.STATE_OPEN:
				if not prev_state == ws.STATE_OPEN:
					ui_toggle.call_deferred(true)
					print("Send Hello")

					err = ws.send(API.HelloPacket.encode())
					if err:
						push_error("ws.put_packet ", error_string(err))

				state.mutex.lock()
				var queued := queued_packets
				queued_packets = 0
				state.mutex.unlock()

				for i in queued:
					err = ws.put_packet(API.IncreasePacket.encode())
					if err:
							push_error("ws.put_packet ", error_string(err))
							continue

				while ws.get_available_packet_count():
					var data := ws.get_packet()
					var p := API.parse_packet(data)
					if not p:
						if data.size() < 15:
							push_error("Invalid Packet: ", data)
						else:
							push_error("Invalid Packet with len ", data.size())
						continue

					if p is API.SyncPacket:
						state.mutex.lock()
						@warning_ignore("unsafe_property_access") state.count = p.amount
						@warning_ignore("unsafe_property_access") state.players = p.players
						update_ui = true
						state.mutex.unlock()
					else:
						push_error("Invalid PacketType: ", p.type)
						continue

			ws.STATE_CLOSED:
				set_process.call_deferred(false)
				ui_toggle.call_deferred(false, true)

		prev_state = ws_state
		OS.delay_msec(DELAY_MS)


func ui_toggle(s: bool, d := false) -> void:
	container.visible = s
	disconnected_label.visible = not s
	if d:
		disconnected_label.text = "Disconnected\nRestart to try again"
