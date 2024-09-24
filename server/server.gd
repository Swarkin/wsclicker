extends Node
class_name Server

const PORT := 8443
const DELAY_MS := 20
const PATH := "user://count"

var tcp := TCPServer.new()
var server_thread := Thread.new()
var clients := [] as Array[ClientConnection]
var mutex := Mutex.new()
var count := 0
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
			push_warning("Client not ready")
			return Error.ERR_BUSY
		print("Server: Send")
		return ws.send(p)

func _ready() -> void:
	load_count_file()

	var err := tcp.listen(PORT)
	if err:
		push_error("server.listen ", error_string(err))
		return
	print("Listening")

	err = server_thread.start(run_server, Thread.PRIORITY_HIGH)
	if err:
		push_error("thread.start ", error_string(err))
		return


func run_server() -> void:
	while not shutdown:
		while tcp.is_connection_available():
			print("Taking Connection")
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
		push_error("ws.accept_stream returned ", error_string(err))
		return

	var conn := ClientConnection.new(ws, t)
	locked_ctx(func() -> void:
		print("clients.append")
		clients.append(conn)
	)

	while true:
		ws.poll()
		match ws.get_ready_state():
			ws.STATE_OPEN:
				if shutdown:
					print("shutdown: Closing Connection")
					ws.close()
					continue

				while ws.get_available_packet_count():
					print("Server: Packet received")
					var p := API.parse_packet(ws.get_packet())
					if not p:
						push_error("Invalid Packet received")
						break

					if p is API.IncreasePacket:
						locked_ctx(func() -> void:
							count += 1
							sync()
						)
					elif p is API.HelloPacket:
						print("Receive Hello")
						conn.ready = true
						locked_ctx(sync.bind(conn))
					else:
						push_error("Invalid PacketType received: ", p.type)
						break

			ws.STATE_CLOSED:
				print("Closed Connection")
				locked_ctx(func() -> void:
					print("clients.erase")
					print(clients)
					clients.erase(conn)
					print(clients)
					sync()
				)
				break

		OS.delay_msec(DELAY_MS)


func locked_ctx(f: Callable) -> void:
	mutex.lock()
	f.call()
	mutex.unlock()


## Needs locked_ctx!
func sync(override: ClientConnection = null) -> void:
	print("Sync")
	var p := API.SyncPacket.new(count, clients.size()).encode()
	if override:
		var err := override.send_packet(p)
		if err:
			push_error("conn.send_packet returned ", error_string(err))
	else:
		for conn in clients:
			if not conn.ready: continue

			var err := conn.send_packet(p)
			if err:
				push_error("conn.send_packet returned ", error_string(err))
				continue


func load_count_file() -> void:
	var file_str := FileAccess.get_file_as_string(PATH)
	if file_str.is_empty():
		var err := FileAccess.get_open_error()
		if err:
			push_warning("FileAccess.get_file_as_string ", error_string(err))
			return

	if not file_str.is_valid_int():
		push_error("File content invalid")
		return

	var file_int := file_str.to_int()
	if file_int < 0:
		push_warning("Stored count is negative")
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
			push_error("FileAccess.open returned ", error_string(FileAccess.get_open_error()))

		print("Waiting for Server thread ", server_thread)
		server_thread.wait_to_finish()

		for conn in clients:
			print("Waiting for Client thread ", conn.thread)
			conn.thread.wait_to_finish()

		print("Quit")
		get_tree().quit()
