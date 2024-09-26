extends Node

var ws := WebSocketPeer.new()
var count := 0
var count_session := 0
var local_player_count := 0
var queued_packets := 0
var prev_state := ws.STATE_CLOSED

@export var button: Button
@export var labels_container: Container
@export var disconnected_label: Label
@export var count_label: Label
@export var session_label: Label
@export var players_label: Label

func _ready() -> void:
	set_process(false)
	ui_toggle(false)

	var url := "wss://swarkin.dev?client=wsclicker"
	if OS.has_feature("debug") and not OS.has_feature("web"): # web exports still show up as debug for some reason.
		print("Debug mode")
		url = "127.0.0.1:8080"
		await get_tree().create_timer(1.0).timeout

	button.pressed.connect(func() -> void:
		if ws.get_ready_state() == ws.STATE_OPEN:
			queued_packets += 1
			count_session += 1
	)

	print("Connecting on Client")
	set_process(true)
	var err := ws.connect_to_url(url)
	if err:
		print("server.listen ", error_string(err))
		set_process(false)
		return


func _process(_dt: float) -> void:
	ws.poll()

	var state := ws.get_ready_state()
	match ws.get_ready_state():
		ws.STATE_OPEN:
			if not prev_state == ws.STATE_OPEN:
				ui_toggle(true)
				print("Send Hello")

				var err := ws.send(API.HelloPacket.encode())
				if err:
					push_error("ws.put_packet ", error_string(err))

			for i in queued_packets:
				var err := ws.put_packet(API.IncreasePacket.encode())
				if err:
					count_session -= 1
					push_error("ws.put_packet ", error_string(err))

			queued_packets = 0

			while ws.get_available_packet_count():
				var data := ws.get_packet()
				var p := API.parse_packet(data)
				if not p:
					push_error("Invalid Packet received: ", data)
					continue

				if p is API.SyncPacket:
					@warning_ignore("unsafe_property_access") count = p.amount
					@warning_ignore("unsafe_property_access") local_player_count = p.players
					update_ui()
				else:
					push_error("Invalid PacketType received: ", p.type)
					continue

		ws.STATE_CLOSED:
			print("Closed")
			set_process(false)
			ui_toggle(false)

	prev_state = state


func update_ui() -> void:
	count_label.text = str(count)
	session_label.text = "You clicked %s times" % count_session
	players_label.text = "You are alone." if local_player_count == 1 else "One other person is here." if local_player_count == 2 else str(local_player_count - 1) + " others are here."


func ui_toggle(state: bool) -> void:
	labels_container.visible = state
	disconnected_label.visible = not state
