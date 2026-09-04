extends Node2D

# =========================================================
# Snake Arab Online
# Main Game
# Step 6.6.8
# =========================================================

const MAP_SIZE := Vector2(
	4000.0,
	4000.0
)

const FOOD_COUNT := 180

const FOOD_RADIUS := 9.0

const FOOD_COLLECTION_DISTANCE := 48.0

# =========================================================
# PLAYER
# =========================================================

var snake: Node2D

var remote_snakes: Dictionary = {}

# =========================================================
# LOCAL FOOD
# =========================================================

var foods: Array[Node2D] = []

# =========================================================
# NETWORK FOOD
# =========================================================

var network_foods: Dictionary = {}

var network_loot: Dictionary = {}

var network_food_nodes: Dictionary = {}

var network_loot_nodes: Dictionary = {}

# =========================================================
# GAME STATE
# =========================================================

var score := 0

var game_coins := 0

var game_xp := 0

var game_over := false

var paused := false

var state_timer := 0.0

# =========================================================
# SPAWN
# =========================================================

var local_spawn_position := Vector2(
	2000.0,
	2000.0
)

# =========================================================
# CAMERA
# =========================================================

var camera: Camera2D

# =========================================================
# UI
# =========================================================

var score_label: Label

var length_label: Label

var players_label: Label

var coins_label: Label

var pause_button: Button

var game_over_panel: Panel

# =========================================================
# READY
# =========================================================

func _ready() -> void:

	randomize()

	_create_background()

	_create_local_player()

	_create_ui()

	_connect_network_signals()

	_sync_existing_players()


# =========================================================
# PROCESS
# =========================================================

func _process(delta: float) -> void:

	if snake == null:
		return

	if not game_over and not paused:

		_check_food_collision()

		_check_map_collision()

		_send_network_state(delta)

	_update_ui()

	queue_redraw()


# =========================================================
# NETWORK SIGNALS
# =========================================================

func _connect_network_signals() -> void:

	var network := get_node_or_null(
		"/root/Network"
	)

	if network == null:
		return

	if not network.player_joined.is_connected(
		_on_network_player_joined
	):

		network.player_joined.connect(
			_on_network_player_joined
		)

	if not network.player_left.is_connected(
		_on_network_player_left
	):

		network.player_left.connect(
			_on_network_player_left
	)

	if not network.player_died.is_connected(
		_on_network_player_died
	):

		network.player_died.connect(
			_on_network_player_died
	)

	if not network.player_respawned.is_connected(
		_on_network_player_respawned
	):

		network.player_respawned.connect(
			_on_network_player_respawned
	)


# =========================================================
# BACKGROUND
# =========================================================

func _create_background() -> void:

	var background := ColorRect.new()

	background.position = Vector2.ZERO

	background.size = MAP_SIZE

	background.color = Color(
		"#111827"
	)

	background.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	add_child(
		background
	)

	move_child(
		background,
		0
	)


# =========================================================
# DRAW MAP
# =========================================================

func _draw() -> void:

	draw_rect(
		Rect2(
			Vector2.ZERO,
			MAP_SIZE
		),
		Color("#263449"),
		false,
		12.0
	)

	var grid_size := 100.0

	var x := 0.0

	while x <= MAP_SIZE.x:

		draw_line(
			Vector2(x, 0),
			Vector2(
				x,
				MAP_SIZE.y
			),
			Color(
				0.12,
				0.16,
				0.22,
				0.35
			),
			2.0
		)

		x += grid_size

	var y := 0.0

	while y <= MAP_SIZE.y:

		draw_line(
			Vector2(0, y),
			Vector2(
				MAP_SIZE.x,
				y
			),
			Color(
				0.12,
				0.16,
				0.22,
				0.35
			),
			2.0
		)

		y += grid_size

	# Center safe zone

	draw_circle(
		MAP_SIZE / 2.0,
		180.0,
		Color(
			0.1,
			0.35,
			0.25,
			0.15
		)
	)

	draw_arc(
		MAP_SIZE / 2.0,
		180.0,
		0.0,
		TAU,
		64,
		Color(
			0.2,
			0.9,
			0.55,
			0.35
		),
		3.0
	)


# =========================================================
# LOCAL PLAYER
# =========================================================

