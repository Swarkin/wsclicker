class_name API

enum PacketType {
	HELLO,
	SYNC,
	INCREASE,
	MAX,
}

## Base Packet type
class Packet:
	var type: PacketType

	func _init(_type: PacketType) -> void:
		type = _type


## Sent to the Server to indicate availability
class HelloPacket extends Packet:
	const SIZE := 1

	func _init() -> void:
		type = PacketType.HELLO

	static func encode() -> PackedByteArray:
		var b := PackedByteArray()
		b.resize(1)
		b.encode_u8(0, PacketType.HELLO)
		return b

	static func decode(b: PackedByteArray) -> HelloPacket:
		if not b.size() == SIZE: return
		if not b.decode_u8(0) == PacketType.HELLO: return
		return HelloPacket.new()


## Sent to the Client to update the state
class SyncPacket extends Packet:
	const SIZE := 8
	var amount: int
	var players: int

	func _init(_amount: int, _players: int) -> void:
		type = PacketType.SYNC
		amount = _amount
		players = _players

	func encode() -> PackedByteArray:
		print("encode")
		print("type ", type)
		print("amount ", amount)
		print("players ", players)
		var b := PackedByteArray()
		b.resize(SIZE)
		b.encode_u8(0, type)
		b.encode_u32(1, amount)
		b.encode_u32(5, players)
		return b

	@warning_ignore("shadowed_variable")
	static func decode(b: PackedByteArray) -> SyncPacket:
		if not b.size() == SIZE: return
		if not b.decode_u8(0) == PacketType.SYNC: return
		var amount := b.decode_u32(1)
		var players := b.decode_u32(5)
		return SyncPacket.new(amount, players)


## Sent to the Server to increase the counter
class IncreasePacket extends Packet:
	const SIZE := 1

	func _init() -> void:
		type = PacketType.INCREASE

	static func encode() -> PackedByteArray:
		var b := PackedByteArray()
		b.resize(1)
		b.encode_u8(0, PacketType.INCREASE)
		return b

	static func decode(b: PackedByteArray) -> IncreasePacket:
		if not b.size() == SIZE: return
		if not b.decode_u8(0) == PacketType.INCREASE: return
		return IncreasePacket.new()


static func parse_packet(p: PackedByteArray) -> API.Packet:
	if p.is_empty(): return

	var type_int := p.decode_u8(0)
	if type_int >= API.PacketType.MAX: return

	match type_int as API.PacketType:
		API.PacketType.HELLO:
			return API.HelloPacket.decode(p)
		API.PacketType.SYNC:
			return API.SyncPacket.decode(p)
		API.PacketType.INCREASE:
			return API.IncreasePacket.decode(p)
		_: return
