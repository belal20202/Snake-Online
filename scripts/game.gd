extends Node2D

const MAP_SIZE := Vector2(4000.0, 4000.0)
const FOOD_COUNT := 180
const FOOD_RADIUS := 9.0

var snake: Node2D
var foods: Array[Node2D] = []
var score: int = 0
var game_over := false
var paused := false

var score_label: Label
var length_label: Label
var pause_button: Button
var game_over_panel: Panel
var joystick_center := Vector2.ZERO
var joystick_active := false


func _ready() -> void:
	randomize()

	_create_background()
	_create_snake()
	_create_food()
	_create_ui()
	_center_camera()


func _process(_delta: float) -> void:
	if snake == null:
		return

	if not game_over and not paused:
		_check_food_collision()
		_check_map_collision()

	queue_redraw()


# =========================================================
# BACKGROUND
# =========================================================

func _create_background() -> void:
	var background := ColorRect.new()

	background.position = Vector2.ZERO
	background.size = MAP_SIZE

	background.color = Color("#111827")

	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(background)
	move_child(background, 0)


func _draw() -> void:
	# حدود الخريطة
	draw_rect(
		Rect2(Vector2.ZERO, MAP_SIZE),
		Color("#263449"),
		false,
		12.0
	)

	# شبكة الخريطة
	var grid_size := 100.0

	var x := 0.0
	while x <= MAP_SIZE.x:
		draw_line(
			Vector2(x, 0),
			Vector2(x, MAP_SIZE.y),
			Color(0.12, 0.16, 0.22, 0.35),
			2.0
		)
		x += grid_size

	var y := 0.0
	while y <= MAP_SIZE.y:
		draw_line(
			Vector2(0, y),
			Vector2(MAP_SIZE.x, y),
			Color(0.12, 0.16, 0.22, 0.35),
			2.0
		)
		y += grid_size


# =========================================================
# SNAKE
# =========================================================

func _create_snake() -> void:
	var snake_scene := load("res://scenes/snake.tscn")

	if snake_scene:
		snake = snake_scene.instantiate()
		add_child(snake)

		snake.position = MAP_SIZE / 2.0

		if snake.has_method("setup"):
			snake.setup("بلال")


func _center_camera() -> void:
	var camera := Camera2D.new()

	camera.position = MAP_SIZE / 2.0
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0

	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(MAP_SIZE.x)
	camera.limit_bottom = int(MAP_SIZE.y)

	add_child(camera)

	if snake:
		camera.reparent(snake)
		camera.position = Vector2.ZERO


# =========================================================
# FOOD
# =========================================================

func _create_food() -> void:
	for i in range(FOOD_COUNT):
		_spawn_food()


func _spawn_food() -> void:
	var food := Node2D.new()

	food.position = Vector2(
		randf_range(100.0, MAP_SIZE.x - 100.0),
		randf_range(100.0, MAP_SIZE.y - 100.0)
	)

	food.set_meta("radius", FOOD_RADIUS)
	food.set_meta("value", 10)

	add_child(food)

	foods.append(food)

	var food_visual := FoodVisual.new()
	food_visual.radius = FOOD_RADIUS

	food.add_child(food_visual)


func _check_food_collision() -> void:
	if snake == null:
		return

	var head_position: Vector2 = snake.global_position

	for food in foods.duplicate():
		if not is_instance_valid(food):
			foods.erase(food)
			continue

		var distance := head_position.distance_to(food.global_position)

		if distance < 30.0:
			var value: int = int(food.get_meta("value", 10))

			score += value

			if snake.has_method("grow"):
				snake.grow(1)

			foods.erase(food)
			food.queue_free()

			_spawn_food()

			_update_ui()


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
# UI
# =========================================================

