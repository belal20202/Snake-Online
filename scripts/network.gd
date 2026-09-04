extends Node

signal connected_to_server
signal connection_failed
signal player_connected(peer_id, player_name)
signal player_disconnected(peer_id)

signal player_joined_signal(peer_id, player_name)
signal player_left_signal(peer_id)
signal players_synced_signal(players)

signal player_died_signal(victim_id, killer_id, death_position, reward)
signal player_respawned_signal(peer_id, spawn_position)

signal food_spawned_signal(food_id, position, value)
signal food_collected_signal(food_id, collector_id, value)

signal loot_spawned_signal(loot_id, position, coins, xp)
signal loot_collected_signal(loot_id, collector_id, coins, xp)

signal leaderboard_updated_signal(leaderboard)

const PORT := 7777
const MAX_PLAYERS := 20

const MAP_SIZE := Vector2(4000, 4000)
const SPAWN_MARGIN := 350.0
const MIN_SPAWN_DISTANCE := 500.0

const INITIAL_LENGTH := 10
const MIN_LENGTH := 5

const STATE_SEND_INTERVAL := 0.05
const COLLISION_CHECK_INTERVAL := 0.05
const FOOD_CHECK_INTERVAL := 0.05

const HEAD_COLLISION_DISTANCE := 32.0
const BODY_COLLISION_DISTANCE := 28.0

const SPAWN_PROTECTION_TIME := 3.0

const KILL_COINS := 100
const KILL_XP := 50

const LOOT_PER_SEGMENT := 1
const LOOT_COIN_VALUE := 10
const LOOT_XP_VALUE := 5
const MAX_DEATH_LOOT := 35

var peer: ENetMultiplayerPeer
var is_host := false
var is_connected := false

var local_player_id := 0
var local_player_name := "لاعب"

var players: Dictionary = {}
var player_states: Dictionary = {}

var foods: Dictionary = {}
var death_loot: Dictionary = {}

var next_food_id := 1
var next_loot_id := 1

var state_timer := 0.0
var collision_timer := 0.0
var food_timer := 0.0

var processed_deaths: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


# =========================================================
# HOST
# =========================================================

func host_game(player_name: String = "لاعب") -> bool:
	close_connection()

	peer = ENetMultiplayerPeer.new()

	var result := peer.create_server(PORT, MAX_PLAYERS)

	if result != OK:
		push_error("فشل إنشاء السيرفر: " + str(result))
		return false

	multiplayer.multiplayer_peer = peer

	is_host = true
	is_connected = true
	local_player_id = multiplayer.get_unique_id()
	local_player_name = player_name

	_register_local_player()

	_create_initial_food()

	print("SERVER STARTED")
	print("Port: ", PORT)

	return true


# =========================================================
# CLIENT
# =========================================================

func join_game(address: String, player_name: String = "لاعب") -> bool:
	close_connection()

	peer = ENetMultiplayerPeer.new()

	var result := peer.create_client(address, PORT)

	if result != OK:
		push_error("فشل الاتصال بالسيرفر: " + str(result))
		connection_failed.emit()
		return false

	multiplayer.multiplayer_peer = peer

	is_host = false
	is_connected = true
	local_player_name = player_name

	return true


func _on_connected_to_server() -> void:
	local_player_id = multiplayer.get_unique_id()

	register_player.rpc_id(
		1,
		local_player_id,
		local_player_name
	)

	connected_to_server.emit()


# =========================================================
# CONNECTION
# =========================================================

func _on_peer_connected(id: int) -> void:
	print("Player connected: ", id)


func _on_peer_disconnected(id: int) -> void:
	print("Player disconnected: ", id)

	if is_host:
		if players.has(id):
			players.erase(id)

		if player_states.has(id):
			player_states.erase(id)

		_sync_players_to_all()
		_send_leaderboard()

		player_disconnected.emit(id)
		player_left_signal.emit(id)


func close_connection() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()

	multiplayer.multiplayer_peer = null

	players.clear()
	player_states.clear()
	foods.clear()
	death_loot.clear()

	is_host = false
	is_connected = false
	local_player_id = 0

# =========================================================
# PLAYER REGISTER
# =========================================================

func _register_local_player() -> void:
	var spawn_position := _get_safe_spawn_position()

	players[local_player_id] = {
		"name": local_player_name,
		"position": spawn_position,
		"direction": Vector2.RIGHT,
		"length": INITIAL_LENGTH,
		"alive": true,
		"kills": 0,
		"deaths": 0,
		"protected_until": Time.get_ticks_msec() / 1000.0 + SPAWN_PROTECTION_TIME
	}

	player_states[local_player_id] = players[local_player_id].duplicate(true)

	_sync_players_to_all()
	_send_leaderboard()


