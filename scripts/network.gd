extends Node

# =========================================================
# Snake Arab Online
# Network Manager
# Step 6.6.8
# Server Authoritative Multiplayer
# =========================================================

signal connected_to_server
signal connection_failed

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)

signal player_joined(peer_id: int, player_name: String)
signal player_left(peer_id: int)

signal network_players_synced(players: Dictionary)

signal player_died(
	peer_id: int,
	killer_id: int,
	death_position: Vector2,
	reward: int
)

signal player_respawned(
	peer_id: int,
	respawn_position: Vector2
)

# =========================================================
# SETTINGS
# =========================================================

const PORT := 7777
const MAX_PLAYERS := 20

const MAP_SIZE := Vector2(4000.0, 4000.0)

const SPAWN_MARGIN := 350.0
const MIN_SPAWN_DISTANCE := 500.0

# Collision
const HEAD_TO_HEAD_DISTANCE := 42.0
const HEAD_TO_BODY_DISTANCE := 34.0
const COLLISION_START_INDEX := 5

# Food
const FOOD_COUNT := 180
const FOOD_VALUE := 10
const FOOD_COIN_VALUE := 5
const FOOD_XP_VALUE := 2
const FOOD_COLLECTION_DISTANCE := 48.0

# Death loot
const DEATH_LOOT_COUNT := 8
const DEATH_LOOT_VALUE := 15
const DEATH_LOOT_COIN_VALUE := 10
const DEATH_LOOT_XP_VALUE := 5
const LOOT_COLLECTION_DISTANCE := 55.0

# Network
const STATE_INTERVAL := 0.05
const MAX_BODY_POINTS := 250

# =========================================================
# NETWORK
# =========================================================

var peer: ENetMultiplayerPeer
var is_host := false

# =========================================================
# PLAYERS
# =========================================================

var connected_players: Dictionary = {}

var player_spawns: Dictionary = {}

var player_states: Dictionary = {}

# =========================================================
# FOOD
# =========================================================

var foods: Dictionary = {}

var next_food_id: int = 1

# =========================================================
# LOOT
# =========================================================

var loot: Dictionary = {}

var next_loot_id: int = 1

# =========================================================
# TIMERS
# =========================================================

var collision_timer := 0.0
var food_timer := 0.0
var loot_timer := 0.0

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

	multiplayer.connected_to_server.connect(
		_on_connected_to_server
	)

	multiplayer.connection_failed.connect(
		_on_connection_failed
	)

	set_process(true)


# =========================================================
# PROCESS
# =========================================================

func _process(delta: float) -> void:

	if not is_host:
		return

	if multiplayer.multiplayer_peer == null:
		return

	collision_timer += delta
	food_timer += delta
	loot_timer += delta

	# Collision check
	if collision_timer >= 0.05:

		collision_timer = 0.0

		_check_server_collisions()

	# Keep food populated
	if food_timer >= 2.0:

		food_timer = 0.0

		_maintain_food()

	# Remove old invalid loot
	if loot_timer >= 5.0:

		loot_timer = 0.0

		_cleanup_loot()


# =========================================================
# HOST GAME
# =========================================================

func host_game() -> bool:

	close_connection()

	peer = ENetMultiplayerPeer.new()

	var error := peer.create_server(
		PORT,
		MAX_PLAYERS
	)

	if error != OK:

		push_error(
			"Failed to create server: %s" % error
		)

		return false

	multiplayer.multiplayer_peer = peer

	is_host = true

	# Server player
	var server_id := multiplayer.get_unique_id()

	var spawn := _generate_spawn_position()

	player_spawns[server_id] = spawn

	connected_players[server_id] = {
		"name": Global.player_name,
		"spawn": spawn
	}

	player_states[server_id] = {
		"position": spawn,
		"direction": Vector2.RIGHT,
		"length": 10,
		"alive": true,
		"body": []
	}

	_create_initial_food()

	return true


# =========================================================
# JOIN GAME
# =========================================================

func join_game(ip_address: String) -> bool:

	close_connection()

	var clean_ip := ip_address.strip_edges()

	if clean_ip.is_empty():
		return false

	peer = ENetMultiplayerPeer.new()

	var error := peer.create_client(
		clean_ip,
		PORT
	)

	if error != OK:

		push_error(
			"Failed to connect: %s" % error
		)

		return false

	multiplayer.multiplayer_peer = peer

	is_host = false

	return true


