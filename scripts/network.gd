extends Node

# =========================================================
# SNAKE ARAB ONLINE
# MULTIPLAYER NETWORK SYSTEM
# STEP 6.6.1
# =========================================================

signal connected_to_server
signal connection_failed
signal player_joined(peer_id)
signal player_left(peer_id)
signal server_started

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 20

var peer: ENetMultiplayerPeer

var is_server := false
var is_connected := false

var server_ip := "127.0.0.1"
var server_port := DEFAULT_PORT

var connected_players: Dictionary = {}


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# =========================================================
# CREATE SERVER
# =========================================================

func create_server(port: int = DEFAULT_PORT) -> bool:

	if is_connected:
		disconnect_from_network()

	peer = ENetMultiplayerPeer.new()

	var result := peer.create_server(
		port,
		MAX_PLAYERS
	)

	if result != OK:
		push_error(
			"فشل إنشاء السيرفر: %s" % result
		)

		return false

	multiplayer.multiplayer_peer = peer

	is_server = true
	is_connected = true

	server_port = port

	connected_players.clear()

	connected_players[
		multiplayer.get_unique_id()
	] = {
		"name": Global.player_name,
		"id": multiplayer.get_unique_id()
	}

	server_started.emit()

	print(
		"Server started on port: ",
		port
	)

	return true


# =========================================================
# CONNECT TO SERVER
# =========================================================

func connect_to_server(
	ip: String,
	port: int = DEFAULT_PORT
) -> bool:

	if is_connected:
		disconnect_from_network()

	peer = ENetMultiplayerPeer.new()

	var result := peer.create_client(
		ip,
		port
	)

	if result != OK:
		push_error(
			"فشل الاتصال بالسيرفر: %s" % result
		)

		connection_failed.emit()

		return false

	multiplayer.multiplayer_peer = peer

	is_server = false
	is_connected = false

	server_ip = ip
	server_port = port

	print(
		"Connecting to server: ",
		ip,
		":",
		port
	)

	return true


# =========================================================
# DISCONNECT
# =========================================================

func disconnect_from_network() -> void:

	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()

	multiplayer.multiplayer_peer = null

	is_server = false
	is_connected = false

	connected_players.clear()


# =========================================================
# CONNECTED
# =========================================================

func _on_connected_to_server() -> void:

	is_connected = true

	print(
		"Connected to server. ID: ",
		multiplayer.get_unique_id()
	)

	connected_to_server.emit()

	register_player.rpc_id(
		1,
		Global.player_name
	)


# =========================================================
# CONNECTION FAILED
# =========================================================

func _on_connection_failed() -> void:

	is_connected = false

	print(
		"Connection failed"
	)

	connection_failed.emit()


# =========================================================
# SERVER DISCONNECTED
# =========================================================

func _on_server_disconnected() -> void:

	is_connected = false

	print(
		"Server disconnected"
	)

	connected_players.clear()


# =========================================================
# PLAYER CONNECTED
# =========================================================

func _on_peer_connected(peer_id: int) -> void:

	print(
		"Player connected: ",
		peer_id
	)

	if is_server:

		connected_players[peer_id] = {
			"name": "لاعب",
			"id": peer_id
		}

	player_joined.emit(peer_id)


# =========================================================
# PLAYER DISCONNECTED
# =========================================================

func _on_peer_disconnected(peer_id: int) -> void:

	print(
		"Player disconnected: ",
		peer_id
	)

	connected_players.erase(peer_id)

	player_left.emit(peer_id)


# =========================================================
# REGISTER PLAYER
# =========================================================

@rpc("any_peer", "reliable")
func register_player(player_name: String) -> void:

	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	connected_players[sender_id] = {
		"name": player_name,
		"id": sender_id
	}

	print(
		"Registered player: ",
		player_name,
		" ID: ",
		sender_id
	)

	sync_player_list.rpc(
		connected_players
	)


# =========================================================
# PLAYER LIST
# =========================================================

@rpc("authority", "call_local", "reliable")
func sync_player_list(players: Dictionary) -> void:

	connected_players = players.duplicate(true)

	print(
		"Players online: ",
		connected_players.size()
	)


# =========================================================
# SEND PLAYER STATE
# =========================================================

@rpc("any_peer", "unreliable_ordered")
func send_player_state(
	player_position: Vector2,
	player_direction: Vector2,
	player_length: int,
	player_alive: bool
) -> void:

	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	update_remote_player.rpc(
		sender_id,
		player_position,
		player_direction,
		player_length,
		player_alive
	)


# =========================================================
# UPDATE REMOTE PLAYER
# =========================================================

@rpc("authority", "unreliable_ordered")
func update_remote_player(
	peer_id: int,
	player_position: Vector2,
	player_direction: Vector2,
	player_length: int,
	player_alive: bool
) -> void:

	var game := get_tree().current_scene

	if game == null:
		return

	if game.has_method(
		"update_remote_player"
	):
		game.update_remote_player(
			peer_id,
			player_position,
			player_direction,
			player_length,
			player_alive
		)


# =========================================================
# BROADCAST PLAYER STATE
# =========================================================

func broadcast_player_state(
	player_position: Vector2,
	player_direction: Vector2,
	player_length: int,
	player_alive: bool
) -> void:

	if not is_connected:
		return

	if is_server:
		update_remote_player.rpc(
			multiplayer.get_unique_id(),
			player_position,
			player_direction,
			player_length,
			player_alive
		)

	else:
		send_player_state.rpc(
			player_position,
			player_direction,
			player_length,
			player_alive
		)


# =========================================================
# SEND DEATH
# =========================================================

@rpc("any_peer", "reliable")
func send_player_death() -> void:

	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	broadcast_player_death.rpc(
		sender_id
	)


# =========================================================
# BROADCAST DEATH
# =========================================================

@rpc("authority", "call_local", "reliable")
func broadcast_player_death(
	peer_id: int
) -> void:

	var game := get_tree().current_scene

	if game == null:
		return

	if game.has_method(
		"remote_player_died"
	):
		game.remote_player_died(
			peer_id
		)


# =========================================================
# SEND RESPAWN
# =========================================================

@rpc("any_peer", "reliable")
func send_player_respawn(
	player_position: Vector2
) -> void:

	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	broadcast_player_respawn.rpc(
		sender_id,
		player_position
	)


# =========================================================
# BROADCAST RESPAWN
# =========================================================

@rpc("authority", "call_local", "reliable")
func broadcast_player_respawn(
	peer_id: int,
	player_position: Vector2
) -> void:

	var game := get_tree().current_scene

	if game == null:
		return

	if game.has_method(
		"remote_player_respawned"
	):
		game.remote_player_respawned(
			peer_id,
			player_position
		)


# =========================================================
# GET PLAYER COUNT
# =========================================================

func get_player_count() -> int:

	return connected_players.size()


# =========================================================
# GET PLAYER NAME
# =========================================================

func get_player_name(
	peer_id: int
) -> String:

	if not connected_players.has(peer_id):
		return "لاعب"

	return str(
		connected_players[peer_id].get(
			"name",
			"لاعب"
		)
	)


# =========================================================
# CHECK SERVER
# =========================================================

func is_host() -> bool:

	return is_server


# =========================================================
# CHECK CONNECTION
# =========================================================

func is_network_connected() -> bool:

	return is_connected


# =========================================================
# GET UNIQUE ID
# =========================================================

func get_local_player_id() -> int:

	return multiplayer.get_unique_id()
