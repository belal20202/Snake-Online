extends Node2D

# =========================================================
# 🐍 SNAKE ARAB ONLINE
# الخطوة 6.3
# النقاط + العملات + الخبرة + حفظ البيانات
# =========================================================

# =========================================================
# إعدادات الخريطة
# =========================================================

const MAP_SIZE := Vector2(
	4000.0,
	4000.0
)

const MAP_MARGIN := 120.0

# =========================================================
# إعدادات الطعام
# =========================================================

const FOOD_COUNT := 180

const FOOD_RADIUS := 10.0

const FOOD_COLLECT_DISTANCE := 45.0

const FOOD_SCORE := 10

const FOOD_COINS := 1

const FOOD_XP := 5

# =========================================================
# اللاعب
# =========================================================

var snake: Node2D = null

# =========================================================
# الطعام
# =========================================================

var foods: Array[Node2D] = []

# =========================================================
# إحصائيات الجولة
# =========================================================

var score: int = 0

var round_coins: int = 0

var round_xp: int = 0

# =========================================================
# حالة اللعبة
# =========================================================

var game_over: bool = false

var paused: bool = false

# =========================================================
# واجهة المستخدم
# =========================================================

var score_label: Label = null

var length_label: Label = null

var coins_label: Label = null

var wallet_label: Label = null

var level_label: Label = null

var pause_button: Button = null

var game_over_panel: Panel = null


# =========================================================
# البداية
# =========================================================

func _ready() -> void:

	randomize()

	_create_background()

	_create_food()

	_create_local_player()

	_create_ui()

	_update_ui()

	queue_redraw()


# =========================================================
# تحديث اللعبة
# =========================================================

func _process(_delta: float) -> void:

	if snake == null:
		return

	if not game_over and not paused:

		_check_food_collision()

		_check_map_collision()

	_update_ui()

	queue_redraw()


# =========================================================
# خلفية الخريطة
# =========================================================

func _create_background() -> void:

	var background := ColorRect.new()

	background.name = "MapBackground"

	background.position = Vector2.ZERO

	background.size = MAP_SIZE

	background.color = Color("#111827")

	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(background)

	move_child(
		background,
		0
	)


# =========================================================
# رسم الخريطة
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


# =========================================================
# إنشاء اللاعب
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

	snake.position = MAP_SIZE / 2.0

	add_child(snake)


	if snake.has_method("setup"):

		var player_name := "لاعب"

		if Global.player_name.strip_edges() != "":

			player_name = Global.player_name

		snake.setup(
			player_name
		)


# =========================================================
# إنشاء الطعام
# =========================================================

func _create_food() -> void:

	for i in range(FOOD_COUNT):

		_spawn_food()


# =========================================================
# إنشاء طعام
# =========================================================

func _spawn_food() -> void:

	var food := Node2D.new()

	food.name = "Food"

	food.position = Vector2(
		randf_range(
			MAP_MARGIN,
			MAP_SIZE.x - MAP_MARGIN
		),
		randf_range(
			MAP_MARGIN,
			MAP_SIZE.y - MAP_MARGIN
		)
	)

	food.set_meta(
		"value",
		FOOD_SCORE
	)

	food.set_meta(
		"coins",
		FOOD_COINS
	)

	food.set_meta(
		"xp",
		FOOD_XP
	)

	add_child(food)

	foods.append(food)

	var visual := FoodVisual.new()

	visual.radius = FOOD_RADIUS

	food.add_child(
		visual
	)


# =========================================================
# فحص الطعام
# =========================================================

func _check_food_collision() -> void:

	if snake == null:
		return

	var head_position := snake.global_position

	for food in foods.duplicate():

		if not is_instance_valid(food):

			foods.erase(food)

			continue


		var distance := (
			head_position.distance_to(
				food.global_position
			)
		)


		if distance <= FOOD_COLLECT_DISTANCE:

			_collect_food(
				food
			)


# =========================================================
# جمع الطعام
# =========================================================

