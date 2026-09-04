extends Node2D

# =========================================================
# SNAKE ARAB ONLINE
# Step 6.6.5
# ربط دخول وخروج اللاعبين داخل المباراة
# =========================================================

const MAP_SIZE := Vector2(4000.0, 4000.0)

const FOOD_COUNT := 180
const FOOD_RADIUS := 10.0
const FOOD_COLLECTION_DISTANCE := 48.0

var local_snake: Node2D = null
var remote_snakes: Dictionary = {}

var foods: Array[Vector2] = []

var score: int = 0
var collected_coins: int = 0

var state_send_timer := 0.0
const STATE_SEND_INTERVAL := 0.05

var game_started := false
var game_over := false

var map_background: ColorRect
var camera: Camera2D

var score_label: Label
var coins_label: Label
var length_label: Label
var players_label: Label
var game_over_panel: Control


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	randomize()

	_create_map()
	_create_food()
	_create_ui()

	_connect_network_signals()

	_spawn_local_player()

	game_started = true

	_sync_existing_players()

	queue_redraw()


# =========================================================
# NETWORK SIGNALS
# =========================================================

func _connect_network_signals() -> void:

	if not Network:
		return

	if not Network.player_joined.is_connected(_on_player_joined):
		Network.player_joined.connect(_on_player_joined)

	if not Network.player_left.is_connected(_on_player_left):
		Network.player_left.connect(_on_player_left)

	if not Network.connected.is_connected(_on_network_connected):
		Network.connected.connect(_on_network_connected)


# =========================================================
# NETWORK CONNECTED
# =========================================================

func _on_network_connected() -> void:
	print("Network connected")

	await get_tree().create_timer(0.2).timeout

	_sync_existing_players()


# =========================================================
# SYNC EXISTING PLAYERS
# =========================================================

func _sync_existing_players() -> void:

	if not Network:
		return

	if Network.connected_players.is_empty():
		_update_players_count()
		return

	sync_network_players(Network.connected_players)


# =========================================================
# PLAYER JOINED
# =========================================================

func _on_player_joined(peer_id: int, player_data: Dictionary) -> void:

	if peer_id == multiplayer.get_unique_id():
		return

	_create_remote_snake(peer_id, player_data)

	_update_players_count()


# =========================================================
# PLAYER LEFT
# =========================================================

func _on_player_left(peer_id: int) -> void:

	_remove_remote_snake(peer_id)

	_update_players_count()


# =========================================================
# SYNC NETWORK PLAYERS
# =========================================================

func sync_network_players(players: Dictionary) -> void:

	if players == null:
		return

	var current_ids: Array[int] = []

	for key in players.keys():

		var peer_id := int(key)

		current_ids.append(peer_id)

		var player_data = players[key]

		if peer_id == multiplayer.get_unique_id():
			continue

		if remote_snakes.has(peer_id):
			continue

		if player_data is Dictionary:
			_create_remote_snake(peer_id, player_data)

	# حذف اللاعبين الذين لم يعودوا موجودين
	var existing_ids: Array = remote_snakes.keys()

	for existing_id in existing_ids:

		if not current_ids.has(int(existing_id)):
			_remove_remote_snake(int(existing_id))

	_update_players_count()


# =========================================================
# CREATE REMOTE SNAKE
# =========================================================

func _create_remote_snake(peer_id: int, player_data: Dictionary) -> void:

	if peer_id == multiplayer.get_unique_id():
		return

	if remote_snakes.has(peer_id):
		return

	var remote_scene := load("res://scripts/remote_snake.gd")

	if remote_scene == null:
		push_error("remote_snake.gd not found")
		return

	var remote_snake = remote_scene.new()

	if remote_snake == null:
		return

	remote_snake.name = "RemoteSnake_%s" % peer_id

	add_child(remote_snake)

	var player_name := "لاعب"

	if player_data.has("name"):
		player_name = str(player_data["name"])

	var spawn_position := Vector2(
		MAP_SIZE.x / 2.0,
		MAP_SIZE.y / 2.0
	)

	if player_data.has("spawn"):
		var spawn_value = player_data["spawn"]

		if spawn_value is Vector2:
			spawn_position = spawn_value

		elif spawn_value is Dictionary:
			spawn_position = Vector2(
				float(spawn_value.get("x", MAP_SIZE.x / 2.0)),
				float(spawn_value.get("y", MAP_SIZE.y / 2.0))
			)

	remote_snake.peer_id = peer_id
	remote_snake.player_name = player_name

	if remote_snake.has_method("set_target_position"):
		remote_snake.set_target_position(spawn_position)
	elif remote_snake.has_method("update_state"):
		remote_snake.update_state(
			spawn_position,
			Vector2.RIGHT,
			10,
			true
		)
	else:
		remote_snake.position = spawn_position

	remote_snakes[peer_id] = remote_snake

	print("Remote player created: ", peer_id, " - ", player_name)