@rpc("any_peer", "reliable")
func register_player(peer_id: int, player_name: String) -> void:
	if not is_host:
		return

	var sender := multiplayer.get_remote_sender_id()

	if sender != peer_id:
		peer_id = sender

	player_name = player_name.strip_edges()

	if player_name.is_empty():
		player_name = "لاعب"

	if player_name.length() > 20:
		player_name = player_name.substr(0, 20)

	var spawn_position := _get_safe_spawn_position()

	players[peer_id] = {
		"name": player_name,
		"position": spawn_position,
		"direction": Vector2.RIGHT,
		"length": INITIAL_LENGTH,
		"alive": true,
		"kills": 0,
		"deaths": 0,
		"protected_until": Time.get_ticks_msec() / 1000.0 + SPAWN_PROTECTION_TIME
	}

	player_states[peer_id] = players[peer_id].duplicate(true)

	player_joined_rpc.rpc(peer_id, player_name)

	_sync_players_to_all()
	_send_leaderboard()


@rpc("authority", "call_remote", "reliable")
func player_joined_rpc(peer_id: int, player_name: String) -> void:
	player_joined_signal.emit(peer_id, player_name)


func _get_safe_spawn_position() -> Vector2:
	var attempts := 30

	for i in range(attempts):
		var candidate := Vector2(
			randf_range(-MAP_SIZE.x / 2.0 + SPAWN_MARGIN, MAP_SIZE.x / 2.0 - SPAWN_MARGIN),
			randf_range(-MAP_SIZE.y / 2.0 + SPAWN_MARGIN, MAP_SIZE.y / 2.0 - SPAWN_MARGIN)
		)

		var safe := true

		for id in players:
			var data: Dictionary = players[id]

			if not data.get("alive", false):
				continue

			var other_position: Vector2 = data.get("position", Vector2.ZERO)

			if candidate.distance_to(other_position) < MIN_SPAWN_DISTANCE:
				safe = false
				break

		if safe:
			return candidate

	return Vector2.ZERO


# =========================================================
# PLAYER STATE
# =========================================================

func broadcast_player_state(
	position_value: Vector2,
	direction_value: Vector2,
	length_value: int,
	alive_value: bool
) -> void:

	if not is_connected:
		return

	if is_host:
		_update_server_player_state(
			local_player_id,
			position_value,
			direction_value,
			length_value,
			alive_value
		)

		return

	submit_player_state.rpc_id(
		1,
		position_value,
		direction_value,
		length_value,
		alive_value
	)


@rpc("any_peer", "unreliable")
func submit_player_state(
	position_value: Vector2,
	direction_value: Vector2,
	length_value: int,
	alive_value: bool
) -> void:

	if not is_host:
		return

	var sender := multiplayer.get_remote_sender_id()

	_update_server_player_state(
		sender,
		position_value,
		direction_value,
		length_value,
		alive_value
	)


func _update_server_player_state(
	peer_id: int,
	position_value: Vector2,
	direction_value: Vector2,
	length_value: int,
	alive_value: bool
) -> void:

	if not players.has(peer_id):
		return

	var data: Dictionary = players[peer_id]

	data["position"] = position_value
	data["direction"] = direction_value
	data["length"] = max(MIN_LENGTH, length_value)
	data["alive"] = alive_value

	players[peer_id] = data
	player_states[peer_id] = data.duplicate(true)


func _process(delta: float) -> void:
	if not is_host:
		return

	state_timer += delta
	collision_timer += delta
	food_timer += delta

	if state_timer >= STATE_SEND_INTERVAL:
		state_timer = 0.0
		_sync_players_to_all()

	if collision_timer >= COLLISION_CHECK_INTERVAL:
		collision_timer = 0.0
		_check_server_collisions()

	if food_timer >= FOOD_CHECK_INTERVAL:
		food_timer = 0.0
		_check_food_collections()
		_check_loot_collections()

	_cleanup_processed_deaths()


# =========================================================
# PLAYER SYNC
# =========================================================

func _sync_players_to_all() -> void:
	var snapshot: Dictionary = {}

	for id in players:
		snapshot[id] = players[id].duplicate(true)

	sync_players_rpc.rpc(snapshot)