# =========================================================
# CLOSE
# =========================================================

func close_connection() -> void:

	if multiplayer.multiplayer_peer:

		multiplayer.multiplayer_peer.close()

	multiplayer.multiplayer_peer = null

	peer = null

	is_host = false

	connected_players.clear()
	player_spawns.clear()
	player_states.clear()

	foods.clear()
	loot.clear()


# =========================================================
# PLAYER COUNT
# =========================================================

func get_player_count() -> int:

	if multiplayer.multiplayer_peer == null:
		return 0

	return multiplayer.get_peers().size() + 1


# =========================================================
# PEER CONNECTED
# =========================================================

func _on_peer_connected(peer_id: int) -> void:

	if not is_host:
		return

	var spawn := _generate_spawn_position()

	player_spawns[peer_id] = spawn

	connected_players[peer_id] = {
		"name": "لاعب",
		"spawn": spawn
	}

	player_states[peer_id] = {
		"position": spawn,
		"direction": Vector2.RIGHT,
		"length": 10,
		"alive": true,
		"body": []
	}

	player_connected.emit(peer_id)

	# Tell new player about existing players
	for existing_id in connected_players.keys():

		if existing_id == peer_id:
			continue

		var data: Dictionary = connected_players[existing_id]

		player_joined.rpc_id(
			peer_id,
			existing_id,
			str(data.get("name", "لاعب")),
			data.get("spawn", Vector2.ZERO)
		)

	# Send current food
	for food_id in foods.keys():

		var food_data: Dictionary = foods[food_id]

		food_spawned.rpc_id(
			peer_id,
			food_id,
			food_data["position"],
			food_data["value"],
			food_data["coins"],
			food_data["xp"]
		)

	# Send current loot
	for loot_id in loot.keys():

		var loot_data: Dictionary = loot[loot_id]

		loot_spawned.rpc_id(
			peer_id,
			loot_id,
			loot_data["position"],
			loot_data["value"],
			loot_data["coins"],
			loot_data["xp"]
		)

	# Send spawn to new player
	assign_spawn.rpc_id(
		peer_id,
		spawn
	)

	# Tell everyone
	player_joined.rpc(
		peer_id,
		"لاعب",
		spawn
	)


# =========================================================
# PEER DISCONNECTED
# =========================================================

func _on_peer_disconnected(peer_id: int) -> void:

	connected_players.erase(peer_id)
	player_spawns.erase(peer_id)
	player_states.erase(peer_id)

	player_disconnected.emit(peer_id)

	if is_host:

		player_left.rpc(
			peer_id
		)

		player_left.emit(peer_id)


# =========================================================
# CONNECTED
# =========================================================

func _on_connected_to_server() -> void:

	connected_to_server.emit()

	register_player.rpc_id(
		1,
		Global.player_name
	)


# =========================================================
# CONNECTION FAILED
# =========================================================

func _on_connection_failed() -> void:

	connection_failed.emit()


# =========================================================
# REGISTER PLAYER
# =========================================================

@rpc("any_peer", "reliable")
func register_player(new_name: String) -> void:

	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	var safe_name := new_name.strip_edges()

	if safe_name.is_empty():
		safe_name = "لاعب"

	if safe_name.length() > 18:
		safe_name = safe_name.substr(0, 18)

	if not connected_players.has(sender_id):

		var spawn := _generate_spawn_position()

		player_spawns[sender_id] = spawn

		connected_players[sender_id] = {
			"name": safe_name,
			"spawn": spawn
		}

		player_states[sender_id] = {
			"position": spawn,
			"direction": Vector2.RIGHT,
			"length": 10,
			"alive": true,
			"body": []
		}

	else:

		connected_players[sender_id]["name"] = safe_name

	player_name_updated.rpc(
		sender_id,
		safe_name
	)

	_send_full_player_list()


# =========================================================
# PLAYER NAME UPDATE
# =========================================================

