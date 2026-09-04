extends Node2D

# ============================================================
# Snake Arab Online
# Game Controller
# Step 6.6.9
# نظام الموت والقتل والجوائز
# ============================================================

const MAP_SIZE := Vector2(
	4000.0,
	4000.0
)

const FOOD_COUNT := 180
const FOOD_RADIUS := 9.0

const LOCAL_STATE_INTERVAL := 0.05

var snake: Node2D

var foods: Array[Node2D] = []

var remote_snakes: Dictionary = {}

var network_foods: Dictionary = {}
var network_loot: Dictionary = {}

var network_food_nodes: Dictionary = {}
var network_loot_nodes: Dictionary = {}


# ============================================================
# Game state
# ============================================================

var score := 0
var game_over := false
var paused := false

var kills := 0
var deaths := 0

var last_killer_id := -1

var state_timer := 0.0

var respawn_timer := 0.0
var can_respawn := false

const RESPAWN_DELAY := 2.5


# ============================================================
# UI
# ============================================================

var score_label: Label
var length_label: Label
var kills_label: Label
var players_label: Label

var pause_button: Button
var game_over_panel: Panel

var notification_label: Label

var camera: Camera2D


# ============================================================
# Ready
# ============================================================

func _ready() -> void:

	add_to_group("game")

	randomize()

	_create_background()

	_create_food()

	_create_local_player()

	_create_ui()

	_connect_network()

	queue_redraw()


# ============================================================
# Network connections
# ============================================================

func _connect_network() -> void:

	var network := get_node_or_null(
		"/root/Network"
	)

	if network == null:
		return

	if network.has_signal(
		"players_synced_signal"
	):

		network.players_synced_signal.connect(
			_on_players_synced
		)

	if network.has_signal(
		"player_joined_signal"
	):

		network.player_joined_signal.connect(
			_on_player_joined
		)

	if network.has_signal(
		"player_left_signal"
	):

		network.player_left_signal.connect(
			_on_player_left
		)

	if network.has_signal(
		"player_died_signal"
	):

		network.player_died_signal.connect(
			_on_player_died
		)

	if network.has_signal(
		"player_respawned_signal"
	):

		network.player_respawned_signal.connect(
			_on_player_respawned
		)

	if network.has_signal(
		"food_spawned_signal"
	):

		network.food_spawned_signal.connect(
			_on_food_spawned
		)

	if network.has_signal(
		"loot_spawned_signal"
	):

		network.loot_spawned_signal.connect(
			_on_loot_spawned
		)

	if network.has_signal(
		"food_collected_signal"
	):

		network.food_collected_signal.connect(
			_on_food_collected
		)

	if network.has_signal(
		"loot_collected_signal"
	):

		network.loot_collected_signal.connect(
			_on_loot_collected
		)


# ============================================================
# Process
# ============================================================

func _process(delta: float) -> void:

	if snake == null:
		return

	if game_over:

		if can_respawn:

			respawn_timer += delta

			if respawn_timer >= RESPAWN_DELAY:

				can_respawn = false

				_request_respawn()

		_update_ui()

		queue_redraw()

		return

	if paused:

		_update_ui()

		queue_redraw()

		return

	state_timer += delta

	if state_timer >= LOCAL_STATE_INTERVAL:

		state_timer = 0.0

		_send_local_state()

	_check_local_map_collision()

	_update_camera()

	_update_ui()

	queue_redraw()


# ============================================================
# Background
# ============================================================

func _create_background() -> void:

	var background := ColorRect.new()

	background.position = Vector2.ZERO

	background.size = MAP_SIZE

	background.color = Color(
		"#111827"
	)

	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(background)

	move_child(
		background,
		0
	)


# ============================================================
# Draw map
# ============================================================

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
			Vector2(x, MAP_SIZE.y),
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
			Vector2(MAP_SIZE.x, y),
			Color(
				0.12,
				0.16,
				0.22,
				0.35
			),
			2.0
		)

		y += grid_size


