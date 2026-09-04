extends Node

# =========================================================
# SNAKE ARAB ONLINE
# NETWORK
# STEP 6.6.6
# SERVER AUTHORITATIVE SNAKE COLLISIONS
# =========================================================

signal player_joined(peer_id: int, player_data: Dictionary)
signal player_left(peer_id: int)
signal connected
signal disconnected

const PORT := 7777
const MAX_PLAYERS := 20

const MAP_SIZE := Vector2(4000.0, 4000.0)
const SPAWN_MARGIN := 350.0
const MIN_SPAWN_DISTANCE := 500.0

const COLLISION_DISTANCE := 32.0
const HEAD_TO_HEAD_DISTANCE := 42.0

var peer: ENetMultiplayerPeer

var is_server := false

var connected_players: Dictionary = {}
var player_spawns: Dictionary = {}

# آخر حالة معروفة لكل لاعب
var player_states: Dictionary = {}

# حماية بسيطة من إرسال أوامر متكررة بسرعة
var last_collision_check := 0.0

# =========================================================
# READY
# =========================================================

func _ready() -> void:

	multiplayer.peer_connected.connect(
		_on_peer_connected
	)

	multiplayer.peer_disconnected.connect(
		_on_peer_disconnected
	)

	print("Network initialized")


# =========================================================
# HOST
# =========================================================

func create_server() -> bool:

	peer = ENetMultiplayerPeer.new()

	var result := peer.create_server(
		PORT,
		MAX_PLAYERS
	)

	if result != OK:

		push_error(
			"Failed to create server: %s" % result
		)

		return false

	multiplayer.multiplayer_peer = peer

	is_server = true

	var local_id := multiplayer.get_unique_id()

	var spawn := _generate_spawn_position()

	connected_players[local_id] = {
		"name": _get_local_player_name(),
		"spawn": spawn,
		"alive": true
	}

	player_spawns[local_id] = spawn

	player_states[local_id] = {
		"position": spawn,
		"direction": Vector2.RIGHT,
		"length": 10,
		"alive": true
	}

	print(
		"Server started on port ",
		PORT
	)

	print(
		"Host spawn: ",
		spawn
	)

	return true


# =========================================================
# CONNECT TO SERVER
# =========================================================

func connect_to_server(
	address: String
) -> bool:

	peer = ENetMultiplayerPeer.new()

	var result := peer.create_client(
		address,
		PORT
	)

	if result != OK:

		push_error(
			"Failed to connect: %s" % result
		)

		return false

	multiplayer.multiplayer_peer = peer

	is_server = false

	print(
		"Connecting to server: ",
		address
	)

	return true


# =========================================================
# DISCONNECT
# =========================================================

