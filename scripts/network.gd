extends Node

# ============================================================
# Snake Arab Online
# Multiplayer Network System
# Step 6.6.9
# نظام الموت والقتل والجوائز Multiplayer
# ============================================================

signal connected_to_server
signal connection_failed

# إشارات قديمة للتوافق مع الملفات السابقة
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)

# إشارات جديدة
signal player_joined_signal(peer_id: int, player_name: String)
signal player_left_signal(peer_id: int)
signal players_synced_signal(players: Dictionary)

signal player_died_signal(
	victim_id: int,
	killer_id: int,
	death_position: Vector2,
	reward: Dictionary
)

signal player_respawned_signal(
	peer_id: int,
	spawn_position: Vector2
)

signal food_spawned_signal(
	food_id: int,
	food_position: Vector2,
	value: int
)

signal food_collected_signal(
	food_id: int,
	collector_id: int
)

signal loot_spawned_signal(
	loot_id: int,
	loot_position: Vector2,
	value: int,
	xp: int
)

signal loot_collected_signal(
	loot_id: int,
	collector_id: int
)


# ============================================================
# Network
# ============================================================

const PORT := 7777
const MAX_PLAYERS := 20

var peer: ENetMultiplayerPeer
var is_host := false


# ============================================================
# Game settings
# ============================================================

const MAP_SIZE := Vector2(4000.0, 4000.0)

const SPAWN_MARGIN := 350.0
const MIN_SPAWN_DISTANCE := 500.0

const INITIAL_LENGTH := 10
const MIN_LENGTH := 5

const PLAYER_STATE_INTERVAL := 0.05

const COLLISION_DISTANCE := 34.0
const HEAD_TO_HEAD_DISTANCE := 46.0

const PROTECTION_TIME := 3.0

# ============================================================
# Kill rewards
# ============================================================

const KILL_COIN_REWARD := 100
const KILL_XP_REWARD := 50

const LOOT_PER_SEGMENT := 1
const LOOT_COIN_VALUE := 10
const LOOT_XP_VALUE := 5

const MAX_DEATH_LOOT := 35


# ============================================================
# Player data
# ============================================================

var players: Dictionary = {}

# مثال:
# players[peer_id] = {
#     "name": "بلال",
#     "position": Vector2,
#     "direction": Vector2,
#     "length": 10,
#     "alive": true,
#     "kills": 0,
#     "deaths": 0,
#     "protected_until": 0.0
# }


var player_states: Dictionary = {}

# لمنع تكرار احتساب نفس القتل
var processed_deaths: Dictionary = {}

# ============================================================
# Food
# ============================================================

const FOOD_COUNT := 180
const FOOD_VALUE := 10
const FOOD_COIN_VALUE := 5
const FOOD_XP_VALUE := 2

var foods: Dictionary = {}
var next_food_id := 1


# ============================================================
# Loot
# ============================================================

var loot: Dictionary = {}
var next_loot_id := 1


# ============================================================
# Timers
# ============================================================

var collision_timer := 0.0
var collection_timer := 0.0
var state_cleanup_timer := 0.0


# ============================================================
# Ready
# ============================================================

func _ready() -> void:

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

	set_process(true)


# ============================================================
# Process
# ============================================================

func _process(delta: float) -> void:

	if not is_host:
		return

	if multiplayer.multiplayer_peer == null:
		return

	collision_timer += delta
	collection_timer += delta
	state_cleanup_timer += delta

	if collision_timer >= 0.05:
		collision_timer = 0.0
		_check_server_collisions()

	if collection_timer >= 0.05:
		collection_timer = 0.0
		_check_food_collection()
		_check_loot_collection()

	if state_cleanup_timer >= 1.0:
		state_cleanup_timer = 0.0
		_cleanup_old_states()


# ============================================================
# Host game
# ============================================================

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

	var local_id := multiplayer.get_unique_id()

	_create_server_player(
		local_id,
		Global.player_name if Global.player_name != "" else "لاعب"
	)

	_create_initial_food()

	return true


# ============================================================
# Join game
# ============================================================

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
			"Failed to create client: %s" % error
		)

		return false

	multiplayer.multiplayer_peer = peer

	is_host = false

	return true


# ============================================================
# Close
# ============================================================

func close_connection() -> void:

	if multiplayer.multiplayer_peer != null:

		multiplayer.multiplayer_peer.close()

	multiplayer.multiplayer_peer = null

	peer = null

	is_host = false

	players.clear()
	player_states.clear()
	processed_deaths.clear()

	foods.clear()
	loot.clear()