func _create_local_player() -> void:

	var snake_scene := load(
		"res://scenes/snake.tscn"
	)

	if snake_scene == null:

		push_error(
			"Snake scene not found"
		)

		return

	snake = snake_scene.instantiate()

	snake.position = (
		local_spawn_position
	)

	add_child(
		snake
	)

	if snake.has_method(
		"setup"
	):

		snake.setup(
			Global.player_name
		)

	_create_camera()


# =========================================================
# CAMERA
# =========================================================

func _create_camera() -> void:

	if snake == null:
		return

	camera = Camera2D.new()

	camera.name = "PlayerCamera"

	camera.position = Vector2.ZERO

	camera.position_smoothing_enabled = true

	camera.position_smoothing_speed = 8.0

	camera.limit_left = 0

	camera.limit_top = 0

	camera.limit_right = int(
		MAP_SIZE.x
	)

	camera.limit_bottom = int(
		MAP_SIZE.y
	)

	snake.add_child(
		camera
	)


# =========================================================
# SET LOCAL SPAWN
# =========================================================

func set_local_spawn(
	spawn_position: Vector2
) -> void:

	local_spawn_position = spawn_position

	if snake == null:
		return

	snake.global_position = (
		spawn_position
	)

	if snake.has_method(
		"revive"
	):

		snake.revive()

	game_over = false

	score = 0


# =========================================================
# NETWORK STATE
# =========================================================

func _send_network_state(
	delta: float
) -> void:

	state_timer += delta

	if state_timer < 0.05:
		return

	state_timer = 0.0

	var network := get_node_or_null(
		"/root/Network"
	)

	if network == null:
		return

	if not network.has_method(
		"broadcast_player_state"
	):

		return

	var position := snake.global_position

	var direction := Vector2.RIGHT

	if "direction" in snake:
		direction = snake.direction

	var length := 10

	if snake.has_method(
		"get_length"
	):

		length = snake.get_length()

	var alive := true

	if snake.has_method(
		"get_is_alive"
	):

		alive = snake.get_is_alive()

	var body_points: Array = []

	if snake.has_method(
		"get_body_points"
	):

		body_points = snake.get_body_points()

	network.broadcast_player_state(
		position,
		direction,
		length,
		alive,
		body_points
	)


# =========================================================
# SYNC EXISTING PLAYERS
# =========================================================

func _sync_existing_players() -> void:

	var network := get_node_or_null(
		"/root/Network"
	)

	if network == null:
		return

	if not network.is_host:
		return

	for peer_id in network.connected_players.keys():

		if peer_id == multiplayer.get_unique_id():
			continue

		var data: Dictionary = (
			network.connected_players[
				peer_id
			]
		)

		_create_remote_snake(
			peer_id,
			str(
				data.get(
					"name",
					"لاعب"
				)
			),
			data.get(
				"spawn",
				Vector2.ZERO
			)
		)


# =========================================================
# NETWORK PLAYER JOINED
# =========================================================

func _on_network_player_joined(
	peer_id: int,
	new_name: String
) -> void:

	var network := get_node_or_null(
		"/root/Network"
	)

	var spawn := Vector2.ZERO

	if network and network.player_spawns.has(
		peer_id
	):

		spawn = network.player_spawns[
			peer_id
		]

	_create_remote_snake(
		peer_id,
		new_name,
		spawn
	)


func network_player_joined(
	peer_id: int,
	new_name: String,
	spawn_position: Vector2
) -> void:

	_create_remote_snake(
		peer_id,
		new_name,
		spawn_position
	)


# =========================================================
# CREATE REMOTE SNAKE
# =========================================================

func _create_remote_snake(
	peer_id: int,
	new_name: String,
	spawn_position: Vector2
) -> void:

	if peer_id == multiplayer.get_unique_id():
		return

	if remote_snakes.has(
		peer_id
	):

		var existing = remote_snakes[
			peer_id
		]

		if is_instance_valid(
			existing
		):

			if existing.has_method(
				"set_player_name"
			):

				existing.set_player_name(
					new_name
				)

			return

		remote_snakes.erase(
			peer_id
		)

	var script_resource := load(
		"res://scripts/remote_snake.gd"
	)

	if script_resource == null:

		push_error(
			"remote_snake.gd not found"
		)

		return

	var remote := Node2D.new()

	remote.set_script(
		script_resource
	)

	remote.position = (
		spawn_position
	)

	add_child(
		remote
	)

	if remote.has_method(
		"setup"
	):

		remote.setup(
			peer_id,
			new_name,
			spawn_position
		)

	remote_snakes[
		peer_id
	] = remote