# =========================================================
# REMOVE REMOTE SNAKE
# =========================================================

func _remove_remote_snake(peer_id: int) -> void:

	if not remote_snakes.has(peer_id):
		return

	var remote_snake = remote_snakes[peer_id]

	if is_instance_valid(remote_snake):
		remote_snake.queue_free()

	remote_snakes.erase(peer_id)

	print("Remote player removed: ", peer_id)


# =========================================================
# SERVER ASSIGNS LOCAL SPAWN
# =========================================================

func set_local_spawn(spawn_position: Vector2) -> void:

	if local_snake == null:
		return

	if not is_instance_valid(local_snake):
		return

	local_snake.position = spawn_position

	if local_snake.has_method("reset"):
		local_snake.reset()

	if camera:
		camera.position = spawn_position

	print("Local spawn assigned: ", spawn_position)


# =========================================================
# REMOTE PLAYER LEFT
# =========================================================

func remote_player_left(peer_id: int) -> void:

	_remove_remote_snake(peer_id)

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

	if peer_id == multiplayer.get_unique_id():
		return

	if not remote_snakes.has(peer_id):
		return

	var remote_snake = remote_snakes[peer_id]

	if not is_instance_valid(remote_snake):
		remote_snakes.erase(peer_id)
		return

	if remote_snake.has_method("update_state"):
		remote_snake.update_state(
			player_position,
			player_direction,
			player_length,
			player_alive
		)


# =========================================================
# REMOTE PLAYER DIED
# =========================================================

func remote_player_died(peer_id: int) -> void:

	if not remote_snakes.has(peer_id):
		return

	var remote_snake = remote_snakes[peer_id]

	if is_instance_valid(remote_snake):

		if remote_snake.has_method("die"):
			remote_snake.die()


# =========================================================
# REMOTE PLAYER RESPAWN
# =========================================================

func remote_player_respawned(
	peer_id: int,
	spawn_position: Vector2
) -> void:

	if not remote_snakes.has(peer_id):
		return

	var remote_snake = remote_snakes[peer_id]

	if is_instance_valid(remote_snake):

		if remote_snake.has_method("respawn"):
			remote_snake.respawn(spawn_position)


# =========================================================
# SPAWN LOCAL PLAYER
# =========================================================

func _spawn_local_player() -> void:

	var snake_scene := load("res://scenes/snake.tscn")

	if snake_scene == null:
		push_error("snake.tscn not found")
		return

	local_snake = snake_scene.instantiate()

	if local_snake == null:
		return

	local_snake.name = "LocalSnake"

	add_child(local_snake)

	var spawn_position := Vector2(
		MAP_SIZE.x / 2.0,
		MAP_SIZE.y / 2.0
	)

	if Network:

		var network_spawn = Network.get_player_spawn(
			multiplayer.get_unique_id()
		)

		if network_spawn != Vector2.ZERO:
			spawn_position = network_spawn

	local_snake.position = spawn_position

	if local_snake.has_method("setup"):
		local_snake.setup(
			Global.player_name if Global.player_name != "" else "لاعب",
			spawn_position
		)

	_create_camera()

	print("Local player spawned at: ", spawn_position)


# =========================================================
# CAMERA
# =========================================================

func _create_camera() -> void:

	camera = Camera2D.new()

	camera.position = local_snake.position

	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0

	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(MAP_SIZE.x)
	camera.limit_bottom = int(MAP_SIZE.y)

	camera.limit_smoothed = true

	local_snake.add_child(camera)


# =========================================================
# PROCESS
# =========================================================