# ============================================================
# Player count
# ============================================================

func get_player_count() -> int:

	if multiplayer.multiplayer_peer == null:
		return 0

	return multiplayer.get_peers().size() + 1


# ============================================================
# Connected
# ============================================================

func _on_connected_to_server() -> void:

	connected_to_server.emit()

	var player_name := Global.player_name

	if player_name.is_empty():
		player_name = "لاعب"

	register_player.rpc_id(
		1,
		player_name
	)


# ============================================================
# Connection failed
# ============================================================

func _on_connection_failed() -> void:

	connection_failed.emit()


# ============================================================
# Peer connected
# ============================================================

func _on_peer_connected(peer_id: int) -> void:

	player_connected.emit(peer_id)

	if not is_host:
		return

	# السيرفر ينتظر register_player من العميل
	# حتى يحصل على الاسم الصحيح.


# ============================================================
# Peer disconnected
# ============================================================

func _on_peer_disconnected(peer_id: int) -> void:

	player_disconnected.emit(peer_id)

	if not is_host:
		return

	players.erase(peer_id)
	player_states.erase(peer_id)

	player_left_rpc.rpc(
		peer_id
	)

	_sync_players_to_all()


# ============================================================
# Register player
# ============================================================

@rpc("any_peer", "reliable")
func register_player(player_name: String) -> void:

	if not is_host:
		return

	var sender_id := multiplayer.get_remote_sender_id()

	if sender_id <= 0:
		return

	var clean_name := player_name.strip_edges()

	if clean_name.is_empty():
		clean_name = "لاعب"

	if clean_name.length() > 18:
		clean_name = clean_name.substr(0, 18)

	if players.has(sender_id):

		players[sender_id]["name"] = clean_name

	else:

		_create_server_player(
			sender_id,
			clean_name
		)

	_sync_players_to_all()


# ============================================================
# Create server player
# ============================================================

func _create_server_player(
	peer_id: int,
	player_name: String
) -> void:

	var spawn_position := _find_safe_spawn_position()

	var data := {
		"name": player_name,
		"position": spawn_position,
		"direction": Vector2.RIGHT,
		"length": INITIAL_LENGTH,
		"alive": true,
		"kills": 0,
		"deaths": 0,
		"protected_until": Time.get_ticks_msec() / 1000.0 + PROTECTION_TIME
	}

	players[peer_id] = data
	player_states[peer_id] = data.duplicate(true)


# ============================================================
# Find safe spawn
# ============================================================

func _find_safe_spawn_position() -> Vector2:

	for attempt in range(60):

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

		var safe := true

		for id in players.keys():

			var data: Dictionary = players[id]

			if not bool(data.get("alive", false)):
				continue

			var existing_position: Vector2 = data.get(
				"position",
				Vector2.ZERO
			)

			if candidate.distance_to(existing_position) < MIN_SPAWN_DISTANCE:

				safe = false
				break

		if safe:
			return candidate

	return MAP_SIZE / 2.0


# ============================================================
# Sync players
# ============================================================

func _sync_players_to_all() -> void:

	var snapshot: Dictionary = {}

	for id in players.keys():

		var data: Dictionary = players[id]

		snapshot[id] = {
			"name": str(data.get("name", "لاعب")),
			"position": data.get("position", Vector2.ZERO),
			"direction": data.get("direction", Vector2.RIGHT),
			"length": int(data.get("length", INITIAL_LENGTH)),
			"alive": bool(data.get("alive", true)),
			"kills": int(data.get("kills", 0)),
			"deaths": int(data.get("deaths", 0))
		}

	players_synced_rpc.rpc(snapshot)


@rpc("authority", "reliable")
func players_synced_rpc(snapshot: Dictionary) -> void:

	players_synced_signal.emit(snapshot)


# ============================================================
# Player joined notification
# ============================================================

@rpc("authority", "reliable")
func player_joined_rpc(
	peer_id: int,
	player_name: String
) -> void:

	player_joined_signal.emit(
		peer_id,
		player_name
	)


# ============================================================
# Player left notification
# ============================================================

@rpc("authority", "reliable")
func player_left_rpc(peer_id: int) -> void:

	player_left_signal.emit(peer_id)


# ============================================================
# Player state
# ============================================================

