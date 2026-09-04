extends Node2D

# =========================================================
# SNAKE ARAB ONLINE
# STEP 6.5
# تطوير الخريطة والعالم
# =========================================================

const MAP_SIZE := Vector2(4000.0, 4000.0)

const FOOD_COUNT := 180
const FOOD_RADIUS := 10.0
const FOOD_COLLECT_DISTANCE := 48.0

const MAP_BORDER := 80.0
const SAFE_SPAWN_DISTANCE := 600.0

var snake: Node2D
var camera: Camera2D

var foods: Array[Node2D] = []

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

var pause_button: Button
var game_over_panel: Panel

var rng := RandomNumberGenerator.new()

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
# PLAYER
# =========================================================

func _create_player() -> void:
	var snake_scene := preload("res://scenes/snake.tscn")

	snake = snake_scene.instantiate()

	snake.position = _get_safe_spawn_position()

	add_child(snake)

	if snake.has_method("setup"):
		snake.setup(Global.player_name)


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
# SAFE SPAWN
# =========================================================

func _get_safe_spawn_position() -> Vector2:
	var center := MAP_SIZE / 2.0

	var spawn := center

	for i in range(30):
		var candidate := Vector2(
			rng.randf_range(MAP_BORDER + 300.0, MAP_SIZE.x - MAP_BORDER - 300.0),
			rng.randf_range(MAP_BORDER + 300.0, MAP_SIZE.y - MAP_BORDER - 300.0)
		)

		if candidate.distance_to(center) < SAFE_SPAWN_DISTANCE:
			continue

		spawn = candidate
		break

	return spawn


# =========================================================
# FOOD
# =========================================================

func _create_food() -> void:
	for old_food in foods:
		if is_instance_valid(old_food):
			old_food.queue_free()

	foods.clear()

	for i in range(FOOD_COUNT):
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
			MAP_SIZE.x - MAP_BORDER - 50.0
		),
		rng.randf_range(
			MAP_BORDER + 50.0,
			MAP_SIZE.y - MAP_BORDER - 50.0
		)
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

	queue_redraw()


# =========================================================
# CAMERA FOLLOW
# =========================================================

func _update_camera() -> void:
	if not is_instance_valid(snake):
		return

	if not is_instance_valid(camera):
		return

	camera.position = snake.position


# =========================================================
# FOOD COLLECTION
# =========================================================

func _check_food_collection() -> void:
	if not is_instance_valid(snake):
		return

	if snake.has_method("get_is_dead"):
		if snake.get_is_dead():
			return

	for i in range(foods.size() - 1, -1, -1):
		var food := foods[i]

		if not is_instance_valid(food):
			foods.remove_at(i)
			continue

		var distance := snake.global_position.distance_to(
			food.global_position
		)

		if distance <= FOOD_COLLECT_DISTANCE:
			_collect_food(food, i)


func _collect_food(food: Node2D, index: int) -> void:
	score += 10

	round_coins += 1
	round_xp += 5

	if Global.has_method("add_coins"):
		Global.add_coins(1)

	if Global.has_method("add_experience"):
		Global.add_experience(5)

	if is_instance_valid(snake):
		if snake.has_method("grow"):
			snake.grow(1)

	if is_instance_valid(food):
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

	top_panel.position = Vector2(20, 20)
	top_panel.size = Vector2(1240, 80)

	canvas.add_child(top_panel)

	var style := StyleBoxFlat.new()

	style.bg_color = Color(
		0.025,
		0.03,
		0.04,
		0.90
	)

	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18

	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1

	style.border_color = Color(
		0.25,
		0.30,
		0.27,
		0.8
	)

	top_panel.add_theme_stylebox_override(
		"panel",
		style
	)

	# -----------------------------
	# SCORE
	# -----------------------------

	score_label = Label.new()

	score_label.position = Vector2(35, 25)
	score_label.size = Vector2(220, 35)

	score_label.text = "النقاط: 0"

	score_label.add_theme_font_size_override(
		"font_size",
		22
	)

	top_panel.add_child(score_label)

	# -----------------------------
	# LENGTH
	# -----------------------------

	length_label = Label.new()

	length_label.position = Vector2(280, 25)
	length_label.size = Vector2(220, 35)

	length_label.text = "الطول: 10"

	length_label.add_theme_font_size_override(
		"font_size",
		22
	)

	top_panel.add_child(length_label)

	# -----------------------------
	# COINS
	# -----------------------------

	coins_label = Label.new()

	coins_label.position = Vector2(520, 25)
	coins_label.size = Vector2(220, 35)

	coins_label.text = "🪙 الجولة: 0"

	coins_label.add_theme_font_size_override(
		"font_size",
		22
	)

	top_panel.add_child(coins_label)

	# -----------------------------
	# WALLET
	# -----------------------------

	wallet_label = Label.new()

	wallet_label.position = Vector2(750, 25)
	wallet_label.size = Vector2(220, 35)

	wallet_label.text = "المحفظة: 0"

	wallet_label.add_theme_font_size_override(
		"font_size",
		22
	)

	top_panel.add_child(wallet_label)

	# -----------------------------
	# LEVEL
	# -----------------------------

	level_label = Label.new()

	level_label.position = Vector2(990, 25)
	level_label.size = Vector2(170, 35)

	level_label.text = "المستوى: 1"

	level_label.add_theme_font_size_override(
		"font_size",
		22
	)

	top_panel.add_child(level_label)

	# -----------------------------
	# PAUSE
	# -----------------------------

	pause_button = Button.new()

	pause_button.position = Vector2(1110, 120)
	pause_button.size = Vector2(130, 55)

	pause_button.text = "إيقاف"

	pause_button.add_theme_font_size_override(
		"font_size",
		20
	)

	pause_button.pressed.connect(_toggle_pause)

	canvas.add_child(pause_button)

	_update_ui()


