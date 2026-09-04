extends Node2D

# =========================================================
# SNAKE ARAB ONLINE
# STEP 6.6.3
# MULTIPLAYER PLAYER INTEGRATION
# =========================================================

const MAP_SIZE := Vector2(4000.0, 4000.0)

const FOOD_COUNT := 180
const FOOD_RADIUS := 10.0
const FOOD_COLLECT_DISTANCE := 48.0

const MAP_BORDER := 80.0
const SAFE_SPAWN_DISTANCE := 600.0

const REMOTE_SNAKE_SCENE := "res://scripts/remote_snake.gd"

var snake: Node2D
var camera: Camera2D

var foods: Array[Node2D] = []

# جميع اللاعبين الآخرين
var remote_snakes: Dictionary = {}

var score: int = 0
var round_coins: int = 0
var round_xp: int = 0

var game_over := false
var paused := false

var score_label: Label
var length_label: Label
var coins_label: Label
var wallet_label: Label
var level_label: Label
var players_label: Label

var pause_button: Button
var game_over_panel: Panel

var rng := RandomNumberGenerator.new()

var network_state_timer := 0.0
const NETWORK_UPDATE_INTERVAL := 0.05


# =========================================================
# READY
# =========================================================

func _ready() -> void:

	rng.randomize()

	_create_world()

	_create_player()

	_create_camera()

	_create_food()

	_create_ui()

	_connect_network_signals()

	# إنشاء اللاعبين الموجودين أصلًا
	_sync_existing_players()

	queue_redraw()


# =========================================================
# WORLD
# =========================================================

func _create_world() -> void:

	var background := ColorRect.new()

	background.position = Vector2.ZERO
	background.size = MAP_SIZE

	background.color = Color(
		0.055,
		0.075,
		0.065,
		1.0
	)

	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(background)

	move_child(background, 0)


# =========================================================
# CREATE LOCAL PLAYER
# =========================================================

func _create_player() -> void:

	var snake_scene := preload(
		"res://scenes/snake.tscn"
	)

	snake = snake_scene.instantiate()

	snake.position = _get_safe_spawn_position()

	add_child(snake)

	if snake.has_method("setup"):
		snake.setup(
			Global.player_name
		)


# =========================================================
# CAMERA
# =========================================================

func _create_camera() -> void:

	camera = Camera2D.new()

	camera.position = snake.position

	camera.enabled = true

	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0

	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(MAP_SIZE.x)
	camera.limit_bottom = int(MAP_SIZE.y)

	camera.limit_smoothed = true

	add_child(camera)


# =========================================================
# NETWORK SIGNALS
# =========================================================

func _connect_network_signals() -> void:

	if Network == null:
		return

	if not Network.player_joined.is_connected(
		_on_player_joined
	):
		Network.player_joined.connect(
			_on_player_joined
		)

	if not Network.player_left.is_connected(
		_on_player_left
	):
		Network.player_left.connect(
			_on_player_left
		)

	if not Network.connected_to_server.is_connected(
		_on_network_connected
	):
		Network.connected_to_server.connect(
			_on_network_connected
	)


# =========================================================
# EXISTING PLAYERS
# =========================================================

func _sync_existing_players() -> void:

	if Network == null:
		return

	for peer_id in Network.connected_players.keys():

		var id := int(peer_id)

		if id == multiplayer.get_unique_id():
			continue

		var player_data: Dictionary = (
			Network.connected_players[peer_id]
		)

		var player_name := str(
			player_data.get(
				"name",
				"لاعب"
			)
		)

		_create_remote_snake(
			id,
			player_name,
			_get_safe_spawn_position()
		)


# =========================================================
# PLAYER JOINED
# =========================================================

func _on_player_joined(peer_id: int) -> void:

	if peer_id == multiplayer.get_unique_id():
		return

	if remote_snakes.has(peer_id):
		return

	var player_name := "لاعب"

	if Network != null:
		player_name = Network.get_player_name(
			peer_id
		)

	_create_remote_snake(
		peer_id,
		player_name,
		_get_safe_spawn_position()
	)

	_update_players_count()


# =========================================================
# PLAYER LEFT
# =========================================================

