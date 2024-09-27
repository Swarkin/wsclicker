extends Node
class_name Server

const PORT := 8080
const DELAY_MS := 20
const PATH := "user://count"

var tcp := TCPServer.new()
var server_thread := Thread.new()
var clients := [] as Array[ClientConnection]
var mutex := Mutex.new()
var count := 0
var packets := 0
var shutdown := false

class ClientConnection:
	var ws: WebSocketPeer
	var thread: Thread
	var ready: bool

	func _init(_ws: WebSocketPeer, _thread: Thread) -> void:
		ws = _ws
		thread = _thread

	func send_packet(p: PackedByteArray) -> Error:
		if not ready:
			return Error.ERR_BUSY
		print("ws.send")
		return ws.send(p)

func _ready() -> void:
	load_count_file()
	prints("loaded count", count)

	var err := tcp.listen(PORT)
	if err:
		push_error("server.listen ", error_string(err))
		return
	prints("listening on", PORT)

	err = server_thread.start(run_server, Thread.PRIORITY_HIGH)
	if err:
		push_error("thread.start ", error_string(err))
		return


func run_server() -> void:
	while not shutdown:
		while tcp.is_connection_available():
			print("tcp.take_connection")
			var peer := tcp.take_connection()
			var err := peer.poll()
			if err:
				push_error("peer.poll ", error_string(err))
				break

			var thread := Thread.new()
			err = thread.start(handle_connection.bind(thread, peer))
			if err:
				push_error("thread.start ", error_string(err))
				peer.disconnect_from_host()
				break

		OS.delay_msec(DELAY_MS)


func handle_connection(t: Thread, peer: StreamPeerTCP) -> void:
	var ws := WebSocketPeer.new()
	var err := ws.accept_stream(peer)
	if err:
		push_error("ws.accept_stream ", error_string(err))
		return

	var conn := ClientConnection.new(ws, t)
	locked_ctx(func() -> void:
		clients.append(conn)
		print(clients)
	)

	while true:
		ws.poll()
		match ws.get_ready_state():
			ws.STATE_OPEN:
				if shutdown:
					print("shutdown: Closing Connection")
					ws.close()
					continue

				mutex.lock()

				while ws.get_available_packet_count():
					packets += 1
					var p := API.parse_packet(ws.get_packet())
					if not p:
						push_error("invalid packet")
						break

					if p is API.IncreasePacket:
						count += 1
						sync()
					elif p is API.HelloPacket:
						print("recv hello")
						conn.ready = true
						sync(conn)
					else:
						push_error("invalid PacketType: ", p.type)

				mutex.unlock()

			ws.STATE_CLOSED:
				print("closed conn")
				locked_ctx(func() -> void:
					clients.erase(conn)
					print(clients)
					sync()
				)
				break

		OS.delay_msec(DELAY_MS)


## Need
func sync(override: ClientConnection = null) -> void:
	var p := API.SyncPacket.new(count, clients.size()).encode()
	if override:
		var err := override.send_packet(p)
		if err:
			push_error("conn.send_packet ", error_string(err))
	else:
		for conn in clients:
			if not conn.ready: continue

			var err := conn.send_packet(p)
			if err:
				push_error("conn.send_packet ", error_string(err))
				continue


func load_count_file() -> void:
	var file_str := FileAccess.get_file_as_string(PATH).strip_edges(false)
	if file_str.is_empty():
		var err := FileAccess.get_open_error()
		if err:
			push_error("FileAccess.get_file_as_string ", error_string(err))
			return

	if not file_str.is_valid_int():
		push_error("file content invalid")
		return

	var file_int := file_str.to_int()
	if file_int < 0:
		push_error("stored count is negative")
		return

	count = file_int


func _notification(n: int) -> void:
	if n == NOTIFICATION_WM_CLOSE_REQUEST:
		if shutdown: return
		shutdown = true
		var file := FileAccess.open(PATH, FileAccess.WRITE)
		if file:
			file.store_string(str(count))
			file.close()
		else:
			push_error("FileAccess.open ", error_string(FileAccess.get_open_error()))

		print("server_thread.wait_to_finish")
		server_thread.wait_to_finish()

		for conn in clients:
			print("conn.thread.wait_to_finish")
			conn.thread.wait_to_finish()

		print("quit")
		get_tree().quit()


func locked_ctx(f: Callable) -> void:
	mutex.lock()
	f.call()
	mutex.unlock()