# =========================================================
# UI UPDATE
# =========================================================

func _update_ui() -> void:
	if is_instance_valid(score_label):
		score_label.text = "النقاط: %d" % score

	if is_instance_valid(coins_label):
		coins_label.text = "🪙 الجولة: %d" % round_coins

	if is_instance_valid(wallet_label):
		wallet_label.text = "المحفظة: %d" % Global.coins

	if is_instance_valid(level_label):
		level_label.text = "المستوى: %d" % Global.level

	if is_instance_valid(length_label):
		var current_length := 10

		if is_instance_valid(snake):
			if snake.has_method("get_length"):
				current_length = snake.get_length()

		length_label.text = "الطول: %d" % current_length


# =========================================================
# PAUSE
# =========================================================

func _toggle_pause() -> void:
	paused = not paused

	if is_instance_valid(pause_button):
		if paused:
			pause_button.text = "متابعة"
		else:
			pause_button.text = "إيقاف"


# =========================================================
# GAME OVER
# =========================================================

func snake_died(dead_snake: Node2D, reason: String = "") -> void:
	if game_over:
		return

	game_over = true

	paused = true

	if Global.has_method("save_data"):
		Global.last_score = score
		Global.last_coins = round_coins

		if is_instance_valid(dead_snake):
			if dead_snake.has_method("get_length"):
				Global.last_length = dead_snake.get_length()

		Global.save_data()

	_show_game_over()


func _show_game_over() -> void:
	var canvas := get_node_or_null("GameUI")

	if canvas == null:
		return

	game_over_panel = Panel.new()

	game_over_panel.position = Vector2(340, 180)
	game_over_panel.size = Vector2(600, 360)

	var panel_style := StyleBoxFlat.new()

	panel_style.bg_color = Color(
		0.025,
		0.03,
		0.04,
		0.97
	)

	panel_style.corner_radius_top_left = 25
	panel_style.corner_radius_top_right = 25
	panel_style.corner_radius_bottom_left = 25
	panel_style.corner_radius_bottom_right = 25

	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2

	panel_style.border_color = Color(
		0.35,
		0.45,
		0.38,
		1
	)

	game_over_panel.add_theme_stylebox_override(
		"panel",
		panel_style
	)

	canvas.add_child(game_over_panel)

	var title := Label.new()

	title.position = Vector2(0, 30)
	title.size = Vector2(600, 60)

	title.text = "انتهت اللعبة"

	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	title.add_theme_font_size_override(
		"font_size",
		38
	)

	game_over_panel.add_child(title)

	var result := Label.new()

	result.position = Vector2(0, 110)
	result.size = Vector2(600, 120)

	result.text = (
		"النقاط: %d\n" %
		score +
		"عملات الجولة: %d\n" %
		round_coins +
		"الطول النهائي: %d" %
		_get_snake_length()
	)

	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	result.add_theme_font_size_override(
		"font_size",
		24
	)

	game_over_panel.add_child(result)

	var restart := Button.new()

	restart.position = Vector2(100, 260)
	restart.size = Vector2(180, 60)

	restart.text = "إعادة اللعب"

	restart.add_theme_font_size_override(
		"font_size",
		21
	)

	restart.pressed.connect(_restart_game)

	game_over_panel.add_child(restart)

	var menu := Button.new()

	menu.position = Vector2(320, 260)
	menu.size = Vector2(180, 60)

	menu.text = "القائمة الرئيسية"

	menu.add_theme_font_size_override(
		"font_size",
		21
	)

	menu.pressed.connect(_return_to_menu)

	game_over_panel.add_child(menu)


func _get_snake_length() -> int:
	if is_instance_valid(snake):
		if snake.has_method("get_length"):
			return snake.get_length()

	return 10


# =========================================================
# RESTART
# =========================================================

