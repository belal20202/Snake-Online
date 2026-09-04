extends Node

# =========================================================
# SNAKE ARAB ONLINE
# NETWORK / ROOMS / MATCHMAKING
# STEP 6.6.13
# Godot 4
# =========================================================

signal connected_to_server
signal connection_failed

signal player_connected
signal player_disconnected

signal player_joined_signal
signal player_left_signal
signal players_synced_signal

signal player_died_signal
signal player_respawned_signal

signal food_spawned_signal
signal food_collected_signal

signal loot_spawned_signal
signal loot_collected_signal

signal leaderboard_updated_signal

# =========================================================
# ROOM SIGNALS
# =========================================================

signal room_created_signal
signal room_joined_signal
signal room_left_signal
signal room_updated_signal
signal room_started_signal
signal room_error_signal
signal matchmaking_started_signal
signal matchmaking_stopped_signal

# =========================================================
# SETTINGS
# =========================================================

const PORT := 7777

const MAX_PLAYERS := 20

const MAP_SIZE := Vector2(
	4000.0,
	4000.0
)

const SPAWN_MARGIN := 350.0

const MIN_SPAWN_DISTANCE := 500.0

const INITIAL_LENGTH := 10

const MIN_LENGTH := 5

const STATE_INTERVAL := 0.05

const COLLISION_INTERVAL := 0.05

const FOOD_INTERVAL := 0.05

const HEAD_COLLISION_DISTANCE := 32.0

const BODY_COLLISION_DISTANCE := 28.0

const PROTECTION_TIME := 3.0

# =========================================================
# ROOM SETTINGS
# =========================================================

const DEFAULT_ROOM_MAX_PLAYERS := 10

const MIN_ROOM_PLAYERS := 2

const MAX_ROOM_PLAYERS := 20

const ROOM_CODE_LENGTH := 6

const MATCHMAKING_MAX_PLAYERS := 10

const MATCHMAKING_TIMEOUT := 20.0

# =========================================================
# REWARDS
# =========================================================

const KILL_REWARD_COINS := 100

const KILL_REWARD_XP := 50

const DEATH_LOOT_PER_SEGMENT := 1

const LOOT_COIN_VALUE := 10

const LOOT_XP_VALUE := 5

const MAX_DEATH_LOOT := 35

# =========================================================
# NETWORK
# =========================================================

var peer: ENetMultiplayerPeer

var is_server: bool = false

var is_connected_to_server: bool = false

var local_player_id: int = 0

# =========================================================
# ROOM STATE
# =========================================================

var current_room_code: String = ""

var current_room_name: String = ""

var current_room_max_players: int = DEFAULT_ROOM_MAX_PLAYERS

var current_room_started: bool = false

var matchmaking_active: bool = false

var matchmaking_time: float = 0.0

# =========================================================
# ROOMS
# =========================================================

var rooms: Dictionary = {}

# Server-side room structure:
#
# rooms[room_code] = {
#     "code": String,
#     "name": String,
#     "host_id": int,
#     "max_players": int,
#     "started": bool,
#     "players": Array
# }

# =========================================================
# PLAYERS
# =========================================================

var players: Dictionary = {}

# player:
#
# {
#   "id": int,
#   "name": String,
#   "position": Vector2,
#   "direction": Vector2,
#   "length": int,
#   "alive": bool,
#   "kills": int,
#   "deaths": int,
#   "protected_until": float,
#   "room": String
# }

# =========================================================
# FOOD
# =========================================================

var food: Dictionary = {}

var food_counter: int = 0

# =========================================================
# LOOT
# =========================================================

var loot: Dictionary = {}

var loot_counter: int = 0

# =========================================================
# TIMERS
# =========================================================

var state_timer: float = 0.0

var collision_timer: float = 0.0

var food_timer: float = 0.0

var leaderboard_timer: float = 0.0

# =========================================================
# LEADERBOARD
# =========================================================

var current_leaderboard: Array = []

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

	if not multiplayer.has_multiplayer_peer():
		return

	if is_server:

		state_timer += delta
		collision_timer += delta
		food_timer += delta
		leaderboard_timer += delta

		_process_rooms(delta)

		if state_timer >= STATE_INTERVAL:

			state_timer = 0.0

			_broadcast_player_states()

		if collision_timer >= COLLISION_INTERVAL:

			collision_timer = 0.0

			_check_all_collisions()

		if food_timer >= FOOD_INTERVAL:

			food_timer = 0.0

			_check_food_collection()

		if leaderboard_timer >= 0.25:

			leaderboard_timer = 0.0

			_send_leaderboard()

	if matchmaking_active and not is_server:

		matchmaking_time += delta

		if matchmaking_time >= MATCHMAKING_TIMEOUT:

			stop_matchmaking()


# =========================================================
# CREATE SERVER
# =========================================================