func broadcast_player_state(
	position: Vector2,
	direction: Vector2,
	length: int,
	alive: bool
) -> void:

	if multiplayer.multiplayer_peer == null:
		return

	var local_id := multiplayer.get_unique_id()

	if is_host:

		_update_server_player_state(
			local_id,
			position,
			direction,
			length,
			alive
		)

	else:

		submit_player_state.rpc_id(
			1,
			position,
			direction,
			length,
			alive
		)


# ============================================================
# Client submits state
# ============================================================

@rpc("any_peer", "unreliable")
func submit_player_state(
	position: Vector2,
	direction: Vector2,
	length: int,
	alive: bool
) -> void:

	if not is_host:
		return

	var sender_id := multiplayer.get_remote_sender_id()

	_update_server_player_state(
		sender_id,
		position,
		direction,
		length,
		alive
	)


# ============================================================
# Update server state
# ============================================================

func _update_server_player_state(
	peer_id: int,
	new_position: Vector2,
	new_direction: Vector2,
	new_length: int,
	alive: bool
) -> void:

	if not players.has(peer_id):
		return

	var data: Dictionary = players[peer_id]

	data["position"] = new_position
	data["direction"] = (
		new_direction.normalized()
		if new_direction.length() > 0.01
		else Vector2.RIGHT
	)

	data["length"] = clamp(
		new_length,
		MIN_LENGTH,
		5000
	)

	data["alive"] = alive

	players[peer_id] = data
	player_states[peer_id] = data.duplicate(true)

	broadcast_state_rpc.rpc(
		peer_id,
		new_position,
		data["direction"],
		int(data["length"]),
		alive
	)


# ============================================================
# Broadcast state
# ============================================================

@rpc("authority", "unreliable")
func broadcast_state_rpc(
	peer_id: int,
	new_position: Vector2,
	new_direction: Vector2,
	new_length: int,
	alive: bool
) -> void:

	var game := get_tree().get_first_node_in_group("game")

	if game != null and game.has_method("update_remote_player"):

		game.update_remote_player(
			peer_id,
			new_position,
			new_direction,
			new_length,
			alive
		)


# ============================================================
# Server collision system
# ============================================================

func _check_server_collisions() -> void:

	if players.size() < 1:
		return

	var ids := players.keys()

	for i in range(ids.size()):

		var first_id: int = ids[i]

		if not players.has(first_id):
			continue

		var first_data: Dictionary = players[first_id]

		if not bool(first_data.get("alive", false)):
			continue

		for j in range(i + 1, ids.size()):

			var second_id: int = ids[j]

			if not players.has(second_id):
				continue

			var second_data: Dictionary = players[second_id]

			if not bool(second_data.get("alive", false)):
				continue

			_check_snake_pair(
				first_id,
				first_data,
				second_id,
				second_data
			)


# ============================================================
# Pair collision
# ============================================================

func _check_snake_pair(
	first_id: int,
	first_data: Dictionary,
	second_id: int,
	second_data: Dictionary
) -> void:

	var first_position: Vector2 = first_data.get(
		"position",
		Vector2.ZERO
	)

	var second_position: Vector2 = second_data.get(
		"position",
		Vector2.ZERO
	)

	# حماية Spawn
	if _is_player_protected(first_data):
		return

	if _is_player_protected(second_data):
		return

	var distance := first_position.distance_to(
		second_position
	)

	# Head vs Head
	if distance <= HEAD_TO_HEAD_DISTANCE:

		var first_length := int(
			first_data.get("length", INITIAL_LENGTH)
		)

		var second_length := int(
			second_data.get("length", INITIAL_LENGTH)
		)

		if first_length > second_length:

			_kill_player(
				second_id,
				first_id,
				second_position
			)

		elif second_length > first_length:

			_kill_player(
				first_id,
				second_id,
				first_position
			)

		else:

			# نفس الطول = كلاهما يموت
			_kill_player(
				first_id,
				-1,
				first_position
			)

			_kill_player(
				second_id,
				-1,
				second_position
			)

		return


# ============================================================
# Full body collision
# ============================================================