func _restart_game() -> void:
	get_tree().reload_current_scene()


# =========================================================
# RETURN TO MENU
# =========================================================

func _return_to_menu() -> void:
	get_tree().change_scene_to_file(
		"res://scenes/main_menu.tscn"
	)


# =========================================================
# MAP DRAW
# =========================================================

func _draw() -> void:
	# -----------------------------
	# GRID
	# -----------------------------

	var grid_size := 100.0

	for x in range(0, int(MAP_SIZE.x) + 1, int(grid_size)):
		draw_line(
			Vector2(x, 0),
			Vector2(x, MAP_SIZE.y),
			Color(0.12, 0.16, 0.14, 0.35),
			2.0
		)

	for y in range(0, int(MAP_SIZE.y) + 1, int(grid_size)):
		draw_line(
			Vector2(0, y),
			Vector2(MAP_SIZE.x, y),
			Color(0.12, 0.16, 0.14, 0.35),
			2.0
		)

	# -----------------------------
	# MAP BORDER
	# -----------------------------

	var border_rect := Rect2(
		0,
		0,
		MAP_SIZE.x,
		MAP_SIZE.y
	)

	draw_rect(
		border_rect,
		Color(0.08, 0.11, 0.09, 1.0),
		false,
		25.0
	)

	draw_rect(
		Rect2(
			30,
			30,
			MAP_SIZE.x - 60,
			MAP_SIZE.y - 60
		),
		Color(0.20, 0.28, 0.22, 0.8),
		false,
		5.0
	)

	# -----------------------------
	# MAP ZONES
	# -----------------------------

	var zone_size := MAP_SIZE / 2.0

	draw_rect(
		Rect2(
			0,
			0,
			zone_size.x,
			zone_size.y
		),
		Color(0.04, 0.09, 0.07, 0.18)
	)

	draw_rect(
		Rect2(
			zone_size.x,
			0,
			zone_size.x,
			zone_size.y
		),
		Color(0.08, 0.07, 0.04, 0.15)
	)

	draw_rect(
		Rect2(
			0,
			zone_size.y,
			zone_size.x,
			zone_size.y
		),
		Color(0.04, 0.07, 0.10, 0.15)
	)

	draw_rect(
		Rect2(
			zone_size.x,
			zone_size.y,
			zone_size.x,
			zone_size.y
		),
		Color(0.09, 0.05, 0.08, 0.15)
	)

	# -----------------------------
	# CENTRAL SAFE AREA
	# -----------------------------

	var center := MAP_SIZE / 2.0

	draw_circle(
		center,
		420.0,
		Color(0.12, 0.18, 0.14, 0.18)
	)

	draw_arc(
		center,
		420.0,
		0,
		TAU,
		100,
		Color(0.22, 0.32, 0.24, 0.4),
		3.0
	)

	# -----------------------------
	# DECORATIVE ROCKS
	# -----------------------------

	for i in range(70):
		var px := float(
			((i * 317) % 3700) + 150
		)

		var py := float(
			((i * 571) % 3700) + 150
		)

		var radius := float(6 + (i % 8))

		draw_circle(
			Vector2(px, py),
			radius,
			Color(0.18, 0.21, 0.18, 0.7)
		)

		draw_circle(
			Vector2(
				px - radius * 0.3,
				py - radius * 0.3
			),
			radius * 0.35,
			Color(0.30, 0.34, 0.30, 0.45)
		)

	# -----------------------------
	# DECORATIVE GRASS
	# -----------------------------

	for i in range(100):
		var gx := float(
			((i * 173) % 3800) + 100
		)

		var gy := float(
			((i * 431) % 3800) + 100
		)

		draw_line(
			Vector2(gx, gy),
			Vector2(gx - 4, gy - 12),
			Color(0.18, 0.30, 0.20, 0.65),
			2.0
		)

		draw_line(
			Vector2(gx, gy),
			Vector2(gx + 5, gy - 10),
			Color(0.20, 0.32, 0.22, 0.65),
			2.0
		)


# =========================================================
# FOOD VISUAL
# =========================================================

class FoodVisual extends Node2D:

	var pulse := 0.0

	func _ready() -> void:
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		pulse += delta * 3.0
		queue_redraw()

	func _draw() -> void:
		var scale_value := 1.0 + sin(pulse) * 0.08

		draw_circle(
			Vector2.ZERO,
			FOOD_RADIUS * 1.7 * scale_value,
			Color(
				1.0,
				0.75,
				0.12,
				0.10
			)
		)

		draw_circle(
			Vector2.ZERO,
			FOOD_RADIUS * scale_value,
			Color(
				1.0,
				0.78,
				0.12,
				1.0
			)
		)

		draw_circle(
			Vector2(
				-3,
				-3
			),
			3.0,
			Color(
				1.0,
				0.95,
				0.55,
				0.9
			)
		)
