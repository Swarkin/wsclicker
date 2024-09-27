extends Label

@export var server: Server

func _process(_dt: float) -> void:
	server.mutex.lock()
	text = "Counter: %s\nPlayers: %s\nPackets: %s" % [server.count, server.clients.size(), server.packets]
	server.mutex.unlock()
