extends Node2D

const MAP_SIZE := Vector2(4000.0, 4000.0)
const FOOD_COUNT := 180
const FOOD_RADIUS := 9.0

var snake: Node2D
var foods: Array[Node2D] = []

var score := 0
var game_over := false
var paused := false

var score_label: Label
var length_label: Label
var pause_button: Button
var game_over_panel: Panel


func _ready() -> void:
	randomize()

	_create_background()
	_create_food()
	_create_local_player()
	_create_ui()


func _process(_delta: float) -> void:
	if snake == null:
		return

	if not game_over and not paused:
		_check_food_collision()
		_check_map_collision()

	_update_ui()
	queue_redraw()


func _create_background() -> void:
	var background := ColorRect.new()

	background.position = Vector2.ZERO
	background.size = MAP_SIZE
	background.color = Color("#111827")

	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(background)
	move_child(background, 0)


func _draw() -> void:
	draw_rect(
		Rect2(Vector2.ZERO, MAP_SIZE),
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


func _create_local_player() -> void:
	var snake_scene := load("res://scenes/snake.tscn")

	if snake_scene == null:
		push_error("Snake scene not found")
		return

	snake = snake_scene.instantiate()

	snake.position = MAP_SIZE / 2.0

	add_child(snake)

	if snake.has_method("setup"):
		snake.setup(Global.player_name)


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

	var visual := FoodVisual.new()
	visual.radius = FOOD_RADIUS

	food.add_child(visual)


func _check_food_collision() -> void:
	if snake == null:
		return

	var head_position := snake.global_position

	for food in foods.duplicate():

		if not is_instance_valid(food):
			foods.erase(food)
			continue

		if head_position.distance_to(food.global_position) < 30.0:

			var value := int(food.get_meta("value", 10))

			score += value

			if snake.has_method("grow"):
				snake.grow(1)

			foods.erase(food)
			food.queue_free()

			_spawn_food()


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


func _create_ui() -> void:
	var canvas := CanvasLayer.new()

	canvas.name = "GameUI"

	add_child(canvas)

	var top_bar := Panel.new()

	top_bar.position = Vector2(20, 20)
	top_bar.size = Vector2(350, 115)

	canvas.add_child(top_bar)

	score_label = Label.new()

	score_label.position = Vector2(20, 15)
	score_label.size = Vector2(310, 40)

	score_label.add_theme_font_size_override(
		"font_size",
		28
	)

	top_bar.add_child(score_label)

	length_label = Label.new()

	length_label.position = Vector2(20, 65)
	length_label.size = Vector2(310, 35)

	length_label.add_theme_font_size_override(
		"font_size",
		22
	)

	top_bar.add_child(length_label)

	pause_button = Button.new()

	pause_button.position = Vector2(1110, 25)
	pause_button.size = Vector2(140, 60)

	pause_button.text = "إيقاف"

	pause_button.pressed.connect(_toggle_pause)

	canvas.add_child(pause_button)

	var exit_button := Button.new()

	exit_button.position = Vector2(1110, 95)
	exit_button.size = Vector2(140, 55)

	exit_button.text = "خروج"

	exit_button.pressed.connect(_back_to_lobby)

	canvas.add_child(exit_button)


func _update_ui() -> void:
	if score_label:
		score_label.text = "النقاط: %d" % score

	if length_label and snake:
		var length := 10

		if snake.has_method("get_length"):
			length = snake.get_length()

		length_label.text = "الطول: %d" % length


func _toggle_pause() -> void:
	paused = not paused

	if pause_button:
		pause_button.text = "متابعة" if paused else "إيقاف"


func _game_over() -> void:
	if game_over:
		return

	game_over = true

	_show_game_over()


func _show_game_over() -> void:
	var canvas := get_node_or_null("GameUI")

	if canvas == null:
		return

	game_over_panel = Panel.new()

	game_over_panel.position = Vector2(390, 200)
	game_over_panel.size = Vector2(500, 300)

	canvas.add_child(game_over_panel)

	var title := Label.new()

	title.position = Vector2(30, 30)
	title.size = Vector2(440, 60)

	title.text = "انتهت اللعبة"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	title.add_theme_font_size_override(
		"font_size",
		40
	)

	game_over_panel.add_child(title)

	var result := Label.new()

	result.position = Vector2(30, 100)
	result.size = Vector2(440, 50)

	result.text = "النقاط: %d" % score
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	result.add_theme_font_size_override(
		"font_size",
		25
	)

	game_over_panel.add_child(result)

	var restart := Button.new()

	restart.position = Vector2(80, 180)
	restart.size = Vector2(340, 55)

	restart.text = "العب مرة أخرى"

	restart.pressed.connect(
		func():
			get_tree().reload_current_scene()
	)

	game_over_panel.add_child(restart)


func _back_to_lobby() -> void:
	var network := get_node_or_null("/root/Network")

	if network:
		network.close_connection()

	get_tree().change_scene_to_file(
		"res://scenes/lobby.tscn"
	)


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
			Color.WHITE
		)