@rpc("authority", "call_remote", "reliable")
func player_name_updated(
	peer_id: int,
	new_name: String
) -> void:

	var game := get_tree().current_scene

	if game and game.has_method("update_remote_player_name"):

		game.update_remote_player_name(
			peer_id,
			new_name
		)


# =========================================================
# FULL PLAYER LIST
# =========================================================

func _send_full_player_list() -> void:

	if not is_host:
		return

	var result: Dictionary = {}

	for id in connected_players.keys():

		var data: Dictionary = connected_players[id]

		result[id] = {
			"name": data.get("name", "لاعب"),
			"spawn": data.get(
				"spawn",
				Vector2.ZERO
			)
		}

	network_players_synced.rpc(
		result
	)


@rpc("authority", "call_remote", "reliable")
func network_players_synced(
	players: Dictionary
) -> void:

	network_players_synced.emit(
		players
	)

	var game := get_tree().current_scene

	if game and game.has_method(
		"sync_network_players"
	):

		game.sync_network_players(
			players
		)


# =========================================================
# PLAYER JOINED RPC
# =========================================================

@rpc("authority", "call_remote", "reliable")
func player_joined(
	peer_id: int,
	new_name: String,
	spawn_position: Vector2
) -> void:

	player_joined.emit(
		peer_id,
		new_name
	)

	var game := get_tree().current_scene

	if game and game.has_method(
		"network_player_joined"
	):

		game.network_player_joined(
			peer_id,
			new_name,
			spawn_position
		)


# =========================================================
# PLAYER LEFT RPC
# =========================================================

@rpc("authority", "call_remote", "reliable")
func player_left(
	peer_id: int
) -> void:

	player_left.emit(
		peer_id
	)

	var game := get_tree().current_scene

	if game and game.has_method(
		"remote_player_left"
	):

		game.remote_player_left(
			peer_id
		)


# =========================================================
# SPAWN
# =========================================================

@rpc("authority", "call_remote", "reliable")
func assign_spawn(
	spawn_position: Vector2
) -> void:

	player_spawns[
		multiplayer.get_unique_id()
	] = spawn_position

	var game := get_tree().current_scene

	if game and game.has_method(
		"set_local_spawn"
	):

		game.set_local_spawn(
			spawn_position
		)


# =========================================================
# GENERATE SPAWN
# =========================================================

func _generate_spawn_position() -> Vector2:

	var best_position := MAP_SIZE / 2.0

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

		var valid := true

		for existing_spawn in player_spawns.values():

			if candidate.distance_to(
				existing_spawn
			) < MIN_SPAWN_DISTANCE:

				valid = false
				break

		if valid:

			best_position = candidate
			break

	return best_position


# =========================================================
# PLAYER STATE
# =========================================================

func broadcast_player_state(
	player_position: Vector2,
	player_direction: Vector2,
	player_length: int,
	player_alive: bool,
	player_body: Array = []
) -> void:

	if multiplayer.multiplayer_peer == null:
		return

	var safe_body: Array = []

	var count := min(
		player_body.size(),
		MAX_BODY_POINTS
	)

	for i in range(count):

		if player_body[i] is Vector2:

			safe_body.append(
				player_body[i]
			)

	if multiplayer.is_server():

		_receive_player_state(
			multiplayer.get_unique_id(),
			player_position,
			player_direction,
			player_length,
			player_alive,
			safe_body
		)

	else:

		send_player_state.rpc_id(
			1,
			player_position,
			player_direction,
			player_length,
			player_alive,
			safe_body
		)


# =========================================================
# STATE RPC
# =========================================================

@rpc("any_peer", "unreliable")
func send_player_state(
	player_position: Vector2,
	player_direction: Vector2,
	player_length: int,
	player_alive: bool,
	player_body: Array
) -> void:

	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	_receive_player_state(
		sender_id,
		player_position,
		player_direction,
		player_length,
		player_alive,
		player_body
	)


# =========================================================
# RECEIVE STATE ON SERVER
# =========================================================

