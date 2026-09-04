extends Node

# =========================================================
# SNAKE ARAB ONLINE
# NETWORK MANAGER
# STEP 6.6.4
# =========================================================

signal connected_to_server
signal connection_failed
signal player_joined(peer_id)
signal player_left(peer_id)
signal server_started

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 20

const MAP_SIZE := Vector2(4000.0, 4000.0)
const SPAWN_MARGIN := 350.0
const MIN_SPAWN_DISTANCE := 500.0

var peer: ENetMultiplayerPeer

var is_server := false
var is_connected := false

var server_ip := "127.0.0.1"
var server_port := DEFAULT_PORT

var connected_players: Dictionary = {}
var player_spawns: Dictionary = {}

var rng := RandomNumberGenerator.new()


# =========================================================
# READY
# =========================================================

func _ready() -> void:

	rng.randomize()

	multiplayer.peer_connected.connect(
		_on_peer_connected
	)

	multiplayer.peer_disconnected.connect(
		_on_peer_disconnected
	)

	multiplayer.connected_to_server.connect(
		_on_connected_to_server
	)

	multiplayer.connection_failed.connect(
		_on_connection_failed
	)

	multiplayer.server_disconnected.connect(
		_on_server_disconnected
	)


# =========================================================
# CREATE SERVER
# =========================================================

