extends Node

# =========================================================
# SNAKE ARAB ONLINE
# NETWORK
# STEP 6.6.7
# FOOD + LOOT SYNCHRONIZATION
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

const FOOD_COUNT := 180
const LOOT_PER_LENGTH := 2
const MAX_LOOT_PER_DEATH := 60

var peer: ENetMultiplayerPeer
var is_server := false

var connected_players: Dictionary = {}
var player_spawns: Dictionary = {}
var player_states: Dictionary = {}

# =========================================================
# SERVER AUTHORITATIVE FOOD
# =========================================================

var foods: Dictionary = {}

var next_food_id: int = 1

const FOOD_VALUE := 10
const FOOD_COIN_VALUE := 1
const FOOD_XP_VALUE := 5

# =========================================================
# SERVER LOOT
# =========================================================

var loot: Dictionary = {}

var next_loot_id: int = 100000

const LOOT_VALUE := 25
const LOOT_COIN_VALUE := 2
const LOOT_XP_VALUE := 10

var last_collision_check := 0.0
var last_state_broadcast := 0.0


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
# CREATE SERVER
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

	_create_initial_food()

	print("Server started on port ", PORT)

	return true


# =========================================================
# CONNECT
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

	foods.clear()
	loot.clear()

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

	# إرسال قائمة اللاعبين
	sync_player_list.rpc_id(
		peer_id,
		connected_players
	)

	# إرسال Spawn
	assign_spawn.rpc_id(
		peer_id,
		spawn
	)

	# إرسال الطعام الحالي
	sync_food.rpc_id(
		peer_id,
		foods
	)

	# إرسال الـLoot الحالي
	sync_loot.rpc_id(
		peer_id,
		loot
	)

	var data: Dictionary = connected_players[
		peer_id
	]

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
# PLAYER JOIN
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
# PLAYER LEFT
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

	if not is_server:
		return

	var sender_id := (
		multiplayer.get_remote_sender_id()
	)

	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	player_name = player_name.strip_edges()

	if player_name.is_empty():
		player_name = "لاعب"

	player_name = player_name.left(18)

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

		connected_players[
			sender_id
		]["name"] = player_name

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

	connected_players = players.duplicate(
		true
	)

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
# PLAYER JOIN BROADCAST
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

	var sender_id := (
		multiplayer.get_remote_sender_id()
	)

	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	player_length = clamp(
		player_length,
		5,
		10000
	)

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

		connected_players[
			sender_id
		]["alive"] = player_alive

	_check_server_collisions()

	_check_food_collection_for_player(
		sender_id
	)

	_check_loot_collection_for_player(
		sender_id
	)

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

		_check_food_collection_for_player(
			local_id
		)

		_check_loot_collection_for_player(
			local_id
		)

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
# SERVER COLLISIONS
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
# CHECK SNAKE PAIR
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

			_kill_player(
				first_id,
				second_id
			)

			_kill_player(
				second_id,
				first_id
			)

		return

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

	var death_position: Vector2 = (
		player_states[victim_id]["position"]
	)

	var victim_length := int(
		player_states[victim_id]["length"]
	)

	player_states[victim_id]["alive"] = false

	if connected_players.has(victim_id):

		connected_players[
			victim_id
		]["alive"] = false

	# إنشاء Loot
	_spawn_death_loot(
		death_position,
		victim_length
	)

	var reward := max(
		10,
		victim_length * 2
	)

	player_died.rpc(
		victim_id,
		killer_id,
		death_position,
		reward
	)

	update_remote_player.rpc(
		victim_id,
		death_position,
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
# PLAYER DIED
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
# INITIAL FOOD
# =========================================================

func _create_initial_food() -> void:

	if not is_server:
		return

	foods.clear()

	for i in range(FOOD_COUNT):

		var position := _generate_food_position()

		_add_food(
			position
		)


# =========================================================
# GENERATE FOOD POSITION
# =========================================================

func _generate_food_position() -> Vector2:

	return Vector2(
		randf_range(
			100.0,
			MAP_SIZE.x - 100.0
		),
		randf_range(
			100.0,
			MAP_SIZE.y - 100.0
		)
	)


# =========================================================
# ADD FOOD
# =========================================================

func _add_food(
	position: Vector2
) -> int:

	var food_id := next_food_id

	next_food_id += 1

	foods[food_id] = {
		"position": position,
		"value": FOOD_VALUE,
		"coins": FOOD_COIN_VALUE,
		"xp": FOOD_XP_VALUE
	}

	return food_id


# =========================================================
# SYNC FOOD
# =========================================================

@rpc("authority", "call_remote", "reliable")
func sync_food(
	server_foods: Dictionary
) -> void:

	foods = server_foods.duplicate(
		true
	)

	var scene := get_tree().current_scene

	if scene and scene.has_method(
		"sync_network_food"
	):

		scene.sync_network_food(
			foods
		)


# =========================================================
# FOOD COLLECT REQUEST
# =========================================================

@rpc("any_peer", "reliable")
func request_collect_food(
	food_id: int
) -> void:

	if not is_server:
		return

	var sender_id := (
		multiplayer.get_remote_sender_id()
	)

	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	_collect_food_for_player(
		sender_id,
		food_id
	)


# =========================================================
# SERVER FOOD COLLECTION
# =========================================================

func _check_food_collection_for_player(
	peer_id: int
) -> void:

	if not is_server:
		return

	if not player_states.has(peer_id):
		return

	if not player_states[peer_id].get(
		"alive",
		true
	):
		return

	var player_position: Vector2 = (
		player_states[peer_id]["position"]
	)

	var collected_ids: Array[int] = []

	for key in foods.keys():

		var food_id := int(key)

		var food_data: Dictionary = foods[key]

		var food_position: Vector2 = (
			food_data["position"]
		)

		if player_position.distance_to(
			food_position
		) <= 48.0:

			collected_ids.append(
				food_id
			)

			if collected_ids.size() >= 3:
				break

	for food_id in collected_ids:

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

	if not is_server:
		return

	if not foods.has(food_id):
		return

	if not player_states.has(peer_id):
		return

	if not player_states[peer_id].get(
		"alive",
		true
	):
		return

	var food_data: Dictionary = foods[
		food_id
	]

	var player_position: Vector2 = (
		player_states[peer_id]["position"]
	)

	var food_position: Vector2 = (
		food_data["position"]
	)

	if player_position.distance_to(
		food_position
	) > 60.0:
		return

	foods.erase(food_id)

	# زيادة طول اللاعب
	var old_length := int(
		player_states[peer_id]["length"]
	)

	var new_length := old_length + 1

	player_states[peer_id]["length"] = (
		new_length
	)

	# إرسال نتيجة الجمع للجميع
	food_collected.rpc(
		food_id,
		peer_id,
		food_position,
		new_length,
		int(food_data["value"]),
		int(food_data["coins"]),
		int(food_data["xp"])
	)

	# تعويض الطعام المحذوف
	var new_food_position := (
		_generate_food_position()
	)

	var new_food_id := _add_food(
		new_food_position
	)

	food_spawned.rpc(
		new_food_id,
		new_food_position,
		FOOD_VALUE,
		FOOD_COIN_VALUE,
		FOOD_XP_VALUE
	)


# =========================================================
# FOOD COLLECTED RPC
# =========================================================

@rpc("authority", "call_remote", "reliable")
func food_collected(
	food_id: int,
	collector_id: int,
	position: Vector2,
	new_length: int,
	value: int,
	coins: int,
	xp: int
) -> void:

	foods.erase(food_id)

	var scene := get_tree().current_scene

	if scene and scene.has_method(
		"network_food_collected"
	):

		scene.network_food_collected(
			food_id,
			collector_id,
			position,
			new_length,
			value,
			coins,
			xp
		)


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

	foods[food_id] = {
		"position": position,
		"value": value,
		"coins": coins,
		"xp": xp
	}

	var scene := get_tree().current_scene

	if scene and scene.has_method(
		"network_food_spawned"
	):

		scene.network_food_spawned(
			food_id,
			position,
			value,
			coins,
			xp
		)


# =========================================================
# DEATH LOOT
# =========================================================

func _spawn_death_loot(
	death_position: Vector2,
	victim_length: int
) -> void:

	if not is_server:
		return

	var amount := clamp(
		victim_length * LOOT_PER_LENGTH,
		5,
		MAX_LOOT_PER_DEATH
	)

	for i in range(amount):

		var angle := (
			float(i) / float(amount)
		) * TAU

		var distance := randf_range(
			20.0,
			120.0
		)

		var position := death_position + Vector2(
			cos(angle),
			sin(angle)
		) * distance

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

		var loot_id := next_loot_id

		next_loot_id += 1

		loot[loot_id] = {
			"position": position,
			"value": LOOT_VALUE,
			"coins": LOOT_COIN_VALUE,
			"xp": LOOT_XP_VALUE
		}

		loot_spawned.rpc(
			loot_id,
			position,
			LOOT_VALUE,
			LOOT_COIN_VALUE,
			LOOT_XP_VALUE
		)


# =========================================================
# SYNC LOOT
# =========================================================

@rpc("authority", "call_remote", "reliable")
func sync_loot(
	server_loot: Dictionary
) -> void:

	loot = server_loot.duplicate(
		true
	)

	var scene := get_tree().current_scene

	if scene and scene.has_method(
		"sync_network_loot"
	):

		scene.sync_network_loot(
			loot
		)


# =========================================================
# LOOT COLLECTION CHECK
# =========================================================

func _check_loot_collection_for_player(
	peer_id: int
) -> void:

	if not is_server:
		return

	if not player_states.has(peer_id):
		return

	if not player_states[peer_id].get(
		"alive",
		true
	):
		return

	var player_position: Vector2 = (
		player_states[peer_id]["position"]
	)

	var collected_ids: Array[int] = []

	for key in loot.keys():

		var loot_id := int(key)

		var loot_data: Dictionary = loot[
			loot_id
		]

		var loot_position: Vector2 = (
			loot_data["position"]
		)

		if player_position.distance_to(
			loot_position
		) <= 55.0:

			collected_ids.append(
				loot_id
			)

			if collected_ids.size() >= 5:
				break

	for loot_id in collected_ids:

		_collect_loot_for_player(
			peer_id,
			loot_id
		)


# =========================================================
# REQUEST LOOT
# =========================================================

@rpc("any_peer", "reliable")
func request_collect_loot(
	loot_id: int
) -> void:

	if not is_server:
		return

	var sender_id := (
		multiplayer.get_remote_sender_id()
	)

	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	_collect_loot_for_player(
		sender_id,
		loot_id
	)


# =========================================================
# COLLECT LOOT
# =========================================================

func _collect_loot_for_player(
	peer_id: int,
	loot_id: int
) -> void:

	if not is_server:
		return

	if not loot.has(loot_id):
		return

	if not player_states.has(peer_id):
		return

	if not player_states[peer_id].get(
		"alive",
		true
	):
		return

	var loot_data: Dictionary = loot[
		loot_id
	]

	var player_position: Vector2 = (
		player_states[peer_id]["position"]
	)

	var loot_position: Vector2 = (
		loot_data["position"]
	)

	if player_position.distance_to(
		loot_position
	) > 70.0:
		return

	loot.erase(loot_id)

	var old_length := int(
		player_states[peer_id]["length"]
	)

	var new_length := old_length + 2

	player_states[peer_id]["length"] = (
		new_length
	)

	loot_collected.rpc(
		loot_id,
		peer_id,
		loot_position,
		new_length,
		int(loot_data["value"]),
		int(loot_data["coins"]),
		int(loot_data["xp"])
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

	var scene := get_tree().current_scene

	if scene and scene.has_method(
		"network_loot_spawned"
	):

		scene.network_loot_spawned(
			loot_id,
			position,
			value,
			coins,
			xp
		)


# =========================================================
# LOOT COLLECTED
# =========================================================

@rpc("authority", "call_remote", "reliable")
func loot_collected(
	loot_id: int,
	collector_id: int,
	position: Vector2,
	new_length: int,
	value: int,
	coins: int,
	xp: int
) -> void:

	loot.erase(loot_id)

	var scene := get_tree().current_scene

	if scene and scene.has_method(
		"network_loot_collected"
	):

		scene.network_loot_collected(
			loot_id,
			collector_id,
			position,
			new_length,
			value,
			coins,
			xp
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

			connected_players[
				local_id
			]["alive"] = true

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

	var sender_id := (
		multiplayer.get_remote_sender_id()
	)

	var spawn := _generate_spawn_position()

	player_spawns[sender_id] = spawn

	player_states[sender_id] = {
		"position": spawn,
		"direction": Vector2.RIGHT,
		"length": 10,
		"alive": true
	}

	if connected_players.has(sender_id):

		connected_players[
			sender_id
		]["spawn"] = spawn

		connected_players[
			sender_id
		]["alive"] = true

	player_respawned.rpc(
		sender_id,
		spawn
	)


# =========================================================
# PLAYER RESPAWNED
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
# GET SPAWN
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
# GET PLAYER COUNT
# =========================================================

func get_player_count() -> int:

	return connected_players.size()


# =========================================================
# LOCAL NAME
# =========================================================

func _get_local_player_name() -> String:

	if Global:

		if Global.player_name != "":
			return Global.player_name

	return "لاعب"