func host_game(
	room_name: String = "غرفة عربية",
	max_room_players: int = DEFAULT_ROOM_MAX_PLAYERS
) -> bool:

	close_connection()

	peer = ENetMultiplayerPeer.new()

	var result := peer.create_server(
		PORT,
		MAX_PLAYERS
	)

	if result != OK:

		push_error(
			"Failed to create server: "
			+ str(result)
		)

		return false

	multiplayer.multiplayer_peer = peer

	is_server = true

	is_connected_to_server = true

	local_player_id = multiplayer.get_unique_id()

	current_room_code = _generate_room_code()

	current_room_name = room_name

	current_room_max_players = clamp(
		max_room_players,
		MIN_ROOM_PLAYERS,
		MAX_ROOM_PLAYERS
	)

	current_room_started = false

	_create_server_room()

	print(
		"Server started on port ",
		PORT
	)

	print(
		"Room Code: ",
		current_room_code
	)

	connected_to_server.emit()

	room_created_signal.emit(
		current_room_code
	)

	return true


# =========================================================
# JOIN SERVER
# =========================================================

func join_game(
	address: String,
	room_code: String = ""
) -> bool:

	close_connection()

	peer = ENetMultiplayerPeer.new()

	var result := peer.create_client(
		address,
		PORT
	)

	if result != OK:

		push_error(
			"Failed to connect: "
			+ str(result)
		)

		connection_failed.emit()

		return false

	multiplayer.multiplayer_peer = peer

	is_server = false

	is_connected_to_server = false

	current_room_code = room_code.to_upper()

	print(
		"Connecting to server: ",
		address
	)

	return true


# =========================================================
# CONNECTION SUCCESS
# =========================================================

func _on_connected_to_server() -> void:

	is_connected_to_server = true

	local_player_id = multiplayer.get_unique_id()

	print(
		"Connected to server. ID: ",
		local_player_id
	)

	connected_to_server.emit()

	# إرسال طلب الانضمام للغرفة
	if current_room_code != "":

		request_join_room.rpc_id(
			1,
			current_room_code,
			Global.player_name
		)


# =========================================================
# CONNECTION FAILED
# =========================================================

func _on_connection_failed() -> void:

	is_connected_to_server = false

	print(
		"Connection failed."
	)

	connection_failed.emit()


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

	player_connected.emit()


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

	if is_server:

		_remove_player_from_room(
			peer_id
		)

		if players.has(peer_id):

			var player_name: String = players[
				peer_id
			].get(
				"name",
				"لاعب"
			)

			players.erase(
				peer_id
			)

			player_left_rpc.rpc(
				peer_id,
				player_name
			)

		_send_room_update()

	player_disconnected.emit()


# =========================================================
# CREATE SERVER ROOM
# =========================================================

func _create_server_room() -> void:

	var room_data := {
		"code": current_room_code,
		"name": current_room_name,
		"host_id": local_player_id,
		"max_players": current_room_max_players,
		"started": false,
		"players": []
	}

	rooms[current_room_code] = room_data

	# إضافة المضيف
	rooms[current_room_code]["players"].append(
		local_player_id
	)

	_register_player(
		local_player_id,
		Global.player_name
	)


# =========================================================
# REGISTER PLAYER
# =========================================================

func _register_player(
	peer_id: int,
	player_name: String
) -> void:

	var spawn_position := _get_safe_spawn_position()

	players[peer_id] = {
		"id": peer_id,
		"name": player_name,
		"position": spawn_position,
		"direction": Vector2.RIGHT,
		"length": INITIAL_LENGTH,
		"alive": true,
		"kills": 0,
		"deaths": 0,
		"protected_until": Time.get_ticks_msec() / 1000.0 + PROTECTION_TIME,
		"room": current_room_code
	}


# =========================================================
# REQUEST JOIN ROOM
# =========================================================

@rpc("any_peer", "reliable")
func request_join_room(
	room_code: String,
	player_name: String
) -> void:

	if not is_server:
		return

	var sender_id := multiplayer.get_remote_sender_id()

	room_code = room_code.to_upper()

	if not rooms.has(room_code):

		room_join_failed_rpc.rpc_id(
			sender_id,
			"الغرفة غير موجودة"
		)

		return

	var room: Dictionary = rooms[
		room_code
	]

	var room_players: Array = room[
		"players"
	]

	if room["started"]:

		room_join_failed_rpc.rpc_id(
			sender_id,
			"المباراة بدأت بالفعل"
		)

		return

	if room_players.size() >= room["max_players"]:

		room_join_failed_rpc.rpc_id(
			sender_id,
			"الغرفة ممتلئة"
		)

		return

	if room_players.has(sender_id):

		return

	# -----------------------------------------------------
	# إضافة اللاعب
	# -----------------------------------------------------

	room_players.append(
		sender_id
	)

	rooms[room_code] = room

	# إذا كان اللاعب في غرفة أخرى
	_remove_player_from_other_rooms(
		sender_id,
		room_code
	)

	var clean_name := player_name.strip_edges()

	if clean_name == "":
		clean_name = "لاعب"

	players[sender_id] = {
		"id": sender_id,
		"name": clean_name,
		"position": _get_safe_spawn_position(),
		"direction": Vector2.RIGHT,
		"length": INITIAL_LENGTH,
		"alive": true,
		"kills": 0,
		"deaths": 0,
		"protected_until": Time.get_ticks_msec() / 1000.0 + PROTECTION_TIME,
		"room": room_code
	}

	player_joined_rpc.rpc(
		sender_id,
		clean_name
	)

	_send_room_update()

	_sync_players_to_room(
		room_code
	)

	print(
		"Player ",
		sender_id,
		" joined room ",
		room_code
	)