# ============================================================
# Local player
# ============================================================

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

	var network := get_node_or_null(
		"/root/Network"
	)

	var spawn_position := MAP_SIZE / 2.0

	if network != null:

		if network.is_host:

			spawn_position = network.players.get(
				multiplayer.get_unique_id(),
				{}
			).get(
				"position",
				spawn_position
			)

	snake.position = spawn_position

	add_child(snake)

	if snake.has_method("setup"):

		var player_name := Global.player_name

		if player_name.is_empty():

			player_name = "لاعب"

		snake.setup(
			player_name
		)

	_create_camera()


# ============================================================
# Camera
# ============================================================

func _create_camera() -> void:

	if snake == null:
		return

	camera = Camera2D.new()

	camera.name = "GameCamera"

	camera.position = Vector2.ZERO

	camera.position_smoothing_enabled = true

	camera.position_smoothing_speed = 8.0

	camera.limit_left = 0

	camera.limit_top = 0

	camera.limit_right = int(MAP_SIZE.x)

	camera.limit_bottom = int(MAP_SIZE.y)

	snake.add_child(camera)


func _update_camera() -> void:

	if camera == null:
		return

	if snake == null:
		return

	camera.position = Vector2.ZERO


# ============================================================
# Local food fallback
# ============================================================

func _create_food() -> void:

	for i in range(FOOD_COUNT):

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

	add_child(food)

	foods.append(food)

	var visual := FoodVisual.new()

	visual.radius = FOOD_RADIUS

	food.add_child(visual)


# ============================================================
# Local food collision
# ============================================================

func _check_food_collision() -> void:

	if snake == null:
		return

	var head_position := snake.global_position

	for food in foods.duplicate():

		if not is_instance_valid(food):

			foods.erase(food)

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

			if snake.has_method("grow"):

				snake.grow(1)

			foods.erase(food)

			food.queue_free()

			_spawn_food()


# ============================================================
# Map collision
# ============================================================

func _check_local_map_collision() -> void:

	if snake == null:
		return

	if not snake.has_method(
		"get_is_alive"
	):
		return

	if not snake.get_is_alive():
		return

	var pos := snake.global_position

	if (
		pos.x < 30.0
		or pos.y < 30.0
		or pos.x > MAP_SIZE.x - 30.0
		or pos.y > MAP_SIZE.y - 30.0
	):

		if snake.has_method("die"):

			snake.die(
				"خرجت من حدود الخريطة"
			)


# ============================================================
# Send local state
# ============================================================

func _send_local_state() -> void:

	if snake == null:
		return

	var network := get_node_or_null(
		"/root/Network"
	)

	if network == null:
		return

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

	network.broadcast_player_state(
		snake.global_position,
		direction,
		length,
		alive
	)


# ============================================================
# Players synced
# ============================================================

func _on_players_synced(
	players: Dictionary
) -> void:

	sync_network_players(
		players
	)


func sync_network_players(
	players: Dictionary
) -> void:

	var local_id := multiplayer.get_unique_id()

	for peer_id in players.keys():

		var id := int(peer_id)

		var data: Dictionary = players[peer_id]

		if id == local_id:

			if snake != null:

				if data.has("position"):

					snake.global_position = data[
						"position"
					]

			continue

		_create_or_update_remote_snake(
			id,
			data
		)

	# إزالة اللاعبين الذين خرجوا
	var active_ids := {}

	for peer_id in players.keys():

		active_ids[int(peer_id)] = true

	for peer_id in remote_snakes.keys():

		if not active_ids.has(
			int(peer_id)
		):

			_remove_remote_snake(
				int(peer_id)
			)

	_update_players_count()


# ============================================================
# Player joined
# ============================================================

func _on_player_joined(
	peer_id: int,
	player_name: String
) -> void:

	if peer_id == multiplayer.get_unique_id():
		return

	_show_notification(
		"انضم اللاعب %s" % player_name
	)


# ============================================================
# Player left
# ============================================================

func _on_player_left(
	peer_id: int
) -> void:

	remote_player_left(
		peer_id
	)

	_show_notification(
		"غادر لاعب المباراة"
	)


func remote_player_left(
	peer_id: int
) -> void:

	_remove_remote_snake(
		peer_id
	)

	_update_players_count()