@rpc("authority", "call_remote", "unreliable")
func sync_players_rpc(snapshot: Dictionary) -> void:
	players_synced_signal.emit(snapshot)

	leaderboard_updated_signal.emit(
		_build_leaderboard_from_snapshot(snapshot)
	)


# =========================================================
# LEADERBOARD
# =========================================================

func _build_leaderboard_from_snapshot(snapshot: Dictionary) -> Array:
	var leaderboard: Array = []

	for id in snapshot:
		var data: Dictionary = snapshot[id]

		leaderboard.append({
			"id": int(id),
			"name": str(data.get("name", "لاعب")),
			"length": int(data.get("length", INITIAL_LENGTH)),
			"kills": int(data.get("kills", 0)),
			"deaths": int(data.get("deaths", 0)),
			"alive": bool(data.get("alive", true))
		})

	leaderboard.sort_custom(_sort_leaderboard)

	for i in range(leaderboard.size()):
		leaderboard[i]["rank"] = i + 1

	return leaderboard


func _sort_leaderboard(a: Dictionary, b: Dictionary) -> bool:
	var length_a := int(a.get("length", 0))
	var length_b := int(b.get("length", 0))

	if length_a != length_b:
		return length_a > length_b

	var kills_a := int(a.get("kills", 0))
	var kills_b := int(b.get("kills", 0))

	if kills_a != kills_b:
		return kills_a > kills_b

	return int(a.get("id", 0)) < int(b.get("id", 0))


func _send_leaderboard() -> void:
	var leaderboard := _build_leaderboard_from_snapshot(players)

	leaderboard_updated_signal.emit(leaderboard)

	leaderboard_rpc.rpc(leaderboard)


@rpc("authority", "call_remote", "reliable")
func leaderboard_rpc(data: Array) -> void:
	leaderboard_updated_signal.emit(data)


func get_current_leaderboard() -> Array:
	return _build_leaderboard_from_snapshot(players)


func get_player_rank(peer_id: int) -> int:
	var leaderboard := _build_leaderboard_from_snapshot(players)

	for entry in leaderboard:
		if int(entry.get("id", 0)) == peer_id:
			return int(entry.get("rank", 0))

	return 0


# =========================================================
# COLLISIONS
# =========================================================

func _check_server_collisions() -> void:
	var ids := players.keys()

	for i in range(ids.size()):
		var id_a = ids[i]

		if not players.has(id_a):
			continue

		if not players[id_a].get("alive", false):
			continue

		for j in range(i + 1, ids.size()):
			var id_b = ids[j]

			if not players.has(id_b):
				continue

			if not players[id_b].get("alive", false):
				continue

			_check_snake_pair(id_a, id_b)


func _check_snake_pair(id_a: int, id_b: int) -> void:
	var a: Dictionary = players[id_a]
	var b: Dictionary = players[id_b]

	var pos_a: Vector2 = a.get("position", Vector2.ZERO)
	var pos_b: Vector2 = b.get("position", Vector2.ZERO)

	if pos_a.distance_to(pos_b) > HEAD_COLLISION_DISTANCE:
		return

	var protection_a := float(a.get("protected_until", 0.0))
	var protection_b := float(b.get("protected_until", 0.0))

	var now := Time.get_ticks_msec() / 1000.0

	if now < protection_a or now < protection_b:
		return

	var length_a := int(a.get("length", INITIAL_LENGTH))
	var length_b := int(b.get("length", INITIAL_LENGTH))

	if length_a > length_b:
		_kill_player(id_b, id_a, pos_b)
	elif length_b > length_a:
		_kill_player(id_a, id_b, pos_a)
	else:
		_kill_player(id_a, id_b, pos_a)
		_kill_player(id_b, id_a, pos_b)


func check_body_collision(
	victim_id: int,
	body_positions: Array[Vector2]
) -> bool:

	if not is_host:
		return false

	if not players.has(victim_id):
		return false

	if not players[victim_id].get("alive", false):
		return false

	var victim_position: Vector2 = players[victim_id].get(
		"position",
		Vector2.ZERO
	)

	for body_position in body_positions:
		if victim_position.distance_to(body_position) <= BODY_COLLISION_DISTANCE:
			return true

	return false


# =========================================================
# DEATH / KILLS
# =========================================================