func _receive_player_state(
	peer_id: int,
	player_position: Vector2,
	player_direction: Vector2,
	player_length: int,
	player_alive: bool,
	player_body: Array
) -> void:

	if not player_states.has(peer_id):
		return

	# Keep player inside map
	player_position.x = clamp(
		player_position.x,
		20.0,
		MAP_SIZE.x - 20.0
	)

	player_position.y = clamp(
		player_position.y,
		20.0,
		MAP_SIZE.y - 20.0
	)

	var safe_length := clamp(
		player_length,
		5,
		5000
	)

	var safe_body: Array = []

	var body_count := min(
		player_body.size(),
		MAX_BODY_POINTS
	)

	for i in range(body_count):

		if player_body[i] is Vector2:

			var body_point: Vector2 = player_body[i]

			body_point.x = clamp(
				body_point.x,
				0.0,
				MAP_SIZE.x
			)

			body_point.y = clamp(
				body_point.y,
				0.0,
				MAP_SIZE.y
			)

			safe_body.append(
				body_point
			)

	player_states[peer_id] = {
		"position": player_position,
		"direction": player_direction,
		"length": safe_length,
		"alive": player_alive,
		"body": safe_body
	}

	receive_player_state.rpc(
		peer_id,
		player_position,
		player_direction,
		safe_length,
		player_alive,
		safe_body
	)

	_check_server_collisions()


# =========================================================
# RECEIVE STATE CLIENT
# =========================================================

@rpc("authority", "call_remote", "unreliable")
func receive_player_state(
	peer_id: int,
	player_position: Vector2,
	player_direction: Vector2,
	player_length: int,
	player_alive: bool,
	player_body: Array
) -> void:

	var game := get_tree().current_scene

	if game and game.has_method(
		"update_remote_player"
	):

		game.update_remote_player(
			peer_id,
			player_position,
			player_direction,
			player_length,
			player_alive,
			player_body
		)


# =========================================================
# SERVER COLLISIONS
# =========================================================

func _check_server_collisions() -> void:

	if not multiplayer.is_server():
		return

	var ids := player_states.keys()

	var victims: Dictionary = {}

	for i in range(ids.size()):

		var id_a = ids[i]

		if not player_states.has(id_a):
			continue

		var state_a: Dictionary = player_states[id_a]

		if not state_a.get(
			"alive",
			true
		):

			continue

		for j in range(
			i + 1,
			ids.size()
		):

			var id_b = ids[j]

			if not player_states.has(id_b):
				continue

			var state_b: Dictionary = player_states[id_b]

			if not state_b.get(
				"alive",
				true
			):

				continue

			_check_player_pair(
				id_a,
				state_a,
				id_b,
				state_b,
				victims
			)

	for victim_id in victims.keys():

		if not player_states.has(
			victim_id
		):

			continue

		var killer_id: int = victims[
			victim_id
		]

		_kill_player(
			victim_id,
			killer_id
		)


# =========================================================
# CHECK TWO PLAYERS
# =========================================================

func _check_player_pair(
	id_a: int,
	state_a: Dictionary,
	id_b: int,
	state_b: Dictionary,
	victims: Dictionary
) -> void:

	var position_a: Vector2 = state_a[
		"position"
	]

	var position_b: Vector2 = state_b[
		"position"
	]

	# -----------------------------------------------------
	# HEAD VS HEAD
	# -----------------------------------------------------

	if position_a.distance_to(
		position_b
	) <= HEAD_TO_HEAD_DISTANCE:

		var length_a := int(
			state_a.get("length", 10)
		)

		var length_b := int(
			state_b.get("length", 10)
		)

		# Bigger snake survives head-to-head.
		if length_a > length_b:

			victims[id_b] = id_a

		elif length_b > length_a:

			victims[id_a] = id_b

		else:

			# Same size = both die
			victims[id_a] = id_b
			victims[id_b] = id_a

		return

	# -----------------------------------------------------
	# HEAD A VS BODY B
	# -----------------------------------------------------

	if _head_hits_body(
		position_a,
		state_b.get("body", [])
	):

		victims[id_a] = id_b

	# -----------------------------------------------------
	# HEAD B VS BODY A
	# -----------------------------------------------------

	if _head_hits_body(
		position_b,
		state_a.get("body", [])
	):

		victims[id_b] = id_a


# =========================================================
# HEAD VS BODY
# =========================================================

