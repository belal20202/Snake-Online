extends Node2D

# =========================================================
# 🐍 SNAKE ARAB ONLINE
# نظام حركة الثعبان - الخطوة 6.1
# =========================================================

# =========================================================
# معلومات اللاعب
# =========================================================

var player_name: String = "لاعب"

# =========================================================
# الحركة
# =========================================================

var direction: Vector2 = Vector2.RIGHT
var target_direction: Vector2 = Vector2.RIGHT

var speed: float = 260.0
var boost_speed: float = 430.0

var boosting: bool = false
var movement_enabled: bool = true

# =========================================================
# جسم الثعبان
# =========================================================

var body: Array[Vector2] = []

var starting_length: int = 10
var body_count: int = 10

var segment_distance: float = 24.0

# =========================================================
# اللمس للموبايل
# =========================================================

var touch_start: Vector2 = Vector2.ZERO
var touching: bool = false

var swipe_threshold: float = 35.0

# =========================================================
# إعداد اللاعب
# =========================================================

func setup(new_player_name: String) -> void:

	player_name = new_player_name

	if player_name.strip_edges().is_empty():
		player_name = "لاعب"

# =========================================================
# البداية
# =========================================================

func _ready() -> void:

	body.clear()

	body_count = starting_length

	for i in range(body_count):

		var segment_position := (
			global_position
			- direction * segment_distance * i
		)

		body.append(segment_position)

	queue_redraw()

# =========================================================
# التحديث
# =========================================================

func _process(delta: float) -> void:

	if not movement_enabled:
		queue_redraw()
		return

	# قراءة لوحة المفاتيح
	_read_keyboard()

	# تطبيق الاتجاه المطلوب
	if target_direction.length_squared() > 0.0:

		direction = target_direction.normalized()

	# السرعة
	boosting = Input.is_action_pressed("boost")

	var current_speed: float

	if boosting:
		current_speed = boost_speed
	else:
		current_speed = speed

	# الحركة
	global_position += direction * current_speed * delta

	# تحديث الجسم
	_update_body()

	queue_redraw()

# =========================================================
# التحكم بالكيبورد
# =========================================================

func _read_keyboard() -> void:

	if Input.is_action_pressed("move_up"):
		_set_direction(Vector2.UP)

	elif Input.is_action_pressed("move_down"):
		_set_direction(Vector2.DOWN)

	elif Input.is_action_pressed("move_left"):
		_set_direction(Vector2.LEFT)

	elif Input.is_action_pressed("move_right"):
		_set_direction(Vector2.RIGHT)

# =========================================================
# تغيير الاتجاه
# =========================================================

func _set_direction(new_direction: Vector2) -> void:

	if new_direction == Vector2.ZERO:
		return

	new_direction = new_direction.normalized()

	# منع الدوران 180 درجة مباشرة
	if new_direction == -direction:
		return

	target_direction = new_direction

# =========================================================
# تحكم الموبايل
# =========================================================

func _unhandled_input(event: InputEvent) -> void:

	if not movement_enabled:
		return

	# بداية اللمس
	if event is InputEventScreenTouch:

		if event.pressed:

			touch_start = event.position
			touching = true

		else:

			if touching:

				var swipe := event.position - touch_start

				if swipe.length() >= swipe_threshold:
					_process_swipe(swipe)

				touching = false

	# السحب على الشاشة
	elif event is InputEventScreenDrag:

		if touching:

			var swipe := event.position - touch_start

			if swipe.length() >= swipe_threshold:

				_process_swipe(swipe)

				touch_start = event.position

# =========================================================
# تحليل السحب
# =========================================================

func _process_swipe(swipe: Vector2) -> void:

	if swipe.length_squared() < swipe_threshold * swipe_threshold:
		return

	# حركة أفقية
	if abs(swipe.x) > abs(swipe.y):

		if swipe.x > 0.0:
			_set_direction(Vector2.RIGHT)
		else:
			_set_direction(Vector2.LEFT)

	# حركة عمودية
	else:

		if swipe.y > 0.0:
			_set_direction(Vector2.DOWN)
		else:
			_set_direction(Vector2.UP)

# =========================================================
# تحديث جسم الثعبان
# =========================================================