# =========================================================
# UPDATE REMOTE PLAYER
# =========================================================

func update_remote_player(
	peer_id: int,
	player_position: Vector2,
	player_direction: Vector2,
	player_length: int,
	player_alive: bool,
	player_body: Array = []
) -> void:

	if peer_id == multiplayer.get_unique_id():
		return

	if not remote_snakes.has(
		peer_id
	):

		_create_remote_snake(
			peer_id,
			"لاعب",
			player_position
		)

	if not remote_snakes.has(
		peer_id
	):

		return

	var remote = remote_snakes[
		peer_id
	]

	if not is_instance_valid(
		remote
	):

		remote_snakes.erase(
			peer_id
		)

		return

	# New remote snake supports body sync
	if remote.has_method(
		"update_state"
	):

		remote.update_state(
			player_position,
			player_direction,
			player_length,
			player_alive,
			player_body
		)


# =========================================================
# REMOTE NAME
# =========================================================

func update_remote_player_name(
	peer_id: int,
	new_name: String
) -> void:

	if not remote_snakes.has(
		peer_id
	):

		return

	var remote = remote_snakes[
		peer_id
	]

	if is_instance_valid(
		remote
	):

		if remote.has_method(
			"set_player_name"
		):

			remote.set_player_name(
				new_name
			)


# =========================================================
# PLAYER LEFT
# =========================================================

func _on_network_player_left(
	peer_id: int
) -> void:

	remote_player_left(
		peer_id
	)


func remote_player_left(
	peer_id: int
) -> void:

	if not remote_snakes.has(
		peer_id
	):

		return

	var remote = remote_snakes[
		peer_id
	]

	if is_instance_valid(
		remote
	):

		remote.queue_free()

	remote_snakes.erase(
		peer_id
	)


# =========================================================
# NETWORK PLAYERS SYNC
# =========================================================

func sync_network_players(
	players: Dictionary
) -> void:

	for peer_id in players.keys():

		if peer_id == multiplayer.get_unique_id():
			continue

		var data: Dictionary = players[
			peer_id
		]

		_create_remote_snake(
			peer_id,
			str(
				data.get(
					"name",
					"لاعب"
				)
			),
			data.get(
				"spawn",
				Vector2.ZERO
			)
		)


# =========================================================
# PLAYER DIED
# =========================================================

func _on_network_player_died(
	peer_id: int,
	killer_id: int,
	death_position: Vector2,
	reward: int
) -> void:

	network_player_died(
		peer_id,
		killer_id,
		death_position,
		reward
	)


func network_player_died(
	peer_id: int,
	killer_id: int,
	death_position: Vector2,
	reward: int
) -> void:

	# Local player died
	if peer_id == multiplayer.get_unique_id():

		if snake:

			if snake.has_method(
				"die"
			):

				snake.die(
					"اصطدمت بثعبان آخر"
				)

		game_over = true

		_show_game_over()

		return

	# Remote player died
	if remote_snakes.has(
		peer_id
	):

		var remote = remote_snakes[
			peer_id
		]

		if is_instance_valid(
			remote
		):

			if remote.has_method(
				"die"
			):

				remote.die()


# =========================================================
# PLAYER RESPAWNED
# =========================================================

func _on_network_player_respawned(
	peer_id: int,
	spawn_position: Vector2
) -> void:

	network_player_respawned(
		peer_id,
		spawn_position
	)


func network_player_respawned(
	peer_id: int,
	spawn_position: Vector2
) -> void:

	if peer_id == multiplayer.get_unique_id():

		if snake:

			snake.global_position = (
				spawn_position
			)

			if snake.has_method(
				"revive"
			):

				snake.revive()

		game_over = false

		if game_over_panel:

			game_over_panel.queue_free()

			game_over_panel = null

		return

	if remote_snakes.has(
		peer_id
	):

		var remote = remote_snakes[
			peer_id
		]

		if is_instance_valid(
			remote
		):

			if remote.has_method(
				"respawn"
			):

				remote.respawn(
					spawn_position
				)