func create_server(
	port: int = DEFAULT_PORT
) -> bool:

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
	player_spawns.clear()

	var host_id := multiplayer.get_unique_id()

	var host_spawn := _generate_spawn_position()

	player_spawns[host_id] = host_spawn

	connected_players[host_id] = {
		"name": Global.player_name,
		"id": host_id,
		"spawn": host_spawn
	}

	server_started.emit()

	print(
		"Server started: ",
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

	disconnect_from_network()

	peer = ENetMultiplayerPeer.new()

	var result := peer.create_client(
		ip,
		port
	)

	if result != OK:

		push_error(
			"فشل إنشاء اتصال السيرفر: %s" % result
		)

		connection_failed.emit()

		return false

	multiplayer.multiplayer_peer = peer

	is_server = false
	is_connected = false

	server_ip = ip
	server_port = port

	print(
		"Connecting to ",
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
	player_spawns.clear()


# =========================================================
# CONNECTED TO SERVER
# =========================================================

func _on_connected_to_server() -> void:

	is_connected = true

	print(
		"Connected. ID: ",
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

	connected_players.clear()
	player_spawns.clear()

	print(
		"Server disconnected"
	)


# =========================================================
# PEER CONNECTED
# =========================================================

func _on_peer_connected(
	peer_id: int
) -> void:

	print(
		"Peer connected: ",
		peer_id
	)

	if not is_server:
		return

	# إعطاء اللاعب مكان Spawn جديد
	var spawn_position := _generate_spawn_position()

	player_spawns[peer_id] = spawn_position

	connected_players[peer_id] = {
		"name": "لاعب",
		"id": peer_id,
		"spawn": spawn_position
	}

	# إرسال قائمة اللاعبين كاملة للاعب الجديد
	sync_player_list.rpc_id(
		peer_id,
		connected_players
	)

	# إرسال Spawn للاعب الجديد
	assign_spawn.rpc_id(
		peer_id,
		spawn_position
	)

	player_joined.emit(
		peer_id
	)


# =========================================================
# PEER DISCONNECTED
# =========================================================

func _on_peer_disconnected(
	peer_id: int
) -> void:

	print(
		"Peer disconnected: ",
		peer_id
	)

	connected_players.erase(
		peer_id
	)

	player_spawns.erase(
		peer_id
	)

	if is_server:

		broadcast_player_left.rpc(
			peer_id
		)

	player_left.emit(
		peer_id
	)


# =========================================================
# REGISTER PLAYER
# =========================================================

@rpc("any_peer", "reliable")
func register_player(
	player_name: String
) -> void:

	if not multiplayer.is_server():
		return

	var sender_id := (
		multiplayer.get_remote_sender_id()
	)

	if not connected_players.has(
		sender_id
	):
		return

	if player_name.strip_edges().is_empty():
		player_name = "لاعب"

	player_name = player_name.strip_edges()

	connected_players[
		sender_id
	]["name"] = player_name

	print(
		"Player registered: ",
		player_name,
		" / ",
		sender_id
	)

	# إرسال قائمة اللاعبين للجميع
	sync_player_list.rpc(
		connected_players
	)


# =========================================================
# SYNC PLAYER LIST
# =========================================================

@rpc(
	"authority",
	"call_local",
	"reliable"
)
func sync_player_list(
	players: Dictionary
) -> void:

	connected_players = players.duplicate(
		true
	)

	print(
		"Players synchronized: ",
		connected_players.size()
	)

	var game := get_tree().current_scene

	if game == null:
		return

	if game.has_method(
		"sync_network_players"
	):

		game.sync_network_players(
			connected_players
		)


# =========================================================
# ASSIGN SPAWN
# =========================================================

@rpc(
	"authority",
	"call_local",
	"reliable"
)
func assign_spawn(
	spawn_position: Vector2
) -> void:

	var local_id := (
		multiplayer.get_unique_id()
	)

	player_spawns[
		local_id
	] = spawn_position

	var game := get_tree().current_scene

	if game == null:
		return

	if game.has_method(
		"set_local_spawn"
	):

		game.set_local_spawn(
			spawn_position
		)


# =========================================================
# BROADCAST PLAYER LEFT
# =========================================================

@rpc(
	"authority",
	"call_local",
	"reliable"
)
func broadcast_player_left(
	peer_id: int
) -> void:

	var game := get_tree().current_scene

	if game == null:
		return

	if game.has_method(
		"remote_player_left"
	):

		game.remote_player_left(
			peer_id
		)


# =========================================================
# GENERATE SPAWN
# =========================================================

func _generate_spawn_position() -> Vector2:

	var attempts := 0

	while attempts < 100:

		attempts += 1

		var candidate := Vector2(
			rng.randf_range(
				SPAWN_MARGIN,
				MAP_SIZE.x -
				SPAWN_MARGIN
			),

			rng.randf_range(
				SPAWN_MARGIN,
				MAP_SIZE.y -
				SPAWN_MARGIN
			)
		)

		var valid := true

		for existing_spawn in player_spawns.values():

			var existing := (
				existing_spawn as Vector2
			)

			if candidate.distance_to(
				existing
			) < MIN_SPAWN_DISTANCE:

				valid = false

				break

		if valid:
			return candidate

	# إذا لم نجد مكانًا مناسبًا
	# نستخدم موقعًا عشوائيًا آمنًا

	return Vector2(
		rng.randf_range(
			SPAWN_MARGIN,
			MAP_SIZE.x -
			SPAWN_MARGIN
		),

		rng.randf_range(
			SPAWN_MARGIN,
			MAP_SIZE.y -
			SPAWN_MARGIN
		)
	)


# =========================================================
# PLAYER STATE
# =========================================================

@rpc(
	"any_peer",
	"unreliable_ordered"
)
func send_player_state(
	player_position: Vector2,
	player_direction: Vector2,
	player_length: int,
	player_alive: bool
) -> void:

	if not multiplayer.is_server():
		return

	var sender_id := (
		multiplayer.get_remote_sender_id()
	)

	if not connected_players.has(
		sender_id
	):
		return

	# حفظ آخر حالة للاعب
	connected_players[
		sender_id
	]["position"] = player_position

	connected_players[
		sender_id
	]["direction"] = player_direction

	connected_players[
		sender_id
	]["length"] = player_length

	connected_players[
		sender_id
	]["alive"] = player_alive

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

@rpc(
	"authority",
	"unreliable_ordered"
)
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
# BROADCAST LOCAL PLAYER STATE
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

		var local_id := (
			multiplayer.get_unique_id()
		)

		update_remote_player.rpc(
			local_id,
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
# PLAYER DEATH
# =========================================================

@rpc(
	"any_peer",
	"reliable"
)
func send_player_death() -> void:

	if not multiplayer.is_server():
		return

	var sender_id := (
		multiplayer.get_remote_sender_id()
	)

	broadcast_player_death.rpc(
		sender_id
	)


@rpc(
	"authority",
	"call_local",
	"reliable"
)
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
# PLAYER RESPAWN
# =========================================================

@rpc(
	"any_peer",
	"reliable"
)
func send_player_respawn(
	player_position: Vector2
) -> void:

	if not multiplayer.is_server():
		return

	var sender_id := (
		multiplayer.get_remote_sender_id()
	)

	connected_players[
		sender_id
	]["position"] = player_position

	connected_players[
		sender_id
	]["alive"] = true

	broadcast_player_respawn.rpc(
		sender_id,
		player_position
	)


@rpc(
	"authority",
	"call_local",
	"reliable"
)
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
# PLAYER COUNT
# =========================================================

func get_player_count() -> int:

	return connected_players.size()


# =========================================================
# PLAYER NAME
# =========================================================

func get_player_name(
	peer_id: int
) -> String:

	if not connected_players.has(
		peer_id
	):

		return "لاعب"

	return str(
		connected_players[
			peer_id
		].get(
			"name",
			"لاعب"
		)
	)


# =========================================================
# PLAYER SPAWN
# =========================================================

func get_player_spawn(
	peer_id: int
) -> Vector2:

	if player_spawns.has(
		peer_id
	):

		return player_spawns[
			peer_id
		]

	if connected_players.has(
		peer_id
	):

		var data: Dictionary = (
			connected_players[peer_id]
		)

		if data.has("spawn"):

			return data["spawn"]

	return MAP_SIZE / 2.0


# =========================================================
# LOCAL ID
# =========================================================

func get_local_player_id() -> int:

	return multiplayer.get_unique_id()


# =========================================================
# HOST CHECK
# =========================================================

func is_host() -> bool:

	return is_server


# =========================================================
# CONNECTION CHECK
# =========================================================

func is_network_connected() -> bool:

	return is_connected