func check_body_collision(
	victim_id: int,
	body_positions: Array[Vector2]
) -> int:

	if not is_host:
		return -1

	if not players.has(victim_id):
		return -1

	var victim_data: Dictionary = players[victim_id]

	if not bool(victim_data.get("alive", false)):
		return -1

	if _is_player_protected(victim_data):
		return -1

	var head_position: Vector2 = victim_data.get(
		"position",
		Vector2.ZERO
	)

	for other_id in players.keys():

		if other_id == victim_id:
			continue

		var other_data: Dictionary = players[other_id]

		if not bool(other_data.get("alive", false)):
			continue

		if _is_player_protected(other_data):
			continue

		for body_position in body_positions:

			if head_position.distance_to(body_position) <= COLLISION_DISTANCE:

				var killer_length := int(
					other_data.get(
						"length",
						INITIAL_LENGTH
					)
				)

				var victim_length := int(
					victim_data.get(
						"length",
						INITIAL_LENGTH
					)
				)

				if killer_length >= victim_length:

					_kill_player(
						victim_id,
						other_id,
						head_position
					)

					return other_id

	return -1


# ============================================================
# Protected check
# ============================================================

func _is_player_protected(data: Dictionary) -> bool:

	var protected_until := float(
		data.get("protected_until", 0.0)
	)

	var now := Time.get_ticks_msec() / 1000.0

	return now < protected_until


# ============================================================
# Kill player
# ============================================================

func _kill_player(
	victim_id: int,
	killer_id: int,
	death_position: Vector2
) -> void:

	if not is_host:
		return

	if not players.has(victim_id):
		return

	var victim: Dictionary = players[victim_id]

	if not bool(victim.get("alive", false)):
		return

	# منع تكرار القتل
	var death_key := "%s_%s" % [
		victim_id,
		Time.get_ticks_msec()
	]

	if processed_deaths.has(victim_id):

		var last_time := int(
			processed_deaths[victim_id]
		)

		if Time.get_ticks_msec() - last_time < 500:
			return

	processed_deaths[victim_id] = Time.get_ticks_msec()

	# تغيير حالة الضحية
	victim["alive"] = false

	var old_length := int(
		victim.get(
			"length",
			INITIAL_LENGTH
		)
	)

	victim["deaths"] = int(
		victim.get("deaths", 0)
	) + 1

	victim["length"] = MIN_LENGTH

	players[victim_id] = victim

	# المكافآت
	var reward := {
		"coins": 0,
		"xp": 0,
		"kills": 0,
		"victim_length": old_length
	}

	# إذا كان هناك قاتل
	if killer_id > 0 and killer_id != victim_id:

		if players.has(killer_id):

			var killer: Dictionary = players[killer_id]

			killer["kills"] = int(
				killer.get("kills", 0)
			) + 1

			players[killer_id] = killer

			reward["coins"] = KILL_COIN_REWARD
			reward["xp"] = KILL_XP_REWARD
			reward["kills"] = 1

			_award_killer(
				killer_id,
				KILL_COIN_REWARD,
				KILL_XP_REWARD
			)

	# إنشاء Loot
	_spawn_death_loot(
		death_position,
		old_length
	)

	# إرسال الموت للجميع
	player_died_rpc.rpc(
		victim_id,
		killer_id,
		death_position,
		reward
	)

	# إرسال حالة اللاعبين
	_sync_players_to_all()


# ============================================================
# Award killer
# ============================================================

func _award_killer(
	killer_id: int,
	coins: int,
	xp: int
) -> void:

	if killer_id == multiplayer.get_unique_id():

		Global.add_coins(coins)
		Global.add_experience(xp)

	_award_killer_rpc.rpc(
		killer_id,
		coins,
		xp
	)


@rpc("authority", "reliable")
func _award_killer_rpc(
	killer_id: int,
	coins: int,
	xp: int
) -> void:

	if killer_id != multiplayer.get_unique_id():
		return

	Global.add_coins(coins)
	Global.add_experience(xp)


# ============================================================
# Player died RPC
# ============================================================

@rpc("authority", "reliable")
func player_died_rpc(
	victim_id: int,
	killer_id: int,
	death_position: Vector2,
	reward: Dictionary
) -> void:

	player_died_signal.emit(
		victim_id,
		killer_id,
		death_position,
		reward
	)


# ============================================================
# Respawn request
# ============================================================

func request_respawn() -> void:

	if multiplayer.multiplayer_peer == null:
		return

	var local_id := multiplayer.get_unique_id()

	if is_host:

		_respawn_player(local_id)

	else:

		request_respawn_rpc.rpc_id(
			1
		)


@rpc("any_peer", "reliable")
func request_respawn_rpc() -> void:

	if not is_host:
		return

	var sender_id := multiplayer.get_remote_sender_id()

	_respawn_player(sender_id)


# ============================================================
# Respawn
# ============================================================