func _process(delta: float) -> void:

	if not game_started:
		return

	if game_over:
		return

	_update_local_player(delta)

	_update_food_collection()

	_send_network_state(delta)

	_update_camera()

	_update_ui()

	queue_redraw()


# =========================================================
# LOCAL PLAYER
# =========================================================

func _update_local_player(delta: float) -> void:

	if local_snake == null:
		return

	if not is_instance_valid(local_snake):
		return

	if local_snake.has_method("get_is_dead"):

		if local_snake.get_is_dead():
			return


# =========================================================
# CAMERA FOLLOW
# =========================================================

func _update_camera() -> void:

	if camera == null:
		return

	if local_snake == null:
		return

	camera.position = Vector2.ZERO


# =========================================================
# SEND NETWORK STATE
# =========================================================

func _send_network_state(delta: float) -> void:

	if not Network:
		return

	if not multiplayer.has_multiplayer_peer():
		return

	state_send_timer += delta

	if state_send_timer < STATE_SEND_INTERVAL:
		return

	state_send_timer = 0.0

	if local_snake == null:
		return

	if not is_instance_valid(local_snake):
		return

	var position := local_snake.position
	var direction := Vector2.RIGHT
	var length := 10
	var alive := true

	if local_snake.has_method("get_direction"):
		direction = local_snake.get_direction()

	if local_snake.has_method("get_length"):
		length = local_snake.get_length()

	if local_snake.has_method("get_is_dead"):
		alive = not local_snake.get_is_dead()

	Network.broadcast_player_state(
		position,
		direction,
		length,
		alive
	)


# =========================================================
# FOOD
# =========================================================

func _create_food() -> void:

	foods.clear()

	for i in range(FOOD_COUNT):

		var position := Vector2(
			randf_range(100.0, MAP_SIZE.x - 100.0),
			randf_range(100.0, MAP_SIZE.y - 100.0)
		)

		foods.append(position)


func _update_food_collection() -> void:

	if local_snake == null:
		return

	if not is_instance_valid(local_snake):
		return

	for i in range(foods.size() - 1, -1, -1):

		var food_position := foods[i]

		if local_snake.position.distance_to(food_position) <= FOOD_COLLECTION_DISTANCE:

			_collect_food(i)


func _collect_food(index: int) -> void:

	if index < 0 or index >= foods.size():
		return

	foods.remove_at(index)

	score += 10
	collected_coins += 1

	if local_snake and local_snake.has_method("grow"):
		local_snake.grow()

	if Global:
		Global.add_coins(1)
		Global.add_experience(5)

	_spawn_new_food()


func _spawn_new_food() -> void:

	var new_position := Vector2(
		randf_range(100.0, MAP_SIZE.x - 100.0),
		randf_range(100.0, MAP_SIZE.y - 100.0)
	)

	foods.append(new_position)


# =========================================================
# PLAYER COUNT
# =========================================================

func _update_players_count() -> void:

	if players_label == null:
		return

	var count := 1 + remote_snakes.size()

	if Network and Network.connected_players.size() > count:
		count = Network.connected_players.size()

	players_label.text = "اللاعبون: %d" % count


# =========================================================
# LOCAL PLAYER DIED
# =========================================================

func snake_died(snake: Node2D, reason: String = "") -> void:

	if snake != local_snake:
		return

	game_over = true

	if Network:
		Network.broadcast_player_death()

	_show_game_over()


# =========================================================
# GAME OVER
# =========================================================

func _show_game_over() -> void:

	if game_over_panel == null:
		return

	game_over_panel.visible = true

	Global.last_score = score
	Global.last_coins = collected_coins

	if local_snake and local_snake.has_method("get_length"):
		Global.last_length = local_snake.get_length()

	Global.save_data()


# =========================================================
# MAP
# =========================================================

func _create_map() -> void:

	map_background = ColorRect.new()

	map_background.position = Vector2.ZERO
	map_background.size = MAP_SIZE

	map_background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(map_background)

	move_child(map_background, 0)


# =========================================================
# UI
# =========================================================