func _kill_player(
	victim_id: int,
	killer_id: int = 0,
	death_position: Vector2 = Vector2.ZERO
) -> void:

	if not is_host:
		return

	if not players.has(victim_id):
		return

	if not players[victim_id].get("alive", false):
		return

	if processed_deaths.has(victim_id):
		return

	processed_deaths[victim_id] = Time.get_ticks_msec()

	var victim: Dictionary = players[victim_id]

	victim["alive"] = false
	victim["length"] = MIN_LENGTH
	victim["deaths"] = int(victim.get("deaths", 0)) + 1

	players[victim_id] = victim

	var reward := {
		"coins": 0,
		"xp": 0
	}

	if killer_id != 0 and killer_id != victim_id and players.has(killer_id):
		reward = _award_killer(killer_id)

	_spawn_death_loot(
		death_position,
		int(victim.get("length", INITIAL_LENGTH))
	)

	player_died_rpc.rpc(
		victim_id,
		killer_id,
		death_position,
		reward
	)

	_sync_players_to_all()
	_send_leaderboard()


func _award_killer(killer_id: int) -> Dictionary:
	var reward := {
		"coins": KILL_COINS,
		"xp": KILL_XP
	}

	if not players.has(killer_id):
		return reward

	var killer: Dictionary = players[killer_id]

	killer["kills"] = int(killer.get("kills", 0)) + 1

	players[killer_id] = killer

	if killer_id == local_player_id:
		Global.add_coins(KILL_COINS)
		Global.add_experience(KILL_XP)

	award_killer_rpc.rpc(
		killer_id,
		KILL_COINS,
		KILL_XP
	)

	return reward


@rpc("authority", "call_remote", "reliable")
func award_killer_rpc(
	killer_id: int,
	coins: int,
	xp: int
) -> void:

	if killer_id == multiplayer.get_unique_id():
		Global.add_coins(coins)
		Global.add_experience(xp)


@rpc("authority", "call_remote", "reliable")
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


# =========================================================
# RESPAWN
# =========================================================

func request_respawn() -> void:
	if not is_connected:
		return

	if is_host:
		_respawn_player(local_player_id)
	else:
		request_respawn_rpc.rpc_id(1)
	

@rpc("any_peer", "reliable")
func request_respawn_rpc() -> void:
	if not is_host:
		return

	var sender := multiplayer.get_remote_sender_id()

	_respawn_player(sender)


func _respawn_player(peer_id: int) -> void:
	if not players.has(peer_id):
		return

	var spawn_position := _get_safe_spawn_position()

	var data: Dictionary = players[peer_id]

	data["position"] = spawn_position
	data["direction"] = Vector2.RIGHT
	data["length"] = INITIAL_LENGTH
	data["alive"] = true
	data["protected_until"] = (
		Time.get_ticks_msec() / 1000.0
		+ SPAWN_PROTECTION_TIME
	)

	players[peer_id] = data
	player_states[peer_id] = data.duplicate(true)

	player_respawned_rpc.rpc(
		peer_id,
		spawn_position
	)

	_sync_players_to_all()
	_send_leaderboard()


@rpc("authority", "call_remote", "reliable")
func player_respawned_rpc(
	peer_id: int,
	spawn_position: Vector2
) -> void:

	player_respawned_signal.emit(
		peer_id,
		spawn_position
	)


# =========================================================
# FOOD
# =========================================================

func _create_initial_food() -> void:
	for i in range(100):
		_spawn_food()


func _spawn_food() -> void:
	var id := next_food_id
	next_food_id += 1

	var food := {
		"id": id,
		"position": Vector2(
			randf_range(-MAP_SIZE.x / 2.0, MAP_SIZE.x / 2.0),
			randf_range(-MAP_SIZE.y / 2.0, MAP_SIZE.y / 2.0)
		),
		"value": randi_range(1, 3)
	}

	foods[id] = food

	food_spawned_rpc.rpc(
		id,
		food["position"],
		food["value"]
	)


@rpc("authority", "call_remote", "reliable")
func food_spawned_rpc(
	food_id: int,
	position_value: Vector2,
	value: int
) -> void:

	foods[food_id] = {
		"id": food_id,
		"position": position_value,
		"value": value
	}

	food_spawned_signal.emit(
		food_id,
		position_value,
		value
	)


func _check_food_collections() -> void:
	for player_id in players:
		if not players[player_id].get("alive", false):
			continue

		var player_position: Vector2 = players[player_id].get(
			"position",
			Vector2.ZERO
		)

		var collected_id := -1

		for food_id in foods:
			var food: Dictionary = foods[food_id]

			if player_position.distance_to(
				food["position"]
			) <= 35.0:

				collected_id = int(food_id)
				break

		if collected_id != -1:
			_collect_food(
				collected_id,
				player_id
			)