# =========================================================
# LOCAL FOOD
# =========================================================

func _create_food() -> void:

	for i in range(
		FOOD_COUNT
	):

		_spawn_food()


func _spawn_food() -> void:

	var food := Node2D.new()

	food.position = Vector2(
		randf_range(
			100.0,
			MAP_SIZE.x - 100.0
		),
		randf_range(
			100.0,
			MAP_SIZE.y - 100.0
		)
	)

	food.set_meta(
		"radius",
		FOOD_RADIUS
	)

	food.set_meta(
		"value",
		10
	)

	add_child(
		food
	)

	foods.append(
		food
	)

	var visual := FoodVisual.new()

	visual.radius = FOOD_RADIUS

	food.add_child(
		visual
	)


# =========================================================
# LOCAL FOOD COLLISION
# =========================================================

func _check_food_collision() -> void:

	if snake == null:
		return

	var head_position := (
		snake.global_position
	)

	for food in foods.duplicate():

		if not is_instance_valid(
			food
		):

			foods.erase(
				food
			)

			continue

		if head_position.distance_to(
			food.global_position
		) < 30.0:

			var value := int(
				food.get_meta(
					"value",
					10
				)
			)

			score += value

			game_coins += 5

			game_xp += 2

			if snake.has_method(
				"grow"
			):

				snake.grow(
					1
				)

			foods.erase(
				food
			)

			food.queue_free()

			_spawn_food()


# =========================================================
# MAP COLLISION
# =========================================================

func _check_map_collision() -> void:

	if snake == null:
		return

	var pos := snake.global_position

	if (
		pos.x < 30.0
		or pos.y < 30.0
		or pos.x > MAP_SIZE.x - 30.0
		or pos.y > MAP_SIZE.y - 30.0
	):

		_game_over()


# =========================================================
# NETWORK FOOD
# =========================================================

func network_food_spawned(
	food_id: int,
	position: Vector2,
	value: int,
	coins: int,
	xp: int
) -> void:

	network_foods[
		food_id
	] = {
		"position": position,
		"value": value,
		"coins": coins,
		"xp": xp
	}

	_create_single_network_food(
		food_id,
		position
	)


# =========================================================
# CREATE NETWORK FOOD VISUAL
# =========================================================

func _create_single_network_food(
	food_id: int,
	position: Vector2
) -> void:

	if network_food_nodes.has(
		food_id
	):

		return

	var food := Node2D.new()

	food.position = position

	add_child(
		food
	)

	var script_resource := load(
		"res://scripts/network_food_visual.gd"
	)

	if script_resource:

		food.set_script(
			script_resource
		)

	network_food_nodes[
		food_id
	] = food


# =========================================================
# NETWORK FOOD COLLECTED
# =========================================================

func network_food_collected(
	food_id: int,
	collector_id: int,
	value: int,
	coins: int,
	xp: int
) -> void:

	network_foods.erase(
		food_id
	)

	if network_food_nodes.has(
		food_id
	):

		var node = network_food_nodes[
			food_id
		]

		if is_instance_valid(
			node
		):

			node.queue_free()

	network_food_nodes.erase(
		food_id
	)

	# Reward local player
	if collector_id == multiplayer.get_unique_id():

		score += value

		game_coins += coins

		game_xp += xp

		if snake and snake.has_method(
			"grow"
		):

			snake.grow(
				1
			)


# =========================================================
# NETWORK LOOT
# =========================================================

func network_loot_spawned(
	loot_id: int,
	position: Vector2,
	value: int,
	coins: int,
	xp: int
) -> void:

	network_loot[
		loot_id
	] = {
		"position": position,
		"value": value,
		"coins": coins,
		"xp": xp
	}

	_create_single_network_loot(
		loot_id,
		position
	)


# =========================================================
# CREATE NETWORK LOOT VISUAL
# =========================================================