func _update_body() -> void:

	if body.is_empty():

		body.append(global_position)

	# الرأس
	body[0] = global_position

	# بقية الجسم
	for i in range(1, body.size()):

		var previous_position: Vector2 = body[i - 1]
		var current_position: Vector2 = body[i]

		var distance := current_position.distance_to(previous_position)

		if distance > segment_distance:

			var direction_to_previous := (
				previous_position - current_position
			).normalized()

			var target_position := (
				previous_position
				- direction_to_previous * segment_distance
			)

			current_position = current_position.lerp(
				target_position,
				0.35
			)

		body[i] = current_position

# =========================================================
# زيادة طول الثعبان
# =========================================================

func grow(amount: int = 1) -> void:

	if amount <= 0:
		return

	if body.is_empty():
		body.append(global_position)

	for i in range(amount):

		var tail_position: Vector2 = body.back()

		body.append(tail_position)

	body_count = body.size()

	queue_redraw()

# =========================================================
# الحصول على طول الثعبان
# =========================================================

func get_length() -> int:

	return body.size()

# =========================================================
# الحصول على الرأس
# =========================================================

func get_head_position() -> Vector2:

	return global_position

# =========================================================
# الحصول على الجسم
# =========================================================

func get_body_positions() -> Array[Vector2]:

	return body

# =========================================================
# إيقاف الحركة
# =========================================================

func stop_movement() -> void:

	movement_enabled = false
	boosting = false

# =========================================================
# تشغيل الحركة
# =========================================================

func resume_movement() -> void:

	movement_enabled = true

# =========================================================
# تغيير السرعة
# =========================================================

func set_speed(new_speed: float) -> void:

	speed = max(0.0, new_speed)

# =========================================================
# تغيير سرعة التعزيز
# =========================================================

func set_boost_speed(new_speed: float) -> void:

	boost_speed = max(0.0, new_speed)

# =========================================================
# إعادة الثعبان
# =========================================================

func reset_snake(start_position: Vector2 = Vector2.ZERO) -> void:

	if start_position != Vector2.ZERO:
		global_position = start_position

	direction = Vector2.RIGHT
	target_direction = Vector2.RIGHT

	boosting = false
	movement_enabled = true

	body.clear()

	body_count = starting_length

	for i in range(body_count):

		body.append(
			global_position
			- direction * segment_distance * i
		)

	queue_redraw()

# =========================================================
# الرسم
# =========================================================

func _draw() -> void:

	if body.is_empty():
		return

	# =====================================================
	# جسم الثعبان
	# =====================================================

	for i in range(body.size() - 1, 0, -1):

		var segment_position := to_local(body[i])

		var segment_size: float = 20.0

		# المقاطع القريبة من الرأس أكبر قليلًا
		if i <= 2:
			segment_size = 22.0

		# الظل
		draw_circle(
			segment_position + Vector2(2.0, 3.0),
			segment_size,
			Color(0.0, 0.0, 0.0, 0.25)
		)

		# اللون الخارجي
		draw_circle(
			segment_position,
			segment_size,
			Color("#22C55E")
		)

		# اللون الداخلي
		draw_circle(
			segment_position,
			segment_size - 4.0,
			Color("#16A34A")
		)

	# =====================================================
	# رأس الثعبان
	# =====================================================

	# ظل الرأس
	draw_circle(
		Vector2(2.0, 4.0),
		29.0,
		Color(0.0, 0.0, 0.0, 0.25)
	)

	# الرأس الخارجي
	draw_circle(
		Vector2.ZERO,
		27.0,
		Color("#4ADE80")
	)

	# الرأس الداخلي
	draw_circle(
		Vector2.ZERO,
		22.0,
		Color("#22C55E")
	)

	# =====================================================
	# العينان
	# =====================================================

	var side := direction.rotated(PI / 2.0)

	var eye_forward := direction * 10.0
	var eye_side := side * 9.0

	var left_eye := eye_forward + eye_side
	var right_eye := eye_forward - eye_side

	# بياض العين
	draw_circle(
		left_eye,
		5.5,
		Color.WHITE
	)

	draw_circle(
		right_eye,
		5.5,
		Color.WHITE
	)

	# بؤبؤ العين
	draw_circle(
		left_eye + direction * 2.0,
		2.7,
		Color.BLACK
	)

	draw_circle(
		right_eye + direction * 2.0,
		2.7,
		Color.BLACK
	)

	# =====================================================
	# لمعان العين
	# =====================================================

	draw_circle(
		left_eye + direction * 3.0 - Vector2(1.0, 1.0),
		0.9,
		Color.WHITE
	)

	draw_circle(
		right_eye + direction * 3.0 - Vector2(1.0, 1.0),
		0.9,
		Color.WHITE
	)