func _head_hits_body(
	head_position: Vector2,
	body_points: Array
) -> bool:

	if body_points.is_empty():
		return false

	var start_index := min(
		COLLISION_START_INDEX,
		body_points.size()
	)

	for i in range(
		start_index,
		body_points.size()
	):

		if not body_points[i] is Vector2:
			continue

		var body_position: Vector2 = body_points[i]

		if head_position.distance_to(
			body_position
		) <= HEAD_TO_BODY_DISTANCE:

			return true

	return false


# =========================================================
# KILL PLAYER
# =========================================================

func _kill_player(
	victim_id: int,
	killer_id: int
) -> void:

	if not player_states.has(
		victim_id
	):

		return

	var victim_state: Dictionary = player_states[
		victim_id
	]

	if not victim_state.get(
		"alive",
		true
	):

		return

	var death_position: Vector2 = victim_state[
		"position"
	]

	var reward := 250

	# Mark dead
	victim_state["alive"] = false

	player_states[victim_id] = victim_state

	# Spawn loot
	_spawn_death_loot(
		death_position,
		victim_state
	)

	# Tell everyone
	player_died.rpc(
		victim_id,
		killer_id,
		death_position,
		reward
	)

	# Update local server game
	var game := get_tree().current_scene

	if game and game.has_method(
		"network_player_died"
	):

		game.network_player_died(
			victim_id,
			killer_id,
			death_position,
			reward
		)


# =========================================================
# PLAYER DIED RPC
# =========================================================

@rpc("authority", "call_remote", "reliable")
func player_died(
	peer_id: int,
	killer_id: int,
	death_position: Vector2,
	reward: int
) -> void:

	player_died.emit(
		peer_id,
		killer_id,
		death_position,
		reward
	)

	var game := get_tree().current_scene

	if game and game.has_method(
		"network_player_died"
	):

		game.network_player_died(
			peer_id,
			killer_id,
			death_position,
			reward
		)


# =========================================================
# REQUEST RESPAWN
# =========================================================

func request_respawn() -> void:

	if multiplayer.multiplayer_peer == null:
		return

	if multiplayer.is_server():

		_respawn_player(
			multiplayer.get_unique_id()
		)

	else:

		request_respawn_rpc.rpc_id(
			1
		)


@rpc("any_peer", "reliable")
func request_respawn_rpc() -> void:

	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	_respawn_player(
		sender_id
	)


# =========================================================
# RESPAWN
# =========================================================

func _respawn_player(
	peer_id: int
) -> void:

	if not player_states.has(
		peer_id
	):

		return

	var spawn := _generate_spawn_position()

	player_spawns[peer_id] = spawn

	var state: Dictionary = player_states[
		peer_id
	]

	state["position"] = spawn
	state["direction"] = Vector2.RIGHT
	state["length"] = 10
	state["alive"] = true
	state["body"] = []

	player_states[peer_id] = state

	player_respawned.rpc(
		peer_id,
		spawn
	)

	var game := get_tree().current_scene

	if game and peer_id == multiplayer.get_unique_id():

		if game.has_method(
			"set_local_spawn"
		):

			game.set_local_spawn(
				spawn
			)


# =========================================================
# RESPAWN RPC
# =========================================================

@rpc("authority", "call_remote", "reliable")
func player_respawned(
	peer_id: int,
	respawn_position: Vector2
) -> void:

	player_respawned.emit(
		peer_id,
		respawn_position
	)

	var game := get_tree().current_scene

	if game and game.has_method(
		"network_player_respawned"
	):

		game.network_player_respawned(
			peer_id,
			respawn_position
		)


# =========================================================
# FOOD INITIALIZATION
# =========================================================

func _create_initial_food() -> void:

	if not is_host:
		return

	foods.clear()

	next_food_id = 1

	for i in range(
		FOOD_COUNT
	):

		_create_food()


# =========================================================
# CREATE FOOD
# =========================================================

func _create_food() -> void:

	var food_id := next_food_id

	next_food_id += 1

	var position := Vector2(
		randf_range(
			100.0,
			MAP_SIZE.x - 100.0
		),
		randf_range(
			100.0,
			MAP_SIZE.y - 100.0
		)
	)

	foods[food_id] = {
		"position": position,
		"value": FOOD_VALUE,
		"coins": FOOD_COIN_VALUE,
		"xp": FOOD_XP_VALUE
	}

	food_spawned.rpc(
		food_id,
		position,
		FOOD_VALUE,
		FOOD_COIN_VALUE,
		FOOD_XP_VALUE
	)