func _create_single_network_loot(
	loot_id: int,
	position: Vector2
) -> void:

	if network_loot_nodes.has(
		loot_id
	):

		return

	var loot_node := Node2D.new()

	loot_node.position = position

	add_child(
		loot_node
	)

	var script_resource := load(
		"res://scripts/network_loot_visual.gd"
	)

	if script_resource:

		loot_node.set_script(
			script_resource
		)

	network_loot_nodes[
		loot_id
	] = loot_node


# =========================================================
# NETWORK LOOT COLLECTED
# =========================================================

func network_loot_collected(
	loot_id: int,
	collector_id: int,
	value: int,
	coins: int,
	xp: int
) -> void:

	network_loot.erase(
		loot_id
	)

	if network_loot_nodes.has(
		loot_id
	):

		var node = network_loot_nodes[
			loot_id
		]

		if is_instance_valid(
			node
		):

			node.queue_free()

	network_loot_nodes.erase(
		loot_id
	)

	if collector_id == multiplayer.get_unique_id():

		score += value

		game_coins += coins

		game_xp += xp

		if snake and snake.has_method(
			"grow"
		):

			snake.grow(
				1
			)


# =========================================================
# NETWORK LOOT REMOVED
# =========================================================

func network_loot_removed(
	loot_id: int
) -> void:

	network_loot.erase(
		loot_id
	)

	if network_loot_nodes.has(
		loot_id
	):

		var node = network_loot_nodes[
			loot_id
		]

		if is_instance_valid(
			node
		):

			node.queue_free()

	network_loot_nodes.erase(
		loot_id
	)


# =========================================================
# UI
# =========================================================

func _create_ui() -> void:

	var canvas := CanvasLayer.new()

	canvas.name = "GameUI"

	add_child(
		canvas
	)

	var top_bar := Panel.new()

	top_bar.position = Vector2(
		20,
		20
	)

	top_bar.size = Vector2(
		390,
		170
	)

	canvas.add_child(
		top_bar
	)

	score_label = Label.new()

	score_label.position = Vector2(
		20,
		12
	)

	score_label.size = Vector2(
		350,
		35
	)

	score_label.add_theme_font_size_override(
		"font_size",
		26
	)

	top_bar.add_child(
		score_label
	)

	length_label = Label.new()

	length_label.position = Vector2(
		20,
		52
	)

	length_label.size = Vector2(
		350,
		35
	)

	length_label.add_theme_font_size_override(
		"font_size",
		21
	)

	top_bar.add_child(
		length_label
	)

	coins_label = Label.new()

	coins_label.position = Vector2(
		20,
		90
	)

	coins_label.size = Vector2(
		350,
		30
	)

	coins_label.add_theme_font_size_override(
		"font_size",
		19
	)

	top_bar.add_child(
		coins_label
	)

	players_label = Label.new()

	players_label.position = Vector2(
		20,
		125
	)

	players_label.size = Vector2(
		350,
		30
	)

	players_label.add_theme_font_size_override(
		"font_size",
		18
	)

	top_bar.add_child(
		players_label
	)

	# Pause
	pause_button = Button.new()

	pause_button.position = Vector2(
		1110,
		25
	)

	pause_button.size = Vector2(
		140,
		60
	)

	pause_button.text = "إيقاف"

	pause_button.pressed.connect(
		_toggle_pause
	)

	canvas.add_child(
		pause_button
	)

	# Exit
	var exit_button := Button.new()

	exit_button.position = Vector2(
		1110,
		95
	)

	exit_button.size = Vector2(
		140,
		55
	)

	exit_button.text = "خروج"

	exit_button.pressed.connect(
		_back_to_lobby
	)

	canvas.add_child(
		exit_button
	)


# =========================================================
# UPDATE UI
# =========================================================

func _update_ui() -> void:

	if score_label:

		score_label.text = (
			"النقاط: %d" %
			score
		)

	if length_label and snake:

		var length := 10

		if snake.has_method(
			"get_length"
		):

			length = snake.get_length()

		length_label.text = (
			"الطول: %d" %
			length
		)

	if coins_label:

		coins_label.text = (
			"💰 العملات: %d" %
			game_coins
		)

	if players_label:

		var network := get_node_or_null(
			"/root/Network"
		)

		var count := 1

		if network:

			count = network.get_player_count()

		players_label.text = (
			"👥 اللاعبون: %d" %
			count
		)