# =========================================================
# REMOVE PLAYER FROM OTHER ROOMS
# =========================================================

func _remove_player_from_other_rooms(
	peer_id: int,
	except_room: String
) -> void:

	for code in rooms.keys():

		if code == except_room:
			continue

		var room: Dictionary = rooms[
			code
		]

		var room_players: Array = room[
			"players"
		]

		if room_players.has(peer_id):

			room_players.erase(
				peer_id
			)

			room["players"] = room_players

			rooms[code] = room


# =========================================================
# LEAVE ROOM
# =========================================================

@rpc("any_peer", "reliable")
func request_leave_room() -> void:

	if not is_server:
		return

	var sender_id := multiplayer.get_remote_sender_id()

	_leave_room_server(
		sender_id
	)


func leave_room() -> void:

	if is_server:

		_leave_room_server(
			local_player_id
		)

	else:

		if multiplayer.has_multiplayer_peer():

			request_leave_room.rpc_id(
				1
			)


# =========================================================
# SERVER LEAVE
# =========================================================

func _leave_room_server(
	peer_id: int
) -> void:

	var room_code := ""

	if players.has(peer_id):

		room_code = players[
			peer_id
		].get(
			"room",
			""
		)

	if room_code != "" and rooms.has(room_code):

		var room: Dictionary = rooms[
			room_code
		]

		var room_players: Array = room[
			"players"
		]

		room_players.erase(
			peer_id
		)

		room["players"] = room_players

		# -------------------------------------------------
		# إذا خرج المضيف
		# -------------------------------------------------

		if int(room["host_id"]) == peer_id:

			if room_players.is_empty():

				rooms.erase(
					room_code
				)

			else:

				room["host_id"] = int(
					room_players[0]
				)

				rooms[room_code] = room

		else:

			rooms[room_code] = room

	players.erase(
		peer_id
	)

	if peer_id == local_player_id:

		current_room_code = ""

		current_room_name = ""

		current_room_started = false

	room_left_signal.emit()

	_send_room_update()


# =========================================================
# GET ROOM LIST
# =========================================================

@rpc("any_peer", "reliable")
func request_room_list() -> void:

	if not is_server:
		return

	var sender_id := multiplayer.get_remote_sender_id()

	var room_list: Array = []

	for code in rooms.keys():

		var room: Dictionary = rooms[
			code
		]

		room_list.append({
			"code": room["code"],
			"name": room["name"],
			"players": room["players"].size(),
			"max_players": room["max_players"],
			"started": room["started"]
		})

	room_list_rpc.rpc_id(
		sender_id,
		room_list
	)


# =========================================================
# ROOM LIST RPC
# =========================================================

@rpc("authority", "reliable")
func room_list_rpc(
	room_list: Array
) -> void:

	rooms.clear()

	for room_data in room_list:

		rooms[
			room_data["code"]
		] = room_data


# =========================================================
# ROOM UPDATE
# =========================================================

func _send_room_update() -> void:

	var room_list: Array = []

	for code in rooms.keys():

		var room: Dictionary = rooms[
			code
		]

		room_list.append({
			"code": room["code"],
			"name": room["name"],
			"host_id": room["host_id"],
			"players": room["players"].size(),
			"max_players": room["max_players"],
			"started": room["started"]
		})

	room_update_rpc.rpc(
		room_list
	)

	room_updated_signal.emit(
		room_list
	)


@rpc("authority", "reliable")
func room_update_rpc(
	room_list: Array
) -> void:

	rooms.clear()

	for room_data in room_list:

		rooms[
			room_data["code"]
		] = room_data

	room_updated_signal.emit(
		room_list
	)


# =========================================================
# START ROOM
# =========================================================

func start_room() -> bool:

	if not is_server:
		return false

	if current_room_code == "":
		return false

	if not rooms.has(
		current_room_code
	):
		return false

	var room: Dictionary = rooms[
		current_room_code
	]

	var room_players: Array = room[
		"players"
	]

	if room_players.size() < MIN_ROOM_PLAYERS:

		room_error_signal.emit(
			"يجب وجود لاعبين على الأقل"
		)

		return false

	room["started"] = true

	rooms[current_room_code] = room

	current_room_started = true

	start_room_rpc.rpc(
		current_room_code
	)

	room_started_signal.emit(
		current_room_code
	)

	_send_room_update()

	return true


@rpc("any_peer", "reliable")
func request_start_room() -> void:

	if not is_server:
		return

	var sender_id := multiplayer.get_remote_sender_id()

	if current_room_code == "":
		return

	if not rooms.has(
		current_room_code
	):
		return

	var room: Dictionary = rooms[
		current_room_code
	]

	if int(room["host_id"]) != sender_id:

		return

	start_room()


@rpc("authority", "reliable")
func start_room_rpc(
	room_code: String
) -> void:

	current_room_code = room_code

	current_room_started = true

	room_started_signal.emit(
		room_code
	)


# =========================================================
# STOP ROOM
# =========================================================