# ============================================================
# Create/update remote snake
# ============================================================

func _create_or_update_remote_snake(
	peer_id: int,
	data: Dictionary
) -> void:

	var player_name := str(
		data.get(
			"name",
			"لاعب"
		)
	)

	var position := data.get(
		"position",
		Vector2.ZERO
	)

	var direction := data.get(
		"direction",
		Vector2.RIGHT
	)

	var length := int(
		data.get(
			"length",
			10
		)
	)

	var alive := bool(
		data.get(
			"alive",
			true
		)
	)

	if not remote_snakes.has(peer_id):

		_create_remote_snake(
			peer_id,
			player_name,
			position
		)

	var remote = remote_snakes.get(
		peer_id
	)

	if remote == null:
		return

	if remote.has_method(
		"set_player_name"
	):

		remote.set_player_name(
			player_name
		)

	if remote.has_method(
		"update_state"
	):

		remote.update_state(
			position,
			direction,
			length,
			alive
		)

	_update_players_count()


# ============================================================
# Create remote snake
# ============================================================

func _create_remote_snake(
	peer_id: int,
	player_name: String,
	start_position: Vector2
) -> void:

	if remote_snakes.has(peer_id):
		return

	var scene := load(
		"res://scenes/snake.tscn"
	)

	if scene == null:
		return

	var remote = scene.instantiate()

	remote.name = "RemoteSnake_%s" % peer_id

	remote.position = start_position

	add_child(remote)

	if remote.has_method(
		"setup"
	):

		remote.setup(
			player_name
		)

	remote_snakes[peer_id] = remote


# ============================================================
# Remove remote snake
# ============================================================

func _remove_remote_snake(
	peer_id: int
) -> void:

	if not remote_snakes.has(peer_id):
		return

	var remote = remote_snakes[peer_id]

	if is_instance_valid(remote):

		remote.queue_free()

	remote_snakes.erase(
		peer_id
	)


# ============================================================
# Update remote player
# ============================================================

func update_remote_player(
	peer_id: int,
	new_position: Vector2,
	new_direction: Vector2,
	new_length: int,
	alive: bool
) -> void:

	if peer_id == multiplayer.get_unique_id():
		return

	if not remote_snakes.has(peer_id):

		_create_remote_snake(
			peer_id,
			"لاعب",
			new_position
		)

	var remote = remote_snakes.get(
		peer_id
	)

	if remote == null:
		return

	if remote.has_method(
		"update_state"
	):

		remote.update_state(
			new_position,
			new_direction,
			new_length,
			alive
		)

	else:

		remote.global_position = new_position


# ============================================================
# Local spawn
# ============================================================

func set_local_spawn(
	spawn_position: Vector2
) -> void:

	if snake == null:
		return

	snake.global_position = spawn_position


# ============================================================
# Player died
# ============================================================

func _on_player_died(
	victim_id: int,
	killer_id: int,
	death_position: Vector2,
	reward: Dictionary
) -> void:

	var local_id := multiplayer.get_unique_id()

	if victim_id == local_id:

		deaths += 1

		game_over = true

		can_respawn = true

		respawn_timer = 0.0

		last_killer_id = killer_id

		if snake != null:

			if snake.has_method(
				"die"
			):

				snake.die(
					"تم القضاء عليك"
				)

		_show_death_screen(
			killer_id
		)

	else:

		if killer_id == local_id:

			kills += 1

			var coins := int(
				reward.get(
					"coins",
					0
				)
			)

			var xp := int(
				reward.get(
					"xp",
					0
				)
			)

			if coins > 0:

				_show_notification(
					"🔥 قضيت على لاعب! +%d عملة" % coins
				)

			else:

				_show_notification(
					"🔥 قضيت على لاعب!"
				)

		else:

			_show_notification(
				"💥 تم القضاء على لاعب"
			)

	if remote_snakes.has(victim_id):

		var remote = remote_snakes[victim_id]

		if is_instance_valid(remote):

			if remote.has_method(
				"die"
			):

				remote.die()


	_update_ui()


# ============================================================
# Respawn
# ============================================================