func _collect_food(
	food: Node2D
) -> void:

	if not is_instance_valid(food):
		return


	# =====================================================
	# قراءة قيمة الطعام
	# =====================================================

	var score_value := FOOD_SCORE

	var coin_value := FOOD_COINS

	var xp_value := FOOD_XP


	if food.has_meta("value"):

		score_value = int(
			food.get_meta("value")
		)


	if food.has_meta("coins"):

		coin_value = int(
			food.get_meta("coins")
		)


	if food.has_meta("xp"):

		xp_value = int(
			food.get_meta("xp")
		)


	# =====================================================
	# تحديث إحصائيات الجولة
	# =====================================================

	score += score_value

	round_coins += coin_value

	round_xp += xp_value


	# =====================================================
	# زيادة طول الثعبان
	# =====================================================

	if snake.has_method("grow"):

		snake.grow(1)


	# =====================================================
	# حفظ العملات والخبرة مباشرة
	# =====================================================

	Global.add_coins(
		coin_value
	)

	Global.add_experience(
		xp_value
	)


	# =====================================================
	# إزالة الطعام
	# =====================================================

	foods.erase(food)

	food.queue_free()


	# =====================================================
	# إنشاء طعام جديد
	# =====================================================

	_spawn_food()


	_update_ui()


# =========================================================
# اصطدام حدود الخريطة
# =========================================================

func _check_map_collision() -> void:

	if snake == null:
		return

	var pos := snake.global_position

	if (
		pos.x < 30.0
		or
		pos.y < 30.0
		or
		pos.x > MAP_SIZE.x - 30.0
		or
		pos.y > MAP_SIZE.y - 30.0
	):

		_game_over()


# =========================================================
# إنشاء واجهة اللعبة
# =========================================================

func _create_ui() -> void:

	var canvas := CanvasLayer.new()

	canvas.name = "GameUI"

	add_child(canvas)


	# =====================================================
	# الشريط العلوي
	# =====================================================

	var top_bar := Panel.new()

	top_bar.name = "TopBar"

	top_bar.position = Vector2(
		20,
		20
	)

	top_bar.size = Vector2(
		410,
		220
	)

	canvas.add_child(
		top_bar
	)


	# =====================================================
	# النقاط
	# =====================================================

	score_label = Label.new()

	score_label.position = Vector2(
		20,
		10
	)

	score_label.size = Vector2(
		370,
		38
	)

	score_label.text = "النقاط: 0"

	score_label.add_theme_font_size_override(
		"font_size",
		27
	)

	top_bar.add_child(
		score_label
	)


	# =====================================================
	# الطول
	# =====================================================

	length_label = Label.new()

	length_label.position = Vector2(
		20,
		52
	)

	length_label.size = Vector2(
		370,
		35
	)

	length_label.text = "الطول: 10"

	length_label.add_theme_font_size_override(
		"font_size",
		21
	)

	top_bar.add_child(
		length_label
	)


	# =====================================================
	# عملات الجولة
	# =====================================================

	coins_label = Label.new()

	coins_label.position = Vector2(
		20,
		90
	)

	coins_label.size = Vector2(
		370,
		35
	)

	coins_label.text = "🪙 الجولة: 0"

	coins_label.add_theme_font_size_override(
		"font_size",
		21
	)

	top_bar.add_child(
		coins_label
	)


	# =====================================================
	# المحفظة
	# =====================================================

	wallet_label = Label.new()

	wallet_label.position = Vector2(
		20,
		128
	)

	wallet_label.size = Vector2(
		370,
		35
	)

	wallet_label.text = "💰 الرصيد: 0"

	wallet_label.add_theme_font_size_override(
		"font_size",
		21
	)

	top_bar.add_child(
		wallet_label
	)


	# =====================================================
	# المستوى
	# =====================================================

	level_label = Label.new()

	level_label.position = Vector2(
		20,
		166
	)

	level_label.size = Vector2(
		370,
		35
	)

	level_label.text = "⭐ المستوى: 1"

	level_label.add_theme_font_size_override(
		"font_size",
		21
	)

	top_bar.add_child(
		level_label
	)


	# =====================================================
	# زر الإيقاف
	# =====================================================

	pause_button = Button.new()

	pause_button.name = "PauseButton"

	pause_button.position = Vector2(
		1100,
		25
	)

	pause_button.size = Vector2(
		150,
		60
	)

	pause_button.text = "إيقاف"

	pause_button.add_theme_font_size_override(
		"font_size",
		20
	)

	pause_button.pressed.connect(
		_toggle_pause
	)

	canvas.add_child(
		pause_button
	)


	# =====================================================
	# زر الخروج
	# =====================================================

	var exit_button := Button.new()

	exit_button.name = "ExitButton"

	exit_button.position = Vector2(
		1100,
		95
	)

	exit_button.size = Vector2(
		150,
		55
	)

	exit_button.text = "خروج"

	exit_button.add_theme_font_size_override(
		"font_size",
		19
	)

	exit_button.pressed.connect(
		_back_to_lobby
	)

	canvas.add_child(
		exit_button
	)