func stop_room() -> void:

	if not is_server:
		return

	if current_room_code == "":
		return

	if not rooms.has(
		current_room_code
	):
		return

	var room: Dictionary = rooms[
		current_room_code
	]

	room["started"] = false

	rooms[current_room_code] = room

	current_room_started = false

	room_stopped_rpc.rpc(
		current_room_code
	)

	_send_room_update()


@rpc("authority", "reliable")
func room_stopped_rpc(
	room_code: String
) -> void:

	if current_room_code != room_code:
		return

	current_room_started = false


# =========================================================
# MATCHMAKING
# =========================================================

func start_matchmaking() -> void:

	if is_server:
		return

	if matchmaking_active:
		return

	matchmaking_active = true

	matchmaking_time = 0.0

	matchmaking_started_signal.emit()

	request_matchmaking.rpc_id(
		1,
		Global.player_name
	)


func stop_matchmaking() -> void:

	if not matchmaking_active:
		return

	matchmaking_active = false

	matchmaking_time = 0.0

	if not is_server:

		if multiplayer.has_multiplayer_peer():

			cancel_matchmaking.rpc_id(
				1
			)

	matchmaking_stopped_signal.emit()


@rpc("any_peer", "reliable")
func request_matchmaking(
	player_name: String
) -> void:

	if not is_server:
		return

	var sender_id := multiplayer.get_remote_sender_id()

	# -----------------------------------------------------
	# البحث عن غرفة مناسبة
	# -----------------------------------------------------

	var selected_room := ""

	for code in rooms.keys():

		var room: Dictionary = rooms[
			code
		]

		if room["started"]:
			continue

		var room_players: Array = room[
			"players"
		]

		if room_players.size() >= room["max_players"]:
			continue

		if room_players.size() >= MATCHMAKING_MAX_PLAYERS:
			continue

		selected_room = code

		break

	# -----------------------------------------------------
	# لا توجد غرفة -> إنشاء غرفة
	# -----------------------------------------------------

	if selected_room == "":

		selected_room = _generate_room_code()

		while rooms.has(
			selected_room
		):

			selected_room = _generate_room_code()

		rooms[selected_room] = {
			"code": selected_room,
			"name": "مباراة سريعة",
			"host_id": sender_id,
			"max_players": MATCHMAKING_MAX_PLAYERS,
			"started": false,
			"players": []
		}

	# -----------------------------------------------------
	# إضافة اللاعب
	# -----------------------------------------------------

	var room: Dictionary = rooms[
		selected_room
	]

	var room_players: Array = room[
		"players"
	]

	if not room_players.has(
		sender_id
	):

		room_players.append(
			sender_id
		)

	room["players"] = room_players

	rooms[selected_room] = room

	players[sender_id] = {
		"id": sender_id,
		"name": player_name,
		"position": _get_safe_spawn_position(),
		"direction": Vector2.RIGHT,
		"length": INITIAL_LENGTH,
		"alive": true,
		"kills": 0,
		"deaths": 0,
		"protected_until": Time.get_ticks_msec() / 1000.0 + PROTECTION_TIME,
		"room": selected_room
	}

	assign_matchmaking_room_rpc.rpc_id(
		sender_id,
		selected_room
	)

	_sync_players_to_room(
		selected_room
	)

	# -----------------------------------------------------
	# بدء المباراة إذا أصبح العدد مناسبًا
	# -----------------------------------------------------

	if room_players.size() >= MIN_ROOM_PLAYERS:

		room["started"] = true

		rooms[selected_room] = room

		start_room_rpc.rpc(
			selected_room
		)

	_send_room_update()


@rpc("any_peer", "reliable")
func cancel_matchmaking() -> void:

	if not is_server:
		return

	var sender_id := multiplayer.get_remote_sender_id()

	_remove_player_from_room(
		sender_id
	)


@rpc("authority", "reliable")
func assign_matchmaking_room_rpc(
	room_code: String
) -> void:

	current_room_code = room_code

	matchmaking_active = false

	matchmaking_time = 0.0

	room_joined_signal.emit(
		room_code
	)

	room_started_signal.emit(
		room_code
	)


# =========================================================
# ROOM JOINED
# =========================================================

@rpc("authority", "reliable")
func room_joined_rpc(
	room_code: String,
	room_name: String,
	max_players: int,
	started: bool
) -> void:

	current_room_code = room_code

	current_room_name = room_name

	current_room_max_players = max_players

	current_room_started = started

	matchmaking_active = false

	room_joined_signal.emit(
		room_code
	)


# =========================================================
# ROOM JOIN FAILED
# =========================================================

@rpc("authority", "reliable")
func room_join_failed_rpc(
	message: String
) -> void:

	print(
		"Room join failed: ",
		message
	)

	room_error_signal.emit(
		message
	)


# =========================================================
# ROOM PLAYER REMOVAL
# =========================================================