# =========================================================
# MAINTAIN FOOD
# =========================================================

func _maintain_food() -> void:

	if not is_host:
		return

	while foods.size() < FOOD_COUNT:

		_create_food()

		if foods.size() >= FOOD_COUNT:
			break


# =========================================================
# FOOD SPAWNED
# =========================================================

@rpc("authority", "call_remote", "reliable")
func food_spawned(
	food_id: int,
	position: Vector2,
	value: int,
	coins: int,
	xp: int
) -> void:

	var data := {
		"position": position,
		"value": value,
		"coins": coins,
		"xp": xp
	}

	foods[food_id] = data

	var game := get_tree().current_scene

	if game and game.has_method(
		"network_food_spawned"
	):

		game.network_food_spawned(
			food_id,
			position,
			value,
			coins,
			xp
		)


# =========================================================
# FOOD COLLECTION CHECK
# =========================================================

func _check_food_collection_for_player(
	peer_id: int
) -> void:

	if not player_states.has(
		peer_id
	):

		return

	var state: Dictionary = player_states[
		peer_id
	]

	if not state.get(
		"alive",
		true
	):

		return

	var player_position: Vector2 = state[
		"position"
	]

	var collected: Array = []

	for food_id in foods.keys():

		var food_data: Dictionary = foods[
			food_id
		]

		var food_position: Vector2 = food_data[
			"position"
		]

		if player_position.distance_to(
			food_position
		) <= FOOD_COLLECTION_DISTANCE:

			collected.append(
				food_id
			)

	for food_id in collected:

		_collect_food_for_player(
			peer_id,
			food_id
		)


# =========================================================
# COLLECT FOOD
# =========================================================

func _collect_food_for_player(
	peer_id: int,
	food_id: int
) -> void:

	if not foods.has(
		food_id
	):

		return

	if not player_states.has(
		peer_id
	):

		return

	var food_data: Dictionary = foods[
		food_id
	]

	foods.erase(
		food_id
	)

	food_collected.rpc(
		food_id,
		peer_id,
		food_data["value"],
		food_data["coins"],
		food_data["xp"]
	)

	# Create replacement
	_create_food()


# =========================================================
# FOOD COLLECTED RPC
# =========================================================

@rpc("authority", "call_remote", "reliable")
func food_collected(
	food_id: int,
	collector_id: int,
	value: int,
	coins: int,
	xp: int
) -> void:

	foods.erase(
		food_id
	)

	var game := get_tree().current_scene

	if game and game.has_method(
		"network_food_collected"
	):

		game.network_food_collected(
			food_id,
			collector_id,
			value,
			coins,
			xp
		)


# =========================================================
# LOOT FROM DEATH
# =========================================================

func _spawn_death_loot(
	death_position: Vector2,
	victim_state: Dictionary
) -> void:

	var amount := DEATH_LOOT_COUNT

	var victim_length := int(
		victim_state.get(
			"length",
			10
		)
	)

	amount = clamp(
		amount + int(victim_length / 20),
		DEATH_LOOT_COUNT,
		25
	)

	for i in range(amount):

		var angle := (
			float(i) /
			float(max(1, amount))
		) * TAU

		var distance := randf_range(
			20.0,
			110.0
		)

		var position := (
			death_position +
			Vector2.from_angle(angle) *
			distance
		)

		position.x = clamp(
			position.x,
			50.0,
			MAP_SIZE.x - 50.0
		)

		position.y = clamp(
			position.y,
			50.0,
			MAP_SIZE.y - 50.0
		)

		_create_loot(
			position
		)


# =========================================================
# CREATE LOOT
# =========================================================

func _create_loot(
	position: Vector2
) -> void:

	var loot_id := next_loot_id

	next_loot_id += 1

	loot[loot_id] = {
		"position": position,
		"value": DEATH_LOOT_VALUE,
		"coins": DEATH_LOOT_COIN_VALUE,
		"xp": DEATH_LOOT_XP_VALUE
	}

	loot_spawned.rpc(
		loot_id,
		position,
		DEATH_LOOT_VALUE,
		DEATH_LOOT_COIN_VALUE,
		DEATH_LOOT_XP_VALUE
	)