func _on_player_left(peer_id: int) -> void:

	_remove_remote_snake(peer_id)

	_update_players_count()


# =========================================================
# NETWORK CONNECTED
# =========================================================

func _on_network_connected() -> void:

	_sync_existing_players()

	_update_players_count()


# =========================================================
# CREATE REMOTE SNAKE
# =========================================================

func _create_remote_snake(
	peer_id: int,
	player_name: String,
	start_position: Vector2
) -> void:

	if remote_snakes.has(peer_id):
		return

	var remote_script = load(
		REMOTE_SNAKE_SCENE
	)

	if remote_script == null:
		push_error(
			"لم يتم العثور على remote_snake.gd"
		)

		return

	var remote_snake := Node2D.new()

	remote_snake.set_script(
		remote_script
	)

	remote_snake.name = (
		"RemoteSnake_%d" % peer_id
	)

	add_child(remote_snake)

	if remote_snake.has_method("setup"):

		remote_snake.setup(
			peer_id,
			player_name,
			start_position
		)

	remote_snakes[peer_id] = remote_snake

	_update_players_count()


# =========================================================
# REMOVE REMOTE SNAKE
# =========================================================

func _remove_remote_snake(
	peer_id: int
) -> void:

	if not remote_snakes.has(peer_id):
		return

	var remote_snake = remote_snakes[
		peer_id
	]

	if is_instance_valid(remote_snake):
		remote_snake.queue_free()

	remote_snakes.erase(peer_id)

	_update_players_count()


# =========================================================
# UPDATE REMOTE PLAYER
# =========================================================

func update_remote_player(
	peer_id: int,
	player_position: Vector2,
	player_direction: Vector2,
	player_length: int,
	player_alive: bool
) -> void:

	# لا ننشئ اللاعب المحلي كـ Remote
	if peer_id == multiplayer.get_unique_id():
		return

	if not remote_snakes.has(peer_id):

		var player_name := "لاعب"

		if Network != null:
			player_name = Network.get_player_name(
				peer_id
			)

		_create_remote_snake(
			peer_id,
			player_name,
			player_position
		)

	if not remote_snakes.has(peer_id):
		return

	var remote_snake = remote_snakes[
		peer_id
	]

	if not is_instance_valid(remote_snake):
		remote_snakes.erase(peer_id)
		return

	if remote_snake.has_method(
		"update_state"
	):

		remote_snake.update_state(
			player_position,
			player_direction,
			player_length,
			player_alive
		)


# =========================================================
# REMOTE PLAYER DEATH
# =========================================================

func remote_player_died(
	peer_id: int
) -> void:

	if not remote_snakes.has(peer_id):
		return

	var remote_snake = remote_snakes[
		peer_id
	]

	if not is_instance_valid(remote_snake):
		return

	if remote_snake.has_method("die"):
		remote_snake.die()


# =========================================================
# REMOTE PLAYER RESPAWN
# =========================================================

func remote_player_respawned(
	peer_id: int,
	player_position: Vector2
) -> void:

	if not remote_snakes.has(peer_id):

		var player_name := "لاعب"

		if Network != null:
			player_name = Network.get_player_name(
				peer_id
			)

		_create_remote_snake(
			peer_id,
			player_name,
			player_position
		)

	if not remote_snakes.has(peer_id):
		return

	var remote_snake = remote_snakes[
		peer_id
	]

	if not is_instance_valid(remote_snake):
		return

	if remote_snake.has_method(
		"respawn"
	):

		remote_snake.respawn(
			player_position
		)


# =========================================================
# PROCESS
# =========================================================

func _process(delta: float) -> void:

	if game_over:
		return

	if paused:
		return

	_update_camera()

	_check_food_collection()

	_send_network_state(delta)

	queue_redraw()


# =========================================================
# SEND NETWORK STATE
# =========================================================