func disconnect_from_server() -> void:

	if multiplayer.multiplayer_peer:

		multiplayer.multiplayer_peer.close()

	multiplayer.multiplayer_peer = null

	connected_players.clear()
	player_spawns.clear()
	player_states.clear()

	is_server = false

	disconnected.emit()


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

	var spawn := _generate_spawn_position()

	player_spawns[peer_id] = spawn

	connected_players[peer_id] = {
		"name": "لاعب",
		"spawn": spawn,
		"alive": true
	}

	player_states[peer_id] = {
		"position": spawn,
		"direction": Vector2.RIGHT,
		"length": 10,
		"alive": true
	}

	# أرسل للاعب الجديد قائمة اللاعبين
	sync_player_list.rpc_id(
		peer_id,
		connected_players
	)

	# أعطه Spawn
	assign_spawn.rpc_id(
		peer_id,
		spawn
	)

	# أخبر الجميع بوجود اللاعب الجديد
	var data: Dictionary = connected_players[peer_id]

	player_joined.emit(
		peer_id,
		data
	)

	_broadcast_player_joined(
		peer_id,
		data
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

	connected_players.erase(peer_id)
	player_spawns.erase(peer_id)
	player_states.erase(peer_id)

	player_left.emit(peer_id)

	if is_server:

		broadcast_player_left.rpc(
			peer_id
		)


# =========================================================
# BROADCAST PLAYER JOINED
# =========================================================

@rpc("authority", "call_remote", "reliable")
func broadcast_player_joined(
	peer_id: int,
	player_data: Dictionary
) -> void:

	connected_players[peer_id] = player_data

	player_joined.emit(
		peer_id,
		player_data
	)

	var scene := get_tree().current_scene

	if scene and scene.has_method(
		"_on_player_joined"
	):

		scene._on_player_joined(
			peer_id,
			player_data
		)


# =========================================================
# BROADCAST PLAYER LEFT
# =========================================================

@rpc("authority", "call_remote", "reliable")
func broadcast_player_left(
	peer_id: int
) -> void:

	connected_players.erase(peer_id)
	player_spawns.erase(peer_id)
	player_states.erase(peer_id)

	player_left.emit(peer_id)

	var scene := get_tree().current_scene

	if scene and scene.has_method(
		"remote_player_left"
	):

		scene.remote_player_left(
			peer_id
		)


# =========================================================
# REGISTER PLAYER
# =========================================================

@rpc("any_peer", "reliable")
func register_player(
	player_name: String
) -> void:

	var sender_id := multiplayer.get_remote_sender_id()

	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	if not is_server:
		return

	if not connected_players.has(sender_id):

		var spawn := _generate_spawn_position()

		player_spawns[sender_id] = spawn

		connected_players[sender_id] = {
			"name": player_name,
			"spawn": spawn,
			"alive": true
		}

		player_states[sender_id] = {
			"position": spawn,
			"direction": Vector2.RIGHT,
			"length": 10,
			"alive": true
		}

	else:

		connected_players[sender_id]["name"] = (
			player_name
		)

	var data: Dictionary = connected_players[
		sender_id
	]

	sync_player_list.rpc(
		connected_players
	)

	assign_spawn.rpc_id(
		sender_id,
		player_spawns[sender_id]
	)

	_broadcast_player_joined(
		sender_id,
		data
	)


# =========================================================
# SYNC PLAYER LIST
# =========================================================

@rpc("authority", "call_local", "reliable")
func sync_player_list(
	players: Dictionary
) -> void:

	connected_players = players.duplicate(true)

	for key in players.keys():

		var peer_id := int(key)

		if players[key].has("spawn"):

			player_spawns[peer_id] = (
				players[key]["spawn"]
			)

	var scene := get_tree().current_scene

	if scene and scene.has_method(
		"sync_network_players"
	):

		scene.sync_network_players(
			connected_players
		)


# =========================================================
# ASSIGN SPAWN
# =========================================================

@rpc("authority", "call_remote", "reliable")
func assign_spawn(
	spawn_position: Vector2
) -> void:

	var local_id := multiplayer.get_unique_id()

	player_spawns[local_id] = spawn_position

	var scene := get_tree().current_scene

	if scene and scene.has_method(
		"set_local_spawn"
	):

		scene.set_local_spawn(
			spawn_position
		)


# =========================================================
# BROADCAST JOIN
# =========================================================

func _broadcast_player_joined(
	peer_id: int,
	player_data: Dictionary
) -> void:

	if not is_server:
		return

	broadcast_player_joined.rpc(
		peer_id,
		player_data
	)


# =========================================================
# PLAYER STATE
# =========================================================

@rpc("any_peer", "unreliable_ordered")
func receive_player_state(
	player_position: Vector2,
	player_direction: Vector2,
	player_length: int,
	player_alive: bool
) -> void:

	if not is_server:
		return

	var sender_id := multiplayer.get_remote_sender_id()

	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	# حماية من أطوال غير منطقية
	player_length = clamp(
		player_length,
		5,
		10000
	)

	# حماية من الإحداثيات الخارجة جدًا
	player_position.x = clamp(
		player_position.x,
		0.0,
		MAP_SIZE.x
	)

	player_position.y = clamp(
		player_position.y,
		0.0,
		MAP_SIZE.y
	)

	player_states[sender_id] = {
		"position": player_position,
		"direction": player_direction,
		"length": player_length,
		"alive": player_alive
	}

	if connected_players.has(sender_id):

		connected_players[sender_id]["alive"] = (
			player_alive
		)

	# فحص التصادم على السيرفر
	_check_server_collisions()

	# بث الحالة إلى جميع العملاء
	update_remote_player.rpc(
		sender_id,
		player_position,
		player_direction,
		player_length,
		player_alive
	)


# =========================================================
# LOCAL PLAYER STATE
# =========================================================

func broadcast_player_state(
	player_position: Vector2,
	player_direction: Vector2,
	player_length: int,
	player_alive: bool
) -> void:

	if not multiplayer.has_multiplayer_peer():
		return

	if is_server:

		var local_id := multiplayer.get_unique_id()

		player_states[local_id] = {
			"position": player_position,
			"direction": player_direction,
			"length": player_length,
			"alive": player_alive
		}

		_check_server_collisions()

		update_remote_player.rpc(
			local_id,
			player_position,
			player_direction,
			player_length,
			player_alive
		)

	else:

		receive_player_state.rpc(
			player_position,
			player_direction,
			player_length,
			player_alive
		)


# =========================================================
# UPDATE REMOTE PLAYER
# =========================================================

@rpc("authority", "call_remote", "unreliable_ordered")
func update_remote_player(
	peer_id: int,
	player_position: Vector2,
	player_direction: Vector2,
	player_length: int,
	player_alive: bool
) -> void:

	player_states[peer_id] = {
		"position": player_position,
		"direction": player_direction,
		"length": player_length,
		"alive": player_alive
	}

	var scene := get_tree().current_scene

	if scene and scene.has_method(
		"update_remote_player"
	):

		scene.update_remote_player(
			peer_id,
			player_position,
			player_direction,
			player_length,
			player_alive
		)


# =========================================================
# SERVER COLLISION SYSTEM
# =========================================================

func _check_server_collisions() -> void:

	if not is_server:
		return

	var now := Time.get_ticks_msec() / 1000.0

	if now - last_collision_check < 0.08:
		return

	last_collision_check = now

	var ids := player_states.keys()

	for i in range(ids.size()):

		var first_id := int(ids[i])

		if not player_states.has(first_id):
			continue

		var first_state: Dictionary = (
			player_states[first_id]
		)

		if not first_state.get(
			"alive",
			true
		):
			continue

		for j in range(
			i + 1,
			ids.size()
		):

			var second_id := int(ids[j])

			if not player_states.has(
				second_id
			):
				continue

			var second_state: Dictionary = (
				player_states[second_id]
			)

			if not second_state.get(
				"alive",
				true
			):
				continue

			_check_snake_pair(
				first_id,
				first_state,
				second_id,
				second_state
			)


# =========================================================
# CHECK TWO SNAKES
# =========================================================

func _check_snake_pair(
	first_id: int,
	first_state: Dictionary,
	second_id: int,
	second_state: Dictionary
) -> void:

	var first_position: Vector2 = (
		first_state["position"]
	)

	var second_position: Vector2 = (
		second_state["position"]
	)

	var distance := first_position.distance_to(
		second_position
	)

	# رأس مقابل رأس
	if distance <= HEAD_TO_HEAD_DISTANCE:

		var first_length := int(
			first_state["length"]
		)

		var second_length := int(
			second_state["length"]
		)

		if first_length > second_length:

			_kill_player(
				second_id,
				first_id
			)

		elif second_length > first_length:

			_kill_player(
				first_id,
				second_id
			)

		else:

			# إذا كانا بنفس الطول يموتان
			_kill_player(
				first_id,
				second_id
			)

			_kill_player(
				second_id,
				first_id
			)

		return

	# اصطدام جسم أحد اللاعبين
	if distance <= COLLISION_DISTANCE:

		var first_length := int(
			first_state["length"]
		)

		var second_length := int(
			second_state["length"]
		)

		if first_length >= second_length:

			_kill_player(
				second_id,
				first_id
			)

		else:

			_kill_player(
				first_id,
				second_id
			)


# =========================================================
# KILL PLAYER
# =========================================================

func _kill_player(
	victim_id: int,
	killer_id: int
) -> void:

	if not is_server:
		return

	if not player_states.has(victim_id):
		return

	if not player_states[victim_id].get(
		"alive",
		true
	):
		return

	player_states[victim_id]["alive"] = false

	if connected_players.has(victim_id):

		connected_players[victim_id]["alive"] = false

	var victim_position: Vector2 = (
		player_states[victim_id]["position"]
	)

	var victim_length := int(
		player_states[victim_id]["length"]
	)

	var reward := max(
		10,
		victim_length * 2
	)

	if player_states.has(killer_id):

		player_states[killer_id]["length"] = (
			int(
				player_states[killer_id]["length"]
			) + min(
				victim_length,
				50
			)
		)

	# إرسال الموت
	player_died.rpc(
		victim_id,
		killer_id,
		victim_position,
		reward
	)

	# إرسال تحديث الحالة
	update_remote_player.rpc(
		victim_id,
		victim_position,
		Vector2.RIGHT,
		victim_length,
		false
	)

	print(
		"Player ",
		victim_id,
		" killed by ",
		killer_id
	)


# =========================================================
# PLAYER DIED RPC
# =========================================================

@rpc("authority", "call_remote", "reliable")
func player_died(
	victim_id: int,
	killer_id: int,
	death_position: Vector2,
	reward: int
) -> void:

	var scene := get_tree().current_scene

	if scene and scene.has_method(
		"network_player_died"
	):

		scene.network_player_died(
			victim_id,
			killer_id,
			death_position,
			reward
		)

	elif scene and scene.has_method(
		"remote_player_died"
	):

		scene.remote_player_died(
			victim_id
		)


# =========================================================
# BROADCAST DEATH
# =========================================================

func broadcast_player_death() -> void:

	if not multiplayer.has_multiplayer_peer():
		return

	if is_server:

		var local_id := multiplayer.get_unique_id()

		if player_states.has(local_id):

			player_states[local_id]["alive"] = false

			player_died.rpc(
				local_id,
				0,
				player_states[local_id]["position"],
				0
			)

	else:

		request_player_death.rpc()


# =========================================================
# REQUEST DEATH
# =========================================================

@rpc("any_peer", "reliable")
func request_player_death() -> void:

	if not is_server:
		return

	var sender_id := multiplayer.get_remote_sender_id()

	if player_states.has(sender_id):

		player_states[sender_id]["alive"] = false

	player_died.rpc(
		sender_id,
		0,
		player_states[sender_id]["position"]
		if player_states.has(sender_id)
		else Vector2.ZERO,
		0
	)


# =========================================================
# RESPAWN
# =========================================================

func broadcast_player_respawn(
	spawn_position: Vector2
) -> void:

	if not multiplayer.has_multiplayer_peer():
		return

	if is_server:

		var local_id := multiplayer.get_unique_id()

		player_states[local_id] = {
			"position": spawn_position,
			"direction": Vector2.RIGHT,
			"length": 10,
			"alive": true
		}

		if connected_players.has(local_id):

			connected_players[local_id]["alive"] = true

		player_respawned.rpc(
			local_id,
			spawn_position
		)

	else:

		request_player_respawn.rpc(
			spawn_position
		)


# =========================================================
# REQUEST RESPAWN
# =========================================================

@rpc("any_peer", "reliable")
func request_player_respawn(
	requested_position: Vector2
) -> void:

	if not is_server:
		return

	var sender_id := multiplayer.get_remote_sender_id()

	var spawn := _generate_spawn_position()

	player_spawns[sender_id] = spawn

	player_states[sender_id] = {
		"position": spawn,
		"direction": Vector2.RIGHT,
		"length": 10,
		"alive": true
	}

	if connected_players.has(sender_id):

		connected_players[sender_id]["spawn"] = spawn
		connected_players[sender_id]["alive"] = true

	player_respawned.rpc(
		sender_id,
		spawn
	)


# =========================================================
# PLAYER RESPAWNED RPC
# =========================================================

@rpc("authority", "call_remote", "reliable")
func player_respawned(
	peer_id: int,
	spawn_position: Vector2
) -> void:

	var scene := get_tree().current_scene

	if scene and scene.has_method(
		"remote_player_respawned"
	):

		scene.remote_player_respawned(
			peer_id,
			spawn_position
		)


# =========================================================
# SPAWN GENERATOR
# =========================================================

func _generate_spawn_position() -> Vector2:

	var best_position := Vector2(
		MAP_SIZE.x / 2.0,
		MAP_SIZE.y / 2.0
	)

	var best_distance := -1.0

	for attempt in range(30):

		var candidate := Vector2(
			randf_range(
				SPAWN_MARGIN,
				MAP_SIZE.x - SPAWN_MARGIN
			),
			randf_range(
				SPAWN_MARGIN,
				MAP_SIZE.y - SPAWN_MARGIN
			)
		)

		var nearest_distance := INF

		for key in player_spawns.keys():

			var existing_position: Vector2 = (
				player_spawns[key]
			)

			var distance := candidate.distance_to(
				existing_position
			)

			nearest_distance = min(
				nearest_distance,
				distance
			)

		if player_spawns.is_empty():
			nearest_distance = INF

		if nearest_distance >= MIN_SPAWN_DISTANCE:

			return candidate

		if nearest_distance > best_distance:

			best_distance = nearest_distance
			best_position = candidate

	return best_position


# =========================================================
# GET PLAYER SPAWN
# =========================================================

func get_player_spawn(
	peer_id: int
) -> Vector2:

	if player_spawns.has(peer_id):

		var value = player_spawns[peer_id]

		if value is Vector2:
			return value

	return Vector2.ZERO


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
# LOCAL PLAYER NAME
# =========================================================

func _get_local_player_name() -> String:

	if Global:

		if Global.player_name != "":
			return Global.player_name

	return "لاعب"


# =========================================================
# PLAYER COUNT
# =========================================================

func get_player_count() -> int:

	return connected_players.size()