# =========================================================
# LOOT SPAWNED
# =========================================================

@rpc("authority", "call_remote", "reliable")
func loot_spawned(
	loot_id: int,
	position: Vector2,
	value: int,
	coins: int,
	xp: int
) -> void:

	loot[loot_id] = {
		"position": position,
		"value": value,
		"coins": coins,
		"xp": xp
	}

	var game := get_tree().current_scene

	if game and game.has_method(
		"network_loot_spawned"
	):

		game.network_loot_spawned(
			loot_id,
			position,
			value,
			coins,
			xp
		)


# =========================================================
# LOOT CLEANUP
# =========================================================

func _cleanup_loot() -> void:

	if not is_host:
		return

	if loot.size() <= 150:
		return

	var remove_count := loot.size() - 150

	for loot_id in loot.keys():

		loot.erase(
			loot_id
		)

		loot_removed.rpc(
			loot_id
		)

		remove_count -= 1

		if remove_count <= 0:
			break


# =========================================================
# LOOT REMOVED
# =========================================================

@rpc("authority", "call_remote", "reliable")
func loot_removed(
	loot_id: int
) -> void:

	loot.erase(
		loot_id
	)

	var game := get_tree().current_scene

	if game and game.has_method(
		"network_loot_removed"
	):

		game.network_loot_removed(
			loot_id
		)


# =========================================================
# LOOT COLLECTION
# =========================================================

func _check_loot_collection_for_player(
	peer_id: int
) -> void:

	if not player_states.has(
		peer_id
	):

		return

	var state: Dictionary = player_states[
		peer_id
	]

	if not state.get(
		"alive",
		true
	):

		return

	var player_position: Vector2 = state[
		"position"
	]

	var collected: Array = []

	for loot_id in loot.keys():

		var loot_data: Dictionary = loot[
			loot_id
		]

		var loot_position: Vector2 = loot_data[
			"position"
		]

		if player_position.distance_to(
			loot_position
		) <= LOOT_COLLECTION_DISTANCE:

			collected.append(
				loot_id
			)

	for loot_id in collected:

		_collect_loot_for_player(
			peer_id,
			loot_id
		)


# =========================================================
# COLLECT LOOT
# =========================================================

func _collect_loot_for_player(
	peer_id: int,
	loot_id: int
) -> void:

	if not loot.has(
		loot_id
	):

		return

	var loot_data: Dictionary = loot[
		loot_id
	]

	loot.erase(
		loot_id
	)

	loot_collected.rpc(
		loot_id,
		peer_id,
		loot_data["value"],
		loot_data["coins"],
		loot_data["xp"]
	)


# =========================================================
# LOOT COLLECTED
# =========================================================

@rpc("authority", "call_remote", "reliable")
func loot_collected(
	loot_id: int,
	collector_id: int,
	value: int,
	coins: int,
	xp: int
) -> void:

	loot.erase(
		loot_id
	)

	var game := get_tree().current_scene

	if game and game.has_method(
		"network_loot_collected"
	):

		game.network_loot_collected(
			loot_id,
			collector_id,
			value,
			coins,
			xp
		)


# =========================================================
# REQUEST FOOD COLLECTION
# =========================================================

func request_collect_food(
	food_id: int
) -> void:

	if multiplayer.is_server():

		var id := multiplayer.get_unique_id()

		_collect_food_for_player(
			id,
			food_id
		)

	else:

		request_collect_food_rpc.rpc_id(
			1,
			food_id
		)


@rpc("any_peer", "reliable")
func request_collect_food_rpc(
	food_id: int
) -> void:

	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	_collect_food_for_player(
		sender_id,
		food_id
	)


# =========================================================
# AUTO COLLECTION AFTER STATE
# =========================================================

func _check_collections() -> void:

	if not is_host:
		return

	for peer_id in player_states.keys():

		_check_food_collection_for_player(
			peer_id
		)

		_check_loot_collection_for_player(
			peer_id
		)