func _respawn_player(peer_id: int) -> void:

	if not players.has(peer_id):
		return

	var data: Dictionary = players[peer_id]

	var spawn_position := _find_safe_spawn_position()

	data["position"] = spawn_position
	data["direction"] = Vector2.RIGHT
	data["length"] = INITIAL_LENGTH
	data["alive"] = true

	data["protected_until"] = (
		Time.get_ticks_msec() / 1000.0
		+ PROTECTION_TIME
	)

	players[peer_id] = data

	player_respawned_rpc.rpc(
		peer_id,
		spawn_position
	)

	_sync_players_to_all()


# ============================================================
# Respawn RPC
# ============================================================

@rpc("authority", "reliable")
func player_respawned_rpc(
	peer_id: int,
	spawn_position: Vector2
) -> void:

	player_respawned_signal.emit(
		peer_id,
		spawn_position
	)


# ============================================================
# Food creation
# ============================================================

func _create_initial_food() -> void:

	foods.clear()

	next_food_id = 1

	for i in range(FOOD_COUNT):

		var food_position := Vector2(
			randf_range(100.0, MAP_SIZE.x - 100.0),
			randf_range(100.0, MAP_SIZE.y - 100.0)
		)

		var id := next_food_id
		next_food_id += 1

		foods[id] = {
			"position": food_position,
			"value": FOOD_VALUE
		}

	# إرسال القائمة الأولية
	sync_food_rpc.rpc(foods)


# ============================================================
# Sync food
# ============================================================

@rpc("authority", "reliable")
func sync_food_rpc(
	food_data: Dictionary
) -> void:

	foods = food_data

	var game := get_tree().get_first_node_in_group("game")

	if game != null and game.has_method("sync_network_food"):

		game.sync_network_food(
			food_data
		)


# ============================================================
# Food collection
# ============================================================

func _check_food_collection() -> void:

	if not is_host:
		return

	for player_id in players.keys():

		var data: Dictionary = players[player_id]

		if not bool(data.get("alive", false)):
			continue

		var player_position: Vector2 = data.get(
			"position",
			Vector2.ZERO
		)

		var collected_id := -1

		for food_id in foods.keys():

			var food: Dictionary = foods[food_id]

			var food_position: Vector2 = food.get(
				"position",
				Vector2.ZERO
			)

			if player_position.distance_to(food_position) < 45.0:

				collected_id = int(food_id)
				break

		if collected_id != -1:

			_collect_food(
				collected_id,
				player_id
			)


# ============================================================
# Collect food
# ============================================================

func _collect_food(
	food_id: int,
	collector_id: int
) -> void:

	if not foods.has(food_id):
		return

	if not players.has(collector_id):
		return

	foods.erase(food_id)

	var player: Dictionary = players[collector_id]

	var old_length := int(
		player.get(
			"length",
			INITIAL_LENGTH
		)
	)

	player["length"] = min(
		old_length + 1,
		5000
	)

	players[collector_id] = player

	# إعطاء مكافآت محلية
	if collector_id == multiplayer.get_unique_id():

		Global.add_coins(
			FOOD_COIN_VALUE
		)

		Global.add_experience(
			FOOD_XP_VALUE
		)

	food_collected_rpc.rpc(
		food_id,
		collector_id
	)

	_spawn_food()


# ============================================================
# Spawn replacement food
# ============================================================

func _spawn_food() -> void:

	var food_position := Vector2(
		randf_range(100.0, MAP_SIZE.x - 100.0),
		randf_range(100.0, MAP_SIZE.y - 100.0)
	)

	var id := next_food_id
	next_food_id += 1

	foods[id] = {
		"position": food_position,
		"value": FOOD_VALUE
	}

	food_spawned_rpc.rpc(
		id,
		food_position,
		FOOD_VALUE
	)


# ============================================================
# Food spawned
# ============================================================

@rpc("authority", "reliable")
func food_spawned_rpc(
	food_id: int,
	food_position: Vector2,
	value: int
) -> void:

	foods[food_id] = {
		"position": food_position,
		"value": value
	}

	food_spawned_signal.emit(
		food_id,
		food_position,
		value
	)

	var game := get_tree().get_first_node_in_group("game")

	if game != null and game.has_method("network_food_spawned"):

		game.network_food_spawned(
			food_id,
			food_position,
			value
		)


# ============================================================
# Food collected RPC
# ============================================================