func _remove_player_from_room(
	peer_id: int
) -> void:

	if not players.has(peer_id):
		return

	var room_code: String = players[
		peer_id
	].get(
		"room",
		""
	)

	if room_code == "":
		return

	if not rooms.has(room_code):
		return

	var room: Dictionary = rooms[
		room_code
	]

	var room_players: Array = room[
		"players"
	]

	room_players.erase(
		peer_id
	)

	room["players"] = room_players

	if room_players.is_empty():

		rooms.erase(
			room_code
		)

	else:

		if int(room["host_id"]) == peer_id:

			room["host_id"] = int(
				room_players[0]
			)

		rooms[room_code] = room


# =========================================================
# SYNC PLAYERS
# =========================================================

func _sync_players_to_room(
	room_code: String
) -> void:

	if not rooms.has(room_code):
		return

	var room: Dictionary = rooms[
		room_code
	]

	var room_players: Array = room[
		"players"
	]

	var snapshot: Array = []

	for peer_id in room_players:

		if not players.has(peer_id):
			continue

		var player: Dictionary = players[
			peer_id
		]

		snapshot.append({
			"id": peer_id,
			"name": player["name"],
			"position": player["position"],
			"direction": player["direction"],
			"length": player["length"],
			"alive": player["alive"],
			"kills": player["kills"],
			"deaths": player["deaths"]
		})

	for peer_id in room_players:

		if peer_id == local_player_id:
			continue

		sync_players_rpc.rpc_id(
			peer_id,
			snapshot
		)

	players_synced_signal.emit(
		snapshot
	)


@rpc("authority", "reliable")
func sync_players_rpc(
	snapshot: Array
) -> void:

	players_synced_signal.emit(
		snapshot
	)


# =========================================================
# BROADCAST PLAYER STATES
# =========================================================

func _broadcast_player_states() -> void:

	var room_snapshots: Dictionary = {}

	for peer_id in players.keys():

		var player: Dictionary = players[
			peer_id
		]

		var room_code: String = player.get(
			"room",
			""
		)

		if room_code == "":
			continue

		if not room_snapshots.has(
			room_code
		):

			room_snapshots[room_code] = []

		room_snapshots[room_code].append({
			"id": peer_id,
			"name": player["name"],
			"position": player["position"],
			"direction": player["direction"],
			"length": player["length"],
			"alive": player["alive"],
			"kills": player["kills"],
			"deaths": player["deaths"]
		})

	for room_code in room_snapshots.keys():

		var snapshot: Array = room_snapshots[
			room_code
		]

		if not rooms.has(room_code):
			continue

		var room: Dictionary = rooms[
			room_code
		]

		var room_players: Array = room[
			"players"
		]

		for peer_id in room_players:

			if peer_id == local_player_id:
				continue

			sync_players_rpc.rpc_id(
				peer_id,
				snapshot
			)


# =========================================================
# PLAYER STATE
# =========================================================

func broadcast_player_state(
	new_position: Vector2,
	new_direction: Vector2,
	new_length: int
) -> void:

	if local_player_id == 0:
		return

	if is_server:

		_update_server_player_state(
			local_player_id,
			new_position,
			new_direction,
			new_length
		)

		return

	if not multiplayer.has_multiplayer_peer():
		return

	submit_player_state.rpc_id(
		1,
		new_position,
		new_direction,
		new_length
	)


@rpc("any_peer", "unreliable")
func submit_player_state(
	new_position: Vector2,
	new_direction: Vector2,
	new_length: int
) -> void:

	if not is_server:
		return

	var sender_id := multiplayer.get_remote_sender_id()

	_update_server_player_state(
		sender_id,
		new_position,
		new_direction,
		new_length
	)


func _update_server_player_state(
	peer_id: int,
	new_position: Vector2,
	new_direction: Vector2,
	new_length: int
) -> void:

	if not players.has(peer_id):
		return

	var player: Dictionary = players[
		peer_id
	]

	player["position"] = new_position

	player["direction"] = new_direction.normalized()

	player["length"] = clamp(
		new_length,
		MIN_LENGTH,
		10000
	)

	players[peer_id] = player


# =========================================================
# COLLISION CHECK
# =========================================================

func _check_all_collisions() -> void:

	var ids := players.keys()

	for i in range(ids.size()):

		var first_id: int = ids[i]

		if not players.has(first_id):
			continue

		var first_player: Dictionary = players[
			first_id
		]

		if not first_player["alive"]:
			continue

		for j in range(
			i + 1,
			ids.size()
		):

			var second_id: int = ids[j]

			if not players.has(second_id):
				continue

			var second_player: Dictionary = players[
				second_id
			]

			if not second_player["alive"]:
				continue

			if first_player["room"] != second_player["room"]:
				continue

			_check_head_collision(
				first_id,
				second_id
			)


# =========================================================
# HEAD COLLISION
# =========================================================

func _check_head_collision(
	first_id: int,
	second_id: int
) -> void:

	var first_player: Dictionary = players[
		first_id
	]

	var second_player: Dictionary = players[
		second_id
	]

	var distance := first_player[
		"position"
	].distance_to(
		second_player[
			"position"
		]
	)

	if distance > HEAD_COLLISION_DISTANCE:
		return

	# حماية Spawn
	var now := Time.get_ticks_msec() / 1000.0

	if now < float(
		first_player["protected_until"]
	):
		return

	if now < float(
		second_player["protected_until"]
	):
		return

	var first_length: int = first_player[
		"length"
	]

	var second_length: int = second_player[
		"length"
	]

	# -----------------------------------------------------
	# نفس الطول
	# -----------------------------------------------------

	if first_length == second_length:

		_kill_player(
			first_id,
			second_id
		)

		_kill_player(
			second_id,
			first_id
		)

		return

	# -----------------------------------------------------
	# الأول أكبر
	# -----------------------------------------------------

	if first_length > second_length:

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
# KILL
# =========================================================

