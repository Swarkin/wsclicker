extends Label

@export var server: Server

func _process(_dt: float) -> void:
	text = "Counter: %d\nPlayers: %s" % [server.count, server.clients.size()]