func _create_ui() -> void:

	var canvas := CanvasLayer.new()
	canvas.name = "GameUI"

	add_child(canvas)

	score_label = Label.new()
	score_label.position = Vector2(25, 20)
	score_label.text = "النقاط: 0"
	score_label.add_theme_font_size_override("font_size", 24)
	canvas.add_child(score_label)

	coins_label = Label.new()
	coins_label.position = Vector2(25, 55)
	coins_label.text = "العملات: 0"
	coins_label.add_theme_font_size_override("font_size", 22)
	canvas.add_child(coins_label)

	length_label = Label.new()
	length_label.position = Vector2(25, 90)
	length_label.text = "الطول: 10"
	length_label.add_theme_font_size_override("font_size", 22)
	canvas.add_child(length_label)

	players_label = Label.new()
	players_label.position = Vector2(1000, 20)
	players_label.text = "اللاعبون: 1"
	players_label.add_theme_font_size_override("font_size", 24)
	canvas.add_child(players_label)

	_create_game_over_ui(canvas)


# =========================================================
# GAME OVER UI
# =========================================================

func _create_game_over_ui(canvas: CanvasLayer) -> void:

	game_over_panel = Panel.new()

	game_over_panel.position = Vector2(440, 220)
	game_over_panel.size = Vector2(400, 260)

	game_over_panel.visible = false

	canvas.add_child(game_over_panel)

	var title := Label.new()

	title.position = Vector2(100, 30)
	title.text = "انتهت اللعبة"

	title.add_theme_font_size_override(
		"font_size",
		32
	)

	game_over_panel.add_child(title)

	var result := Label.new()

	result.name = "Result"

	result.position = Vector2(70, 90)
	result.text = "النقاط: 0\nالعملات: 0"

	result.add_theme_font_size_override(
		"font_size",
		22
	)

	game_over_panel.add_child(result)

	var restart_button := Button.new()

	restart_button.position = Vector2(100, 180)
	restart_button.size = Vector2(200, 50)

	restart_button.text = "إعادة اللعب"

	restart_button.pressed.connect(
		_restart_game
	)

	game_over_panel.add_child(
		restart_button
	)


# =========================================================
# RESTART
# =========================================================

func _restart_game() -> void:

	game_over = false

	score = 0
	collected_coins = 0

	if game_over_panel:
		game_over_panel.visible = false

	if local_snake:

		if local_snake.has_method("revive"):
			local_snake.revive()

		var spawn_position := Vector2(
			MAP_SIZE.x / 2.0,
			MAP_SIZE.y / 2.0
		)

		if Network:
			var network_spawn = Network.get_player_spawn(
				multiplayer.get_unique_id()
			)

			if network_spawn != Vector2.ZERO:
				spawn_position = network_spawn

		local_snake.position = spawn_position

	if Network:
		Network.broadcast_player_respawn(
			local_snake.position
		)

	_create_food()


# =========================================================
# DRAW
# =========================================================

func _draw() -> void:

	# خلفية الخريطة
	draw_rect(
		Rect2(Vector2.ZERO, MAP_SIZE),
		Color(0.055, 0.075, 0.065)
	)

	# شبكة
	var grid_size := 100

	for x in range(0, int(MAP_SIZE.x), grid_size):

		draw_line(
			Vector2(x, 0),
			Vector2(x, MAP_SIZE.y),
			Color(0.10, 0.13, 0.11, 0.5),
			1.0
		)

	for y in range(0, int(MAP_SIZE.y), grid_size):

		draw_line(
			Vector2(0, y),
			Vector2(MAP_SIZE.x, y),
			Color(0.10, 0.13, 0.11, 0.5),
			1.0
		)

	# حدود الخريطة
	draw_rect(
		Rect2(Vector2.ZERO, MAP_SIZE),
		Color(0.8, 0.65, 0.2),
		false,
		12.0
	)

	# الطعام
	for food_position in foods:

		draw_circle(
			food_position,
			FOOD_RADIUS,
			Color(1.0, 0.75, 0.15)
		)

		draw_circle(
			food_position,
			FOOD_RADIUS + 4,
			Color(1.0, 0.75, 0.15, 0.15)
		)


# =========================================================
# UI UPDATE
# =========================================================

func _update_ui() -> void:

	if score_label:
		score_label.text = "النقاط: %d" % score

	if coins_label:
		coins_label.text = "العملات: %d" % collected_coins

	if length_label and local_snake:

		var length := 10

		if local_snake.has_method("get_length"):
			length = local_snake.get_length()

		length_label.text = "الطول: %d" % length

	_update_players_count()
