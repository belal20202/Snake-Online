extends Node

signal connected_to_server
signal connection_failed
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)

const PORT: int = 7777
const MAX_PLAYERS: int = 16

var peer: ENetMultiplayerPeer = null
var is_host: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game() -> bool:
	close_connection()

	peer = ENetMultiplayerPeer.new()

	var error := peer.create_server(PORT, MAX_PLAYERS)

	if error != OK:
		push_error("فشل إنشاء الخادم: %s" % error)
		return false

	multiplayer.multiplayer_peer = peer
	is_host = true

	return true


func join_game(ip_address: String) -> bool:
	close_connection()

	var clean_ip := ip_address.strip_edges()

	if clean_ip.is_empty():
		return false

	peer = ENetMultiplayerPeer.new()

	var error := peer.create_client(clean_ip, PORT)

	if error != OK:
		push_error("فشل الاتصال: %s" % error)
		return false

	multiplayer.multiplayer_peer = peer
	is_host = false

	return true


func close_connection() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()

	multiplayer.multiplayer_peer = null
	peer = null
	is_host = false


func get_player_count() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0

	return multiplayer.get_peers().size() + 1


func _on_peer_connected(peer_id: int) -> void:
	player_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	player_disconnected.emit(peer_id)


func _on_connected_to_server() -> void:
	connected_to_server.emit()


func _on_connection_failed() -> void:
	connection_failed.emit()


func _on_server_disconnected() -> void:
	connection_failed.emit()