@rpc("authority", "reliable")
func food_collected_rpc(
	food_id: int,
	collector_id: int
) -> void:

	food_collected_signal.emit(
		food_id,
		collector_id
	)

	var game := get_tree().get_first_node_in_group("game")

	if game != null and game.has_method("network_food_collected"):

		game.network_food_collected(
			food_id,
			collector_id
		)


# ============================================================
# Death loot
# ============================================================

func _spawn_death_loot(
	death_position: Vector2,
	old_length: int
) -> void:

	var amount := clamp(
		int(old_length * 0.55),
		3,
		MAX_DEATH_LOOT
	)

	for i in range(amount):

		var angle := randf_range(
			0.0,
			TAU
		)

		var distance := randf_range(
			25.0,
			160.0
		)

		var loot_position := death_position + Vector2(
			cos(angle),
			sin(angle)
		) * distance

		loot_position.x = clamp(
			loot_position.x,
			80.0,
			MAP_SIZE.x - 80.0
		)

		loot_position.y = clamp(
			loot_position.y,
			80.0,
			MAP_SIZE.y - 80.0
		)

		var loot_id := next_loot_id
		next_loot_id += 1

		loot[loot_id] = {
			"position": loot_position,
			"value": LOOT_COIN_VALUE,
			"xp": LOOT_XP_VALUE
		}

		loot_spawned_rpc.rpc(
			loot_id,
			loot_position,
			LOOT_COIN_VALUE,
			LOOT_XP_VALUE
		)


# ============================================================
# Loot collection
# ============================================================

func _check_loot_collection() -> void:

	if not is_host:
		return

	for player_id in players.keys():

		var player: Dictionary = players[player_id]

		if not bool(player.get("alive", false)):
			continue

		var player_position: Vector2 = player.get(
			"position",
			Vector2.ZERO
		)

		var collected_id := -1

		for loot_id in loot.keys():

			var item: Dictionary = loot[loot_id]

			var item_position: Vector2 = item.get(
				"position",
				Vector2.ZERO
			)

			if player_position.distance_to(item_position) < 50.0:

				collected_id = int(loot_id)
				break

		if collected_id != -1:

			_collect_loot(
				collected_id,
				player_id
			)


# ============================================================
# Collect loot
# ============================================================

func _collect_loot(
	loot_id: int,
	collector_id: int
) -> void:

	if not loot.has(loot_id):
		return

	if not players.has(collector_id):
		return

	var item: Dictionary = loot[loot_id]

	var coin_value := int(
		item.get(
			"value",
			LOOT_COIN_VALUE
		)
	)

	var xp_value := int(
		item.get(
			"xp",
			LOOT_XP_VALUE
		)
	)

	loot.erase(loot_id)

	var player: Dictionary = players[collector_id]

	player["length"] = min(
		int(player.get("length", INITIAL_LENGTH)) + LOOT_PER_SEGMENT,
		5000
	)

	players[collector_id] = player

	if collector_id == multiplayer.get_unique_id():

		Global.add_coins(
			coin_value
		)

		Global.add_experience(
			xp_value
		)

	loot_collected_rpc.rpc(
		loot_id,
		collector_id
	)


# ============================================================
# Loot spawned
# ============================================================

@rpc("authority", "reliable")
func loot_spawned_rpc(
	loot_id: int,
	loot_position: Vector2,
	value: int,
	xp: int
) -> void:

	loot[loot_id] = {
		"position": loot_position,
		"value": value,
		"xp": xp
	}

	loot_spawned_signal.emit(
		loot_id,
		loot_position,
		value,
		xp
	)

	var game := get_tree().get_first_node_in_group("game")

	if game != null and game.has_method("network_loot_spawned"):

		game.network_loot_spawned(
			loot_id,
			loot_position,
			value,
			xp
		)


# ============================================================
# Loot collected
# ============================================================

@rpc("authority", "reliable")
func loot_collected_rpc(
	loot_id: int,
	collector_id: int
) -> void:

	loot_collected_signal.emit(
		loot_id,
		collector_id
	)

	var game := get_tree().get_first_node_in_group("game")

	if game != null and game.has_method("network_loot_collected"):

		game.network_loot_collected(
			loot_id,
			collector_id
		)


# ============================================================
# Cleanup
# ============================================================

func _cleanup_old_states() -> void:

	var now := Time.get_ticks_msec()

	for victim_id in processed_deaths.keys():

		var timestamp := int(
			processed_deaths[victim_id]
		)

		if now - timestamp > 5000:

			processed_deaths.erase(
				victim_id
			)