func _send_network_state(
	delta: float
) -> void:

	if Network == null:
		return

	if not Network.is_network_connected():
		return

	if not is_instance_valid(snake):
		return

	network_state_timer += delta

	if network_state_timer < NETWORK_UPDATE_INTERVAL:
		return

	network_state_timer = 0.0

	var player_position := snake.global_position

	var player_direction := Vector2.RIGHT

	if snake.has_method(
		"get_direction"
	):
		player_direction = snake.get_direction()

	var player_length := 10

	if snake.has_method(
		"get_length"
	):
		player_length = snake.get_length()

	var player_alive := true

	if snake.has_method(
		"get_is_dead"
	):
		player_alive = not snake.get_is_dead()

	Network.broadcast_player_state(
		player_position,
		player_direction,
		player_length,
		player_alive
	)


# =========================================================
# CAMERA FOLLOW
# =========================================================

func _update_camera() -> void:

	if not is_instance_valid(
		snake
	):
		return

	if not is_instance_valid(
		camera
	):
		return

	camera.position = snake.position


# =========================================================
# SAFE SPAWN
# =========================================================

func _get_safe_spawn_position() -> Vector2:

	var center := MAP_SIZE / 2.0

	var spawn := center

	for i in range(30):

		var candidate := Vector2(
			rng.randf_range(
				MAP_BORDER + 300.0,
				MAP_SIZE.x -
				MAP_BORDER -
				300.0
			),

			rng.randf_range(
				MAP_BORDER + 300.0,
				MAP_SIZE.y -
				MAP_BORDER -
				300.0
			)
		)

		if candidate.distance_to(
			center
		) < SAFE_SPAWN_DISTANCE:
			continue

		spawn = candidate

		break

	return spawn


# =========================================================
# FOOD
# =========================================================

func _create_food() -> void:

	for old_food in foods:

		if is_instance_valid(
			old_food
		):
			old_food.queue_free()

	foods.clear()

	for i in range(
		FOOD_COUNT
	):
		_spawn_food()


func _spawn_food() -> void:

	var food := FoodVisual.new()

	food.position = _get_random_map_position()

	add_child(food)

	foods.append(food)


func _get_random_map_position() -> Vector2:

	return Vector2(
		rng.randf_range(
			MAP_BORDER + 50.0,
			MAP_SIZE.x -
			MAP_BORDER -
			50.0
		),

		rng.randf_range(
			MAP_BORDER + 50.0,
			MAP_SIZE.y -
			MAP_BORDER -
			50.0
		)
	)


# =========================================================
# FOOD COLLECTION
# =========================================================

func _check_food_collection() -> void:

	if not is_instance_valid(
		snake
	):
		return

	if snake.has_method(
		"get_is_dead"
	):

		if snake.get_is_dead():
			return

	for i in range(
		foods.size() - 1,
		-1,
		-1
	):

		var food := foods[i]

		if not is_instance_valid(
			food
		):

			foods.remove_at(i)

			continue

		var distance := snake.global_position.distance_to(
			food.global_position
		)

		if distance <= FOOD_COLLECT_DISTANCE:

			_collect_food(
				food,
				i
			)


# =========================================================
# COLLECT FOOD
# =========================================================

func _collect_food(
	food: Node2D,
	index: int
) -> void:

	score += 10

	round_coins += 1

	round_xp += 5

	if Global.has_method(
		"add_coins"
	):
		Global.add_coins(1)

	if Global.has_method(
		"add_experience"
	):
		Global.add_experience(5)

	if is_instance_valid(
		snake
	):

		if snake.has_method(
			"grow"
		):
			snake.grow(1)

	if is_instance_valid(
		food
	):
		food.queue_free()

	if index >= 0 and index < foods.size():
		foods.remove_at(index)

	_spawn_food()

	_update_ui()


# =========================================================
# UI
# =========================================================

func _create_ui() -> void:

	var canvas := CanvasLayer.new()

	canvas.name = "GameUI"

	add_child(canvas)

	# -----------------------------
	# TOP BAR
	# -----------------------------

	var top_panel := Panel.new()

	top_panel.position = Vector2(
		20,
		20
	)

	top_panel.size = Vector2(
		1240,
		80
	)

	canvas.add_child(
		top_panel
	)

	var style := StyleBoxFlat.new()

	style.bg_color = Color(
		0.025,
		0.03,
		0.04,
		0.90
	)

	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 