func _collect_food(
	food_id: int,
	player_id: int
) -> void:

	if not foods.has(food_id):
		return

	var value := int(foods[food_id].get("value", 1))

	foods.erase(food_id)

	food_collected_rpc.rpc(
		food_id,
		player_id,
		value
	)

	_spawn_food()


@rpc("authority", "call_remote", "reliable")
func food_collected_rpc(
	food_id: int,
	collector_id: int,
	value: int
) -> void:

	foods.erase(food_id)

	food_collected_signal.emit(
		food_id,
		collector_id,
		value
	)


# =========================================================
# DEATH LOOT
# =========================================================

func _spawn_death_loot(
	death_position: Vector2,
	length: int
) -> void:

	var amount := min(
		MAX_DEATH_LOOT,
		max(1, length * LOOT_PER_SEGMENT)
	)

	for i in range(amount):
		var loot_id := next_loot_id
		next_loot_id += 1

		var angle := randf() * TAU
		var distance := randf_range(20.0, 130.0)

		var position_value := death_position + Vector2(
			cos(angle),
			sin(angle)
		) * distance

		var loot := {
			"id": loot_id,
			"position": position_value,
			"coins": LOOT_COIN_VALUE,
			"xp": LOOT_XP_VALUE
		}

		death_loot[loot_id] = loot

		loot_spawned_rpc.rpc(
			loot_id,
			position_value,
			LOOT_COIN_VALUE,
			LOOT_XP_VALUE
		)


@rpc("authority", "call_remote", "reliable")
func loot_spawned_rpc(
	loot_id: int,
	position_value: Vector2,
	coins: int,
	xp: int
) -> void:

	death_loot[loot_id] = {
		"id": loot_id,
		"position": position_value,
		"coins": coins,
		"xp": xp
	}

	loot_spawned_signal.emit(
		loot_id,
		position_value,
		coins,
		xp
	)


func _check_loot_collections() -> void:
	for player_id in players:
		if not players[player_id].get("alive", false):
			continue

		var player_position: Vector2 = players[player_id].get(
			"position",
			Vector2.ZERO
		)

		var collected_id := -1

		for loot_id in death_loot:
			var loot: Dictionary = death_loot[loot_id]

			if player_position.distance_to(
				loot["position"]
			) <= 35.0:

				collected_id = int(loot_id)
				break

		if collected_id != -1:
			_collect_loot(
				collected_id,
				player_id
			)


func _collect_loot(
	loot_id: int,
	player_id: int
) -> void:

	if not death_loot.has(loot_id):
		return

	var loot: Dictionary = death_loot[loot_id]

	var coins := int(loot.get("coins", 0))
	var xp := int(loot.get("xp", 0))

	death_loot.erase(loot_id)

	loot_collected_rpc.rpc(
		loot_id,
		player_id,
		coins,
		xp
	)


@rpc("authority", "call_remote", "reliable")
func loot_collected_rpc(
	loot_id: int,
	collector_id: int,
	coins: int,
	xp: int
) -> void:

	death_loot.erase(loot_id)

	if collector_id == multiplayer.get_unique_id():
		Global.add_coins(coins)
		Global.add_experience(xp)

	loot_collected_signal.emit(
		loot_id,
		collector_id,
		coins,
		xp
	)


# =========================================================
# CLEANUP
# =========================================================

func _cleanup_processed_deaths() -> void:
	var now := Time.get_ticks_msec()

	for id in processed_deaths.keys():
		if now - int(processed_deaths[id]) > 3000:
			processed_deaths.erase(id)


# =========================================================
# HELPERS
# =========================================================

func get_player_count() -> int:
	return players.size()


func get_local_player() -> Dictionary:
	if players.has(local_player_id):
		return players[local_player_id]

	return {}


func get_player_data(peer_id: int) -> Dictionary:
	if players.has(peer_id):
		return players[peer_id]

	return {}


func is_player_alive(peer_id: int) -> bool:
	if not players.has(peer_id):
		return false

	return bool(players[peer_id].get("alive", false))


func get_kills(peer_id: int) -> int:
	if not players.has(peer_id):
		return 0

	return int(players[peer_id].get("kills", 0))


func get_deaths(peer_id: int) -> int:
	if not players.has(peer_id):
		return 0

	return int(players[peer_id].get("deaths", 0))