# =========================================================
# تحديث الواجهة
# =========================================================

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


	if coins_label:

		coins_label.text = (
			"🪙 الجولة: %d"
			% round_coins
		)


	if wallet_label:

		wallet_label.text = (
			"💰 الرصيد: %d"
			% Global.coins
		)


	if level_label:

		level_label.text = (
			"⭐ المستوى: %d"
			% Global.level
		)


# =========================================================
# إيقاف / متابعة
# =========================================================

func _toggle_pause() -> void:

	paused = not paused


	if pause_button:

		if paused:

			pause_button.text = "متابعة"

		else:

			pause_button.text = "إيقاف"


# =========================================================
# انتهاء اللعبة
# =========================================================

func _game_over() -> void:

	if game_over:
		return


	game_over = true


	if snake:

		if snake.has_method(
			"stop_movement"
		):

			snake.stop_movement()


	# حفظ إحصائيات الجولة

	Global.last_score = score

	Global.last_coins = round_coins

	Global.last_length = _get_snake_length()

	Global.save_data()


	_show_game_over()


# =========================================================
# شاشة النهاية
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

	game_over_panel.name = "GameOverPanel"

	game_over_panel.position = Vector2(
		390,
		180
	)

	game_over_panel.size = Vector2(
		500,
		370
	)

	canvas.add_child(
		game_over_panel
	)


	# =====================================================
	# العنوان
	# =====================================================

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


	# =====================================================
	# النتائج
	# =====================================================

	var result := Label.new()

	result.position = Vector2(
		30,
		95
	)

	result.size = Vector2(
		440,
		120
	)

	result.text = (
		"النقاط: %d\n"
		+ "الطول: %d\n"
		+ "عملات الجولة: %d\n"
		+ "رصيدك: %d"
		% [
			score,
			_get_snake_length(),
			round_coins,
			Global.coins
		]
	)

	result.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	result.add_theme_font_size_override(
		"font_size",
		22
	)

	game_over_panel.add_child(
		result
	)


	# =====================================================
	# إعادة اللعب
	# =====================================================

	var restart := Button.new()

	restart.position = Vector2(
		80,
		245
	)

	restart.size = Vector2(
		340,
		55
	)

	restart.text = "العب مرة أخرى"

	restart.add_theme_font_size_override(
		"font_size",
		20
	)

	restart.pressed.connect(
		func():
			get_tree().reload_current_scene()
	)

	game_over_panel.add_child(
		restart
	)


# =========================================================
# طول الثعبان
# =========================================================

func _get_snake_length() -> int:

	if snake == null:
		return 0


	if snake.has_method(
		"get_length"
	):

		return snake.get_length()


	return 10


# =========================================================
# العودة إلى اللوبي
# =========================================================

func _back_to_lobby() -> void:

	var network := get_node_or_null(
		"/root/Network"
	)

	if network:

		if network.has_method(
			"close_connection"
		):

			network.close_connection()


	get_tree().change_scene_to_file(
		"res://scenes/lobby.tscn"
	)


# =========================================================
# شكل الطعام
# =========================================================

class FoodVisual extends Node2D:

	var radius: float = 10.0


	func _ready() -> void:

		queue_redraw()


	func _process(_delta: float) -> void:

		queue_redraw()


	func _draw() -> void:

		# الهالة

		draw_circle(
			Vector2.ZERO,
			radius + 6.0,
			Color(
				1.0,
				0.82,
				0.05,
				0.14
			)
		)


		# جسم العملة/الطعام

		draw_circle(
			Vector2.ZERO,
			radius,
			Color("#FACC15")
		)


		# الحلقة الداخلية

		draw_arc(
			Vector2.ZERO,
			radius - 2.0,
			0.0,
			TAU,
			24,
			Color("#EAB308"),
			2.0
		)


		# اللمعة

		draw_circle(
			Vector2(
				-3.0,
				-3.0
			),
			radius * 0.28,
			Color.WHITE
		)
