extends Node2D

# =========================================================
# 🐍 SNAKE ARAB ONLINE
# الخطوة 6.2
# نظام الطعام + النقاط + زيادة طول الثعبان
# =========================================================

# =========================================================
# إعدادات الخريطة
# =========================================================

const MAP_SIZE := Vector2(4000.0, 4000.0)

const MAP_MARGIN := 120.0

# =========================================================
# إعدادات الطعام
# =========================================================

const FOOD_COUNT := 180

const FOOD_RADIUS := 10.0

const FOOD_COLLECT_DISTANCE := 45.0

const FOOD_VALUE := 10

# =========================================================
# اللاعب
# =========================================================

var snake: Node2D = null

# =========================================================
# الطعام
# =========================================================

var foods: Array[Node2D] = []

# =========================================================
# النقاط
# =========================================================

var score: int = 0

var coins: int = 0

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
# إنشاء خلفية الخريطة
# =========================================================

func _create_background() -> void:

	var background := ColorRect.new()

	background.name = "MapBackground"

	background.position = Vector2.ZERO

	background.size = MAP_SIZE

	background.color = Color("#111827")

	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(background)

	move_child(background, 0)


# =========================================================
# رسم الخريطة
# =========================================================

func _draw() -> void:

	# حدود الخريطة

	draw_rect(
		Rect2(
			Vector2.ZERO,
			MAP_SIZE
		),
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


	# إرسال اسم اللاعب للثعبان

	if snake.has_method("setup"):

		var player_name := "لاعب"

		if "player_name" in Global:

			player_name = Global.player_name

		snake.setup(player_name)


# =========================================================
# إنشاء الطعام
# =========================================================

func _create_food() -> void:

	for i in range(FOOD_COUNT):

		_spawn_food()


# =========================================================
# إنشاء قطعة طعام واحدة
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


	# البيانات الخاصة بالطعام

	food.set_meta(
		"radius",
		FOOD_RADIUS
	)

	food.set_meta(
		"value",
		FOOD_VALUE
	)


	add_child(food)

	foods.append(food)


	# الشكل المرئي للطعام

	var visual := FoodVisual.new()

	visual.radius = FOOD_RADIUS

	food.add_child(visual)


# =========================================================
# فحص اصطدام الرأس بالطعام
# =========================================================

func _check_food_collision() -> void:

	if snake == null:
		return


	var head_position := snake.global_position


	# نستخدم نسخة من القائمة
	# حتى نستطيع حذف الطعام أثناء الحلقة

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

			_collect_food(food)


# =========================================================
# جمع الطعام
# =========================================================

func _collect_food(food: Node2D) -> void:

	if not is_instance_valid(food):
		return


	# =====================================================
	# حساب قيمة الطعام
	# =====================================================

	var value := FOOD_VALUE

	if food.has_meta("value"):

		value = int(
			food.get_meta("value")
		)


	# =====================================================
	# زيادة النقاط
	# =====================================================

	score += value


	# =====================================================
	# إضافة عملة داخل اللعبة
	# =====================================================

	coins += 1


	# =====================================================
	# زيادة طول الثعبان
	# =====================================================

	if snake.has_method("grow"):

		snake.grow(1)


	# =====================================================
	# إزالة الطعام القديم
	# =====================================================

	foods.erase(food)

	food.queue_free()


	# =====================================================
	# إنشاء طعام جديد
	# =====================================================

	_spawn_food()


	# =====================================================
	# تحديث الواجهة فورًا
	# =====================================================

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
		390,
		155
	)

	canvas.add_child(top_bar)


	# =====================================================
	# النقاط
	# =====================================================

	score_label = Label.new()

	score_label.name = "ScoreLabel"

	score_label.position = Vector2(
		20,
		12
	)

	score_label.size = Vector2(
		350,
		40
	)

	score_label.text = "النقاط: 0"

	score_label.add_theme_font_size_override(
		"font_size",
		28
	)

	top_bar.add_child(score_label)


	# =====================================================
	# الطول
	# =====================================================

	length_label = Label.new()

	length_label.name = "LengthLabel"

	length_label.position = Vector2(
		20,
		58
	)

	length_label.size = Vector2(
		350,
		35
	)

	length_label.text = "الطول: 10"

	length_label.add_theme_font_size_override(
		"font_size",
		22
	)

	top_bar.add_child(length_label)


	# =====================================================
	# العملات
	# =====================================================

	coins_label = Label.new()

	coins_label.name = "CoinsLabel"

	coins_label.position = Vector2(
		20,
		100
	)

	coins_label.size = Vector2(
		350,
		35
	)

	coins_label.text = "العملات: 0"

	coins_label.add_theme_font_size_override(
		"font_size",
		22
	)

	top_bar.add_child(coins_label)


	# =====================================================
	# زر الإيقاف
	# =====================================================

	pause_button = Button.new()

	pause_button.name = "PauseButton"

	pause_button.position = Vector2(
		1110,
		25
	)

	pause_button.size = Vector2(
		140,
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

	canvas.add_child(pause_button)


	# =====================================================
	# زر الخروج
	# =====================================================

	var exit_button := Button.new()

	exit_button.name = "ExitButton"

	exit_button.position = Vector2(
		1110,
		95
	)

	exit_button.size = Vector2(
		140,
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

	canvas.add_child(exit_button)


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
			"العملات: %d"
			% coins
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


	_show_game_over()


# =========================================================
# شاشة انتهاء اللعبة
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
		200
	)

	game_over_panel.size = Vector2(
		500,
		320
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
	# النتيجة
	# =====================================================

	var result := Label.new()

	result.position = Vector2(
		30,
		100
	)

	result.size = Vector2(
		440,
		80
	)

	result.text = (
		"النقاط: %d\nالطول: %d\nالعملات: %d"
		% [
			score,
			_get_snake_length(),
			coins
		]
	)

	result.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	result.add_theme_font_size_override(
		"font_size",
		23
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
		220
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
# الحصول على طول الثعبان
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

		# هالة بسيطة

		draw_circle(
			Vector2.ZERO,
			radius + 5.0,
			Color(
				0.98,
				0.80,
				0.08,
				0.12
			)
		)


		# الطعام

		draw_circle(
			Vector2.ZERO,
			radius,
			Color("#FACC15")
		)


		# اللمعة

		draw_circle(
			Vector2(
				-3.0,
				-3.0
			),
			radius * 0.30,
			Color.WHITE
		)


		# نقطة صغيرة

		draw_circle(
			Vector2(
				3.0,
				3.0
			),
			radius * 0.12,
			Color(
				0.9,
				0.65,
				0.0,
				0.8
			)
		)