func _on_player_respawned(
	peer_id: int,
	spawn_position: Vector2
) -> void:

	var local_id := multiplayer.get_unique_id()

	if peer_id == local_id:

		game_over = false

		can_respawn = false

		respawn_timer = 0.0

		if snake != null:

			snake.global_position = spawn_position

			if snake.has_method(
				"revive"
			):

				snake.revive()

			if snake.has_method(
				"reset_body"
			):

				snake.reset_body()

			if snake.has_method(
				"resume_movement"
			):

				snake.resume_movement()

		_remove_game_over_panel()

		_show_notification(
			"🛡️ عدت إلى اللعبة — حماية لمدة 3 ثوانٍ"
		)

	else:

		if remote_snakes.has(peer_id):

			var remote = remote_snakes[peer_id]

			if is_instance_valid(remote):

				if remote.has_method(
					"respawn"
				):

					remote.respawn(
						spawn_position
					)

				else:

					remote.global_position = spawn_position


# ============================================================
# Request respawn
# ============================================================

func _request_respawn() -> void:

	var network := get_node_or_null(
		"/root/Network"
	)

	if network == null:
		return

	network.request_respawn()


# ============================================================
# Death screen
# ============================================================

func _show_death_screen(
	killer_id: int
) -> void:

	_remove_game_over_panel()

	var canvas := get_node_or_null(
		"GameUI"
	)

	if canvas == null:
		return

	game_over_panel = Panel.new()

	game_over_panel.position = Vector2(
		390,
		175
	)

	game_over_panel.size = Vector2(
		500,
		370
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

	title.text = "💀 انتهت حياتك"

	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	title.add_theme_font_size_override(
		"font_size",
		40
	)

	game_over_panel.add_child(
		title
	)

	var killer_label := Label.new()

	killer_label.position = Vector2(
		30,
		90
	)

	killer_label.size = Vector2(
		440,
		50
	)

	if killer_id > 0:

		killer_label.text = (
			"القضاء عليك بواسطة لاعب #%d"
			% killer_id
		)

	else:

		killer_label.text = "انتهت المواجهة بالتعادل"

	killer_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	killer_label.add_theme_font_size_override(
		"font_size",
		20
	)

	game_over_panel.add_child(
		killer_label
	)

	var stats := Label.new()

	stats.position = Vector2(
		30,
		145
	)

	stats.size = Vector2(
		440,
		80
	)

	stats.text = (
		"القتلات: %d\n"
		+ "الوفيات: %d"
	) % [
		kills,
		deaths
	]

	stats.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	stats.add_theme_font_size_override(
		"font_size",
		22
	)

	game_over_panel.add_child(
		stats
	)

	var respawn := Button.new()

	respawn.position = Vector2(
		70,
		255
	)

	respawn.size = Vector2(
		360,
		60
	)

	respawn.text = "إعادة الظهور"

	respawn.pressed.connect(
		_request_respawn
	)

	game_over_panel.add_child(
		respawn
	)


# ============================================================
# Remove game over panel
# ============================================================

func _remove_game_over_panel() -> void:

	if is_instance_valid(
		game_over_panel
	):

		game_over_panel.queue_free()

	game_over_panel = null


# ============================================================
# UI
# ============================================================

func _create_ui() -> void:

	var canvas := CanvasLayer.new()

	canvas.name = "GameUI"

	add_child(canvas)

	var top_bar := Panel.new()

	top_bar.position = Vector2(
		20,
		20
	)

	top_bar.size = Vector2(
		390,
		175
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
		32
	)

	score_label.add_theme_font_size_override(
		"font_size",
		24
	)

	top_bar.add_child(
		score_label
	)

	length_label = Label.new()

	length_label.position = Vector2(
		20,
		50
	)

	length_label.size = Vector2(
		350,
		32
	)

	length_label.add_theme_font_size_override(
		"font_size",
		21
	)

	top_bar.add_child(
		length_label
	)

	kills_label = Label.new()

	kills_label.position = Vector2(
		20,
		87
	)

	kills_label.size = Vector2(
		350,
		32
	)

	kills_label.add_theme_font_size_override(
		"font_size",
		20
	)

	top_bar.add_child(
		kills_label
	)

	players_label = Label.new()

	players_label.position = Vector2(
		20,
		124
	)

	players_label.size = Vector2(
		350,
		32
	)

	players_label.add_theme_font_size_override(
		"font_size",
		19
	)

	top_bar.add_child(
		players_label
	)

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

	notification_label = Label.new()

	notification_label.position = Vector2(
		390,
		35
	)

	notification_label.size = Vector2(
		500,
		50
	)

	notification_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	notification_label.add_theme_font_size_override(
		"font_size",
		22
	)

	notification_label.visible = false

	canvas.add_child(
		notification_label
	)


# ============================================================
# UI update
# ============================================================

func _update_ui() -> void:

	if score_label:

		score_label.text = (
			"النقاط: %d"
			% score
		)

	if length_label and snake:

		var length := 10

		if snake.has_method(
			"get_length"
		):

			length = snake.get_length()

		length_label.text = (
			"الطول: %d"
			% length
		)

	if kills_label:

		kills_label.text = (
			"🔥 القتلات: %d   💀 الوفيات: %d"
			% [
				kills,
				deaths
			]
		)

	_update_players_count()


# ============================================================
# Players count
# ============================================================

func _update_players_count() -> void:

	if players_label == null:
		return

	var count := 1

	var network := get_node_or_null(
		"/root/Network"
	)

	if network != null:

		count = network.get_player_count()

	players_label.text = (
		"👥 اللاعبون: %d"
		% count
	)


# ============================================================
# Pause
# ============================================================

func _toggle_pause() -> void:

	paused = not paused

	if pause_button:

		pause_button.text = (
			"متابعة"
			if paused
			else
			"إيقاف"
		)

	if snake != null:

		if paused:

			if snake.has_method(
				"stop_movement"
			):

				snake.stop_movement()

		else:

			if snake.has_method(
				"resume_movement"
			):

				snake.resume_movement()


# ============================================================
# Notification
# ============================================================

func _show_notification(
	message: String
) -> void:

	if notification_label == null:
		return

	notification_label.text = message

	notification_label.visible = true

	var timer := get_tree().create_timer(
		2.5
	)

	timer.timeout.connect(
		func():
			if is_instance_valid(
				notification_label
			):

				notification_label.visible = false
	)


# ============================================================
# Network food
# ============================================================

func sync_network_food(
	food_data: Dictionary
) -> void:

	network_foods = food_data

	_refresh_network_food_visuals()


func _refresh_network_food_visuals() -> void:

	for id in network_food_nodes.keys():

		if not network_foods.has(id):

			var node = network_food_nodes[id]

			if is_instance_valid(node):

				node.queue_free()

			network_food_nodes.erase(id)

	for id in network_foods.keys():

		if not network_food_nodes.has(id):

			var data: Dictionary = network_foods[id]

			_create_single_network_food(
				int(id),
				data.get(
					"position",
					Vector2.ZERO
				),
				int(data.get(
					"value",
					10
				))
			)


func network_food_spawned(
	food_id: int,
	food_position: Vector2,
	value: int
) -> void:

	network_foods[food_id] = {
		"position": food_position,
		"value": value
	}

	_create_single_network_food(
		food_id,
		food_position,
		value
	)


func _on_food_spawned(
	food_id: int,
	food_position: Vector2,
	value: int
) -> void:

	network_food_spawned(
		food_id,
		food_position,
		value
	)


func _create_single_network_food(
	food_id: int,
	food_position: Vector2,
	value: int
) -> void:

	if network_food_nodes.has(
		food_id
	):

		return

	var node := Node2D.new()

	node.name = (
		"NetworkFood_%d"
		% food_id
	)

	node.position = food_position

	add_child(node)

	var visual := NetworkFoodVisual.new()

	visual.radius = FOOD_RADIUS

	node.add_child(
		visual
	)

	network_food_nodes[food_id] = node


func network_food_collected(
	food_id: int,
	collector_id: int
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

		if is_instance_valid(node):

			node.queue_free()

		network_food_nodes.erase(
			food_id
		)


func _on_food_collected(
	food_id: int,
	collector_id: int
) -> void:

	network_food_collected(
		food_id,
		collector_id
	)


# ============================================================
# Network loot
# ============================================================

func sync_network_loot(
	loot_data: Dictionary
) -> void:

	network_loot = loot_data

	_refresh_network_loot_visuals()


func _refresh_network_loot_visuals() -> void:

	for id in network_loot_nodes.keys():

		if not network_loot.has(id):

			var node = network_loot_nodes[id]

			if is_instance_valid(node):

				node.queue_free()

			network_loot_nodes.erase(id)

	for id in network_loot.keys():

		if not network_loot_nodes.has(id):

			var data: Dictionary = network_loot[id]

			_create_single_network_loot(
				int(id),
				data.get(
					"position",
					Vector2.ZERO
				),
				int(data.get(
					"value",
					10
				)),
				int(data.get(
					"xp",
					5
				))
			)


func network_loot_spawned(
	loot_id: int,
	loot_position: Vector2,
	value: int,
	xp: int
) -> void:

	network_loot[loot_id] = {
		"position": loot_position,
		"value": value,
		"xp": xp
	}

	_create_single_network_loot(
		loot_id,
		loot_position,
		value,
		xp
	)


func _on_loot_spawned(
	loot_id: int,
	loot_position: Vector2,
	value: int,
	xp: int
) -> void:

	network_loot_spawned(
		loot_id,
		loot_position,
		value,
		xp
	)


func _create_single_network_loot(
	loot_id: int,
	loot_position: Vector2,
	value: int,
	xp: int
) -> void:

	if network_loot_nodes.has(
		loot_id
	):

		return

	var node := Node2D.new()

	node.name = (
		"NetworkLoot_%d"
		% loot_id
	)

	node.position = loot_position

	add_child(node)

	var visual := NetworkLootVisual.new()

	visual.value = value
	visual.xp = xp

	node.add_child(
		visual
	)

	network_loot_nodes[loot_id] = node


func network_loot_collected(
	loot_id: int,
	collector_id: int
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

		if is_instance_valid(node):

			node.queue_free()

		network_loot_nodes.erase(
			loot_id
		)


func _on_loot_collected(
	loot_id: int,
	collector_id: int
) -> void:

	network_loot_collected(
		loot_id,
		collector_id
	)


# ============================================================
# Exit
# ============================================================

func _back_to_lobby() -> void:

	var network := get_node_or_null(
		"/root/Network"
	)

	if network:

		network.close_connection()

	get_tree().change_scene_to_file(
		"res://scenes/lobby.tscn"
	)


# ============================================================
# Food visual
# ============================================================

class FoodVisual extends Node2D:

	var radius := 9.0

	var pulse := 0.0

	func _process(delta: float) -> void:

		pulse += delta * 4.0

		queue_redraw()

	func _draw() -> void:

		var scale_factor := (
			1.0
			+ sin(pulse) * 0.08
		)

		draw_circle(
			Vector2.ZERO,
			radius * scale_factor,
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


# ============================================================
# Network food visual
# ============================================================

class NetworkFoodVisual extends Node2D:

	var radius := 9.0

	var pulse := 0.0

	func _process(delta: float) -> void:

		pulse += delta * 5.0

		queue_redraw()

	func _draw() -> void:

		var scale_factor := (
			1.0
			+ sin(pulse) * 0.1
		)

		draw_circle(
			Vector2.ZERO,
			radius * scale_factor,
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


# ============================================================
# Network loot visual
# ============================================================

class NetworkLootVisual extends Node2D:

	var value := 10
	var xp := 5

	var time := 0.0

	func _process(delta: float) -> void:

		time += delta

		position.y = sin(
			time * 4.0
		) * 4.0

		rotation = sin(
			time * 2.0
		) * 0.08

		queue_redraw()

	func _draw() -> void:

		draw_circle(
			Vector2.ZERO,
			15.0,
			Color("#F59E0B")
		)

		draw_circle(
			Vector2.ZERO,
			11.0,
			Color("#FACC15")
		)

		draw_circle(
			Vector2(
				-4,
				-4
			),
			3.0,
			Color.WHITE
		)