func _kill_player(
	victim_id: int,
	killer_id: int
) -> void:

	if not players.has(victim_id):
		return

	var victim: Dictionary = players[
		victim_id
	]

	if not victim["alive"]:
		return

	victim["alive"] = false

	victim["deaths"] = int(
		victim["deaths"]
	) + 1

	players[victim_id] = victim

	if killer_id != victim_id:

		if players.has(killer_id):

			var killer: Dictionary = players[
				killer_id
			]

			killer["kills"] = int(
				killer["kills"]
			) + 1

			players[killer_id] = killer

			_award_kill_reward(
				killer_id
			)

	_spawn_death_loot(
		victim_id
	)

	player_died_rpc.rpc(
		victim_id,
		killer_id
	)

	player_died_signal.emit(
		victim_id,
		killer_id
	)


# =========================================================
# KILL REWARD
# =========================================================

func _award_kill_reward(
	killer_id: int
) -> void:

	award_killer_rpc.rpc(
		killer_id,
		KILL_REWARD_COINS,
		KILL_REWARD_XP
	)

	if killer_id == local_player_id:

		Global.add_coins(
			KILL_REWARD_COINS
		)

		Global.add_experience(
			KILL_REWARD_XP
		)


@rpc("authority", "reliable")
func award_killer_rpc(
	killer_id: int,
	coins: int,
	xp: int
) -> void:

	if killer_id != local_player_id:
		return

	Global.add_coins(
		coins
	)

	Global.add_experience(
		xp
	)


# =========================================================
# PLAYER DIED RPC
# =========================================================

@rpc("authority", "reliable")
func player_died_rpc(
	victim_id: int,
	killer_id: int
) -> void:

	player_died_signal.emit(
		victim_id,
		killer_id
	)


# =========================================================
# RESPAWN
# =========================================================

func request_respawn() -> void:

	if is_server:

		_respawn_player(
			local_player_id
		)

	else:

		request_respawn_rpc.rpc_id(
			1
		)


@rpc("any_peer", "reliable")
func request_respawn_rpc() -> void:

	if not is_server:
		return

	var sender_id := multiplayer.get_remote_sender_id()

	_respawn_player(
		sender_id
	)


func _respawn_player(
	peer_id: int
) -> void:

	if not players.has(peer_id):
		return

	var player: Dictionary = players[
		peer_id
	]

	player["position"] = _get_safe_spawn_position()

	player["direction"] = Vector2.RIGHT

	player["length"] = INITIAL_LENGTH

	player["alive"] = true

	player["protected_until"] = (
		Time.get_ticks_msec() / 1000.0
		+ PROTECTION_TIME
	)

	players[peer_id] = player

	player_respawned_rpc.rpc(
		peer_id,
		player["position"]
	)

	player_respawned_signal.emit(
		peer_id
	)


@rpc("authority", "reliable")
func player_respawned_rpc(
	peer_id: int,
	spawn_position: Vector2
) -> void:

	player_respawned_signal.emit(
		peer_id
	)


# =========================================================
# SAFE SPAWN
# =========================================================

func _get_safe_spawn_position() -> Vector2:

	var attempts := 0

	while attempts < 50:

		attempts += 1

		var candidate := Vector2(
			randf_range(
				-SPAWN_MARGIN,
				MAP_SIZE.x + SPAWN_MARGIN
			),
			randf_range(
				-SPAWN_MARGIN,
				MAP_SIZE.y + SPAWN_MARGIN
			)
		)

		var valid := true

		for peer_id in players.keys():

			var player: Dictionary = players[
				peer_id
			]

			if not player["alive"]:
				continue

			if candidate.distance_to(
				player["position"]
			) < MIN_SPAWN_DISTANCE:

				valid = false

				break

		if valid:
			return candidate

	return Vector2(
		MAP_SIZE.x * 0.5,
		MAP_SIZE.y * 0.5
	)


# =========================================================
# FOOD
# =========================================================

func spawn_food(
	position: Vector2,
	value: int = 1
) -> int:

	if not is_server:
		return -1

	food_counter += 1

	var food_id := food_counter

	food[food_id] = {
		"id": food_id,
		"position": position,
		"value": value
	}

	food_spawned_rpc.rpc(
		food_id,
		position,
		value
	)

	food_spawned_signal.emit(
		food_id,
		position,
		value
	)

	return food_id


@rpc("authority", "reliable")
func food_spawned_rpc(
	food_id: int,
	position: Vector2,
	value: int
) -> void:

	food[food_id] = {
		"id": food_id,
		"position": position,
		"value": value
	}

	food_spawned_signal.emit(
		food_id,
		position,
		value
	)