# =========================================================
# PAUSE
# =========================================================

func _toggle_pause() -> void:

	paused = not paused

	if pause_button:

		pause_button.text = (
			"متابعة"
			if paused
			else
			"إيقاف"
		)


# =========================================================
# GAME OVER
# =========================================================

func _game_over() -> void:

	if game_over:
		return

	game_over = true

	if snake:

		if snake.has_method(
			"die"
		):

			snake.die(
				"اصطدمت بحدود الخريطة"
			)

	_show_game_over()


# =========================================================
# GAME OVER PANEL
# =========================================================

func _show_game_over() -> void:

	var canvas := get_node_or_null(
		"GameUI"
	)

	if canvas == null:
		return

	if game_over_panel:

		return

	game_over_panel = Panel.new()

	game_over_panel.position = Vector2(
		390,
		180
	)

	game_over_panel.size = Vector2(
		500,
		340
	)

	canvas.add_child(
		game_over_panel
	)

	var title := Label.new()

	title.position = Vector2(
		30,
		25
	)

	title.size = Vector2(
		440,
		60
	)

	title.text = "انتهت اللعبة"

	title.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	title.add_theme_font_size_override(
		"font_size",
		40
	)

	game_over_panel.add_child(
		title
	)

	var result := Label.new()

	result.position = Vector2(
		30,
		100
	)

	result.size = Vector2(
		440,
		90
	)

	result.text = (
		"النقاط: %d\nالعملات: %d" %
		[
			score,
			game_coins
		]
	)

	result.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	result.add_theme_font_size_override(
		"font_size",
		25
	)

	game_over_panel.add_child(
		result
	)

	var restart := Button.new()

	restart.position = Vector2(
		80,
		210
	)

	restart.size = Vector2(
		340,
		55
	)

	restart.text = "العب مرة أخرى"

	restart.pressed.connect(
		_restart_game
	)

	game_over_panel.add_child(
		restart
	)


# =========================================================
# RESTART
# =========================================================

func _restart_game() -> void:

	var network := get_node_or_null(
		"/root/Network"
	)

	if network and network.has_method(
		"request_respawn"
	):

		network.request_respawn()

	else:

		get_tree().reload_current_scene()


# =========================================================
# BACK TO LOBBY
# =========================================================

func _back_to_lobby() -> void:

	var network := get_node_or_null(
		"/root/Network"
	)

	if network:

		network.close_connection()

	get_tree().change_scene_to_file(
		"res://scenes/lobby.tscn"
	)


# =========================================================
# NETWORK PLAYER JOINED
# =========================================================

func _on_network_player_joined(
	peer_id: int,
	new_name: String
) -> void:

	# Handled through network_player_joined
	pass


# =========================================================
# NETWORK PLAYER LEFT
# =========================================================

func _on_network_player_left(
	peer_id: int
) -> void:

	remote_player_left(
		peer_id
	)


# =========================================================
# NETWORK PLAYER DIED
# =========================================================

func _on_network_player_died(
	peer_id: int,
	killer_id: int,
	death_position: Vector2,
	reward: int
) -> void:

	network_player_died(
		peer_id,
		killer_id,
		death_position,
		reward
	)


# =========================================================
# NETWORK PLAYER RESPAWN
# =========================================================

func _on_network_player_respawned(
	peer_id: int,
	spawn_position: Vector2
) -> void:

	network_player_respawned(
		peer_id,
		spawn_position
	)


# =========================================================
# FOOD VISUAL
# =========================================================

class FoodVisual extends Node2D:

	var radius := 9.0

	var pulse := 0.0

	func _process(delta: float) -> void:

		pulse += delta * 4.0

		queue_redraw()


	func _draw() -> void:

		var scale_value := (
			1.0 +
			sin(pulse) * 0.08
		)

		draw_circle(
			Vector2.ZERO,
			radius * scale_value + 3.0,
			Color(
				0.0,
				0.0,
				0.0,
				0.18
			)
		)

		draw_circle(
			Vector2.ZERO,
			radius * scale_value,
			Color("#FACC15")
		)

		draw_circle(
			Vector2(
				-3,
				-3
			),
			radius * 0.3,
			Color.WHITE
		)