func _create_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# أعلى الشاشة
	var top_bar := Panel.new()

	top_bar.position = Vector2(20, 20)
	top_bar.size = Vector2(360, 120)

	canvas.add_child(top_bar)

	score_label = Label.new()
	score_label.position = Vector2(25, 15)
	score_label.size = Vector2(310, 40)
	score_label.text = "النقاط: 0"
	score_label.add_theme_font_size_override("font_size", 28)

	top_bar.add_child(score_label)

	length_label = Label.new()
	length_label.position = Vector2(25, 65)
	length_label.size = Vector2(310, 40)
	length_label.text = "الطول: 10"
	length_label.add_theme_font_size_override("font_size", 24)

	top_bar.add_child(length_label)

	# زر الإيقاف
	pause_button = Button.new()

	pause_button.position = Vector2(1110, 25)
	pause_button.size = Vector2(140, 60)

	pause_button.text = "إيقاف"
	pause_button.add_theme_font_size_override("font_size", 22)

	pause_button.pressed.connect(_toggle_pause)

	canvas.add_child(pause_button)

	# زر العودة
	var back_button := Button.new()

	back_button.position = Vector2(1110, 95)
	back_button.size = Vector2(140, 55)

	back_button.text = "خروج"

	back_button.add_theme_font_size_override("font_size", 20)

	back_button.pressed.connect(_back_to_menu)

	canvas.add_child(back_button)

	# عصا تحكم مبدئية
	_create_mobile_controls(canvas)

	_update_ui()


func _create_mobile_controls(canvas: CanvasLayer) -> void:
	var joystick := Control.new()

	joystick.position = Vector2(50, 520)
	joystick.size = Vector2(180, 180)

	canvas.add_child(joystick)

	var outer := ColorRect.new()

	outer.position = Vector2(20, 20)
	outer.size = Vector2(140, 140)

	outer.color = Color(0.15, 0.2, 0.28, 0.7)

	joystick.add_child(outer)

	var inner := ColorRect.new()

	inner.position = Vector2(60, 60)
	inner.size = Vector2(60, 60)

	inner.color = Color(0.3, 0.4, 0.55, 0.9)

	joystick.add_child(inner)


func _update_ui() -> void:
	if score_label:
		score_label.text = "النقاط: %d" % score

	if length_label and snake:
		var current_length := 10

		if snake.has_method("get_length"):
			current_length = snake.get_length()

		length_label.text = "الطول: %d" % current_length


# =========================================================
# PAUSE
# =========================================================

func _toggle_pause() -> void:
	paused = not paused

	if pause_button:
		pause_button.text = "متابعة" if paused else "إيقاف"


# =========================================================
# GAME OVER
# =========================================================

func _game_over() -> void:
	if game_over:
		return

	game_over = true

	_create_game_over()


func _create_game_over() -> void:
	var canvas := get_node_or_null("CanvasLayer")

	if canvas == null:
		return

	game_over_panel = Panel.new()

	game_over_panel.position = Vector2(390, 190)
	game_over_panel.size = Vector2(500, 340)

	canvas.add_child(game_over_panel)

	var title := Label.new()

	title.position = Vector2(40, 30)
	title.size = Vector2(420, 60)

	title.text = "انتهت اللعبة"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	title.add_theme_font_size_override("font_size", 42)

	game_over_panel.add_child(title)

	var result := Label.new()

	result.position = Vector2(40, 105)
	result.size = Vector2(420, 50)

	result.text = "النقاط: %d" % score
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	result.add_theme_font_size_override("font_size", 26)

	game_over_panel.add_child(result)

	var restart := Button.new()

	restart.position = Vector2(80, 190)
	restart.size = Vector2(340, 60)

	restart.text = "العب مرة أخرى"
	restart.add_theme_font_size_override("font_size", 24)

	restart.pressed.connect(_restart_game)

	game_over_panel.add_child(restart)

	var menu := Button.new()

	menu.position = Vector2(80, 260)
	menu.size = Vector2(340, 50)

	menu.text = "القائمة الرئيسية"

	menu.pressed.connect(_back_to_menu)

	game_over_panel.add_child(menu)


func _restart_game() -> void:
	get_tree().reload_current_scene()


func _back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# =========================================================
# FOOD VISUAL
# =========================================================

class FoodVisual extends Node2D:

	var radius := 9.0

	func _draw() -> void:
		draw_circle(
			Vector2.ZERO,
			radius,
			Color("#FACC15")
		)

		draw_circle(
			Vector2(-3, -3),
			radius * 0.3,
			Color(1, 1, 1, 0.8)
		)