# =========================================================
# FOOD COLLECTION
# =========================================================

func _check_food_collection() -> void:

	if food.is_empty():
		return

	for peer_id in players.keys():

		var player: Dictionary = players[
			peer_id
		]

		if not player["alive"]:
			continue

		var collected_id := -1

		for food_id in food.keys():

			var food_item: Dictionary = food[
				food_id
			]

			if player["position"].distance_to(
				food_item["position"]
			) <= 35.0:

				collected_id = food_id

				break

		if collected_id != -1:

			_collect_food(
				peer_id,
				collected_id
			)


func _collect_food(
	peer_id: int,
	food_id: int
) -> void:

	if not food.has(food_id):
		return

	if not players.has(peer_id):
		return

	var food_item: Dictionary = food[
		food_id
	]

	food.erase(
		food_id
	)

	var player: Dictionary = players[
		peer_id
	]

	player["length"] = int(
		player["length"]
	) + int(
		food_item["value"]
	)

	players[peer_id] = player

	food_collected_rpc.rpc(
		food_id,
		peer_id,
		int(food_item["value"])
	)

	food_collected_signal.emit(
		food_id,
		peer_id,
		int(food_item["value"])
	)


@rpc("authority", "reliable")
func food_collected_rpc(
	food_id: int,
	peer_id: int,
	value: int
) -> void:

	food.erase(
		food_id
	)

	food_collected_signal.emit(
		food_id,
		peer_id,
		value
	)


# =========================================================
# DEATH LOOT
# =========================================================

func _spawn_death_loot(
	victim_id: int
) -> void:

	if not players.has(victim_id):
		return

	var victim: Dictionary = players[
		victim_id
	]

	var amount := min(
		int(victim["length"]) * DEATH_LOOT_PER_SEGMENT,
		MAX_DEATH_LOOT
	)

	for i in range(amount):

		var offset := Vector2(
			randf_range(
				-120.0,
				120.0
			),
			randf_range(
				-120.0,
				120.0
			)
		)

		_spawn_loot(
			victim["position"] + offset,
			LOOT_COIN_VALUE,
			LOOT_XP_VALUE
		)


# =========================================================
# SPAWN LOOT
# =========================================================

func _spawn_loot(
	position: Vector2,
	coins: int,
	xp: int
) -> int:

	loot_counter += 1

	var loot_id := loot_counter

	loot[loot_id] = {
		"id": loot_id,
		"position": position,
		"coins": coins,
		"xp": xp
	}

	loot_spawned_rpc.rpc(
		loot_id,
		position,
		coins,
		xp
	)

	loot_spawned_signal.emit(
		loot_id,
		position,
		coins,
		xp
	)

	return loot_id


@rpc("authority", "reliable")
func loot_spawned_rpc(
	loot_id: int,
	position: Vector2,
	coins: int,
	xp: int
) -> void:

	loot[loot_id] = {
		"id": loot_id,
		"position": position,
		"coins": coins,
		"xp": xp
	}

	loot_spawned_signal.emit(
		loot_id,
		position,
		coins,
		xp
	)


# =========================================================
# LOOT COLLECTION
# =========================================================

func collect_loot(
	loot_id: int
) -> void:

	if is_server:

		_collect_loot(
			local_player_id,
			loot_id
		)

	else:

		request_collect_loot.rpc_id(
			1,
			loot_id
		)


@rpc("any_peer", "reliable")
func request_collect_loot(
	loot_id: int
) -> void:

	if not is_server:
		return

	var sender_id := multiplayer.get_remote_sender_id()

	_collect_loot(
		sender_id,
		loot_id
	)


func _collect_loot(
	peer_id: int,
	loot_id: int
) -> void:

	if not loot.has(loot_id):
		return

	if not players.has(peer_id):
		return

	var loot_item: Dictionary = loot[
		loot_id
	]

	var player: Dictionary = players[
		peer_id
	]

	if player["position"].distance_to(
		loot_item["position"]
	) > 70.0:

		return

	loot.erase(
		loot_id
	)

	loot_collected_rpc.rpc(
		loot_id,
		peer_id,
		loot_item["coins"],
		loot_item["xp"]
	)

	loot_collected_signal.emit(
		loot_id,
		peer_id,
		loot_item["coins"],
		loot_item["xp"]
	)


@rpc("authority", "reliable")
func loot_collected_rpc(
	loot_id: int,
	peer_id: int,
	coins: int,
	xp: int
) -> void:

	loot.erase(
		loot_id
	)

	if peer_id == local_player_id:

		Global.add_coins(
			coins
		)

		Global.add_experience(
			xp
		)

	loot_collected_signal.emit(
		loot_id,
		peer_id,
		coins,
		xp
	)


# =========================================================
# LEADERBOARD
# =========================================================

func _send_leaderboard() -> void:

	if players.is_empty():
		return

	var leaderboard: Array = []

	for peer_id in players.keys():

		var player: Dictionary = players[
			peer_id
		]

		leaderboard.append({
			"id": peer_id,
			"name": player["name"],
			"length": player["length"],
			"kills": player["kills"],
			"deaths": player["deaths"],
			"alive": player["alive"],
			"room": player["room"]
		})

	leaderboard.sort_custom(
		_sort_leaderboard
	)

	current_leaderboard = leaderboard

	leaderboard_rpc.rpc(
		leaderboard
	)

	leaderboard_updated_signal.emit(
		leaderboard
	)


func _sort_leaderboard(
	a: Dictionary,
	b: Dictionary
) -> bool:

	if a["length"] != b["length"]:

		return int(a["length"]) > int(
			b["length"]
		)

	if a["kills"] != b["kills"]:

		return int(a["kills"]) > int(
			b["kills"]
		)

	return int(a["id"]) < int(
		b["id"]
	)


@rpc("authority", "reliable")
func leaderboard_rpc(
	leaderboard: Array
) -> void:

	current_leaderboard = leaderboard

	leaderboard_updated_signal.emit(
		leaderboard
	)


# =========================================================
# GET LEADERBOARD
# =========================================================

func get_current_leaderboard() -> Array:

	return current_leaderboard.duplicate(
		true
	)


# =========================================================
# GET PLAYER RANK
# =========================================================

func get_player_rank(
	peer_id: int = -1
) -> int:

	if peer_id == -1:
		peer_id = local_player_id

	for i in range(
		current_leaderboard.size()
	):

		if int(
			current_leaderboard[i]["id"]
		) == peer_id:

			return i + 1

	return 0


# =========================================================
# GET PLAYER COUNT
# =========================================================

func get_player_count() -> int:

	if current_room_code != "" and rooms.has(
		current_room_code
	):

		var room: Dictionary = rooms[
			current_room_code
		]

		if room.has("players"):

			if room["players"] is Array:
				return room["players"].size()

			return int(
				room["players"]
			)

	return players.size()


# =========================================================
# GET ROOM INFO
# =========================================================

func get_current_room_info() -> Dictionary:

	if current_room_code == "":
		return {}

	if not rooms.has(
		current_room_code
	):

		return {
			"code": current_room_code,
			"name": current_room_name,
			"max_players": current_room_max_players,
			"started": current_room_started
		}

	return rooms[
		current_room_code
	]


# =========================================================
# IS IN ROOM
# =========================================================

func is_in_room() -> bool:

	return current_room_code != ""


# =========================================================
# IS ROOM HOST
# =========================================================

func is_room_host() -> bool:

	if current_room_code == "":
		return false

	if not rooms.has(
		current_room_code
	):

		if is_server:
			return true

		return false

	var room: Dictionary = rooms[
		current_room_code
	]

	return int(
		room.get(
			"host_id",
			-1
		)
	) == local_player_id


# =========================================================
# GET ROOM CODE
# =========================================================

func get_room_code() -> String:

	return current_room_code


# =========================================================
# GENERATE ROOM CODE
# =========================================================

func _generate_room_code() -> String:

	const chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

	var result := ""

	for i in range(
		ROOM_CODE_LENGTH
	):

		result += chars[
			randi() % chars.length()
		]

	return result


# =========================================================
# PROCESS ROOMS
# =========================================================

func _process_rooms(
	_delta: float
) -> void:

	if not is_server:
		return

	var rooms_to_delete: Array = []

	for code in rooms.keys():

		var room: Dictionary = rooms[
			code
		]

		var room_players: Array = room[
			"players"
		]

		# تنظيف اللاعبين غير الموجودين
		var valid_players: Array = []

		for peer_id in room_players:

			if players.has(peer_id):

				valid_players.append(
					peer_id
				)

		room["players"] = valid_players

		# حذف الغرفة الفارغة
		if valid_players.is_empty():

			rooms_to_delete.append(
				code
			)

		else:

			if not room["started"]:

				# لا شيء

				pass

			rooms[code] = room

	for code in rooms_to_delete:

		rooms.erase(
			code
		)


# =========================================================
# CLOSE CONNECTION
# =========================================================

func close_connection() -> void:

	if multiplayer.has_multiplayer_peer():

		multiplayer.multiplayer_peer = null

	peer = null

	is_server = false

	is_connected_to_server = false

	local_player_id = 0

	current_room_code = ""

	current_room_name = ""

	current_room_started = false

	matchmaking_active = false

	players.clear()

	rooms.clear()

	food.clear()

	loot.clear()

	current_leaderboard.clear()


# =========================================================
# DISCONNECT
# =========================================================

func disconnect_from_server() -> void:

	close_connection()


# =========================================================
# FULL BODY COLLISION HELPER
# =========================================================

func check_body_collision(
	head_position: Vector2,
	body_positions: Array
) -> bool:

	for body_position in body_positions:

		if head_position.distance_to(
			body_position
		) <= BODY_COLLISION_DISTANCE:

			return true

	return false


# =========================================================
# DEBUG
# =========================================================

func print_network_status() -> void:

	print(
		"=============================="
	)

	print(
		"Network Status"
	)

	print(
		"Server: ",
		is_server
	)

	print(
		"Connected: ",
		is_connected_to_server
	)

	print(
		"Local ID: ",
		local_player_id
	)

	print(
		"Room: ",
		current_room_code
	)

	print(
		"Players: ",
		get_player_count()
	)

	print(
		"=============================="
	)
