extends Node2D

# =========================================================
# 🐍 SNAKE ARAB ONLINE
# الخطوة 6.4
# الحركة + الجسم + الاصطدام + الموت
# =========================================================

# =========================================================
# اللاعب
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
# الجسم
# =========================================================

var body: Array[Vector2] = []

var starting_length: int = 10
var body_count: int = 10

var segment_distance: float = 24.0

# =========================================================
# الاصطدام
# =========================================================

var collision_enabled: bool = true

var self_collision_distance: float = 24.0

var collision_cooldown: float = 0.0

const COLLISION_START_INDEX := 5

# =========================================================
# الموت
# =========================================================

var is_dead: bool = false

var death_position: Vector2 = Vector2.ZERO

# =========================================================
# اللمس
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
# تحديث
# =========================================================

func _process(delta: float) -> void:

	if is_dead:

		queue_redraw()

		return


	if collision_cooldown > 0.0:

		collision_cooldown -= delta


	if not movement_enabled:

		queue_redraw()

		return


	# التحكم

	_read_keyboard()


	# الاتجاه

	if target_direction.length_squared() > 0.0:

		direction = target_direction.normalized()


	# التعزيز

	boosting = Input.is_action_pressed("boost")


	var current_speed := speed

	if boosting:

		current_speed = boost_speed


	# الحركة

	global_position += (
		direction
		* current_speed
		* delta
	)


	# تحديث الجسم

	_update_body()


	# فحص الاصطدام

	if collision_enabled:

		_check_self_collision()


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


	# منع الرجوع للخلف

	if new_direction.dot(direction) < -0.5:

		return


	target_direction = new_direction


# =========================================================
# التحكم باللمس
# =========================================================

func _unhandled_input(event: InputEvent) -> void:

	if is_dead:

		return


	if event is InputEventScreenTouch:

		if event.pressed:

			touch_start = event.position

			touching = true

		else:

			if touching:

				var swipe := (
					event.position
					- touch_start
				)

				if swipe.length() >= swipe_threshold:

					_process_swipe(swipe)

				touching = false


	elif event is InputEventScreenDrag:

		if touching:

			var swipe := (
				event.position
				- touch_start
			)

			if swipe.length() >= swipe_threshold:

				_process_swipe(swipe)

				touch_start = event.position


# =========================================================
# تحليل السحب
# =========================================================

func _process_swipe(swipe: Vector2) -> void:

	if swipe.length_squared() < (
		swipe_threshold
		* swipe_threshold
	):

		return


	if abs(swipe.x) > abs(swipe.y):

		if swipe.x > 0.0:

			_set_direction(
				Vector2.RIGHT
			)

		else:

			_set_direction(
				Vector2.LEFT
			)

	else:

		if swipe.y > 0.0:

			_set_direction(
				Vector2.DOWN
			)

		else:

			_set_direction(
				Vector2.UP
			)


# =========================================================
# تحديث الجسم
# =========================================================

func _update_body() -> void:

	if body.is_empty():

		body.append(
			global_position
		)


	body[0] = global_position


	for i in range(1, body.size()):

		var previous_position: Vector2 = (
			body[i - 1]
		)

		var current_position: Vector2 = (
			body[i]
		)

		var distance := (
			current_position.distance_to(
				previous_position
			)
		)


		if distance > segment_distance:

			var direction_to_previous := (
				previous_position
				- current_position
			).normalized()


			var target_position := (
				previous_position
				- direction_to_previous
				* segment_distance
			)


			current_position = (
				current_position.lerp(
					target_position,
					0.45
				)
			)


		body[i] = current_position


# =========================================================
# زيادة الطول
# =========================================================

func grow(amount: int = 1) -> void:

	if amount <= 0:

		return


	if body.is_empty():

		body.append(
			global_position
		)


	for i in range(amount):

		var tail_position: Vector2 = (
			body.back()
		)

		body.append(
			tail_position
		)


	body_count = body.size()

	queue_redraw()


# =========================================================
# فحص اصطدام الثعبان بنفسه
# =========================================================

func _check_self_collision() -> void:

	if is_dead:

		return


	if collision_cooldown > 0.0:

		return


	if body.size() <= COLLISION_START_INDEX:

		return


	var head_position := global_position


	for i in range(
		COLLISION_START_INDEX,
		body.size()
	):

		var segment_position := body[i]

		var distance := (
			head_position.distance_to(
				segment_position
			)
		)


		if distance <= self_collision_distance:

			die(
				"اصطدمت بنفسك"
			)

			return


# =========================================================
# اصطدام بثعبان آخر
# =========================================================

func check_collision_with_snake(
	other_snake: Node2D
) -> bool:

	if is_dead:

		return false


	if other_snake == null:

		return false


	if other_snake == self:

		return false


	if not other_snake.has_method(
		"get_body_positions"
	):

		return false


	var other_body = (
		other_snake.get_body_positions()
	)


	if other_body.is_empty():

		return false


	var head_position := global_position


	# فحص رأس اللاعب مع جسم الخصم

	for i in range(
		3,
		other_body.size()
	):

		var distance := (
			head_position.distance_to(
				other_body[i]
			)
		)


		if distance <= 30.0:

			die(
				"اصطدمت بلاعب آخر"
			)

			return true


	return false


# =========================================================
# الموت
# =========================================================

func die(reason: String = "انتهت اللعبة") -> void:

	if is_dead:

		return


	is_dead = true

	movement_enabled = false

	boosting = false

	death_position = global_position


	# إرسال إشارة إلى Game

	var parent := get_parent()

	if parent and parent.has_method(
		"snake_died"
	):

		parent.snake_died(
			self,
			reason
		)


	queue_redraw()


# =========================================================
# إعادة الحياة
# =========================================================

func revive(
	start_position: Vector2
) -> void:

	global_position = start_position

	direction = Vector2.RIGHT

	target_direction = Vector2.RIGHT

	is_dead = false

	movement_enabled = true

	boosting = false

	body.clear()


	for i in range(starting_length):

		body.append(
			global_position
			- direction
			* segment_distance
			* i
		)


	body_count = body.size()

	collision_cooldown = 1.5

	queue_redraw()


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

	if not is_dead:

		movement_enabled = true


# =========================================================
# طول الثعبان
# =========================================================

func get_length() -> int:

	return body.size()


# =========================================================
# موقع الرأس
# =========================================================

func get_head_position() -> Vector2:

	return global_position


# =========================================================
# الجسم
# =========================================================

func get_body_positions() -> Array[Vector2]:

	return body


# =========================================================
# هل اللاعب ميت؟
# =========================================================

func get_is_dead() -> bool:

	return is_dead


# =========================================================
# الاسم
# =========================================================

func get_player_name() -> String:

	return player_name


# =========================================================
# السرعة
# =========================================================

func set_speed(new_speed: float) -> void:

	speed = max(
		0.0,
		new_speed
	)


# =========================================================
# سرعة التعزيز
# =========================================================

func set_boost_speed(new_speed: float) -> void:

	boost_speed = max(
		0.0,
		new_speed
	)


# =========================================================
# إعادة الثعبان
# =========================================================

func reset_snake(
	start_position: Vector2 = Vector2.ZERO
) -> void:

	if start_position != Vector2.ZERO:

		global_position = start_position


	direction = Vector2.RIGHT

	target_direction = Vector2.RIGHT

	boosting = false

	movement_enabled = true

	is_dead = false

	collision_cooldown = 1.0

	body.clear()


	for i in range(starting_length):

		body.append(
			global_position
			- direction
			* segment_distance
			* i
		)


	body_count = body.size()

	queue_redraw()


# =========================================================
# الرسم
# =========================================================

func _draw() -> void:

	if body.is_empty():

		return


	# =====================================================
	# الجسم
	# =====================================================

	for i in range(
		body.size() - 1,
		0,
		-1
	):

		var segment_position := (
			to_local(body[i])
		)


		var segment_size := 20.0


		if i <= 2:

			segment_size = 22.0


		# الظل

		draw_circle(
			segment_position
			+ Vector2(2.0, 3.0),
			segment_size,
			Color(
				0.0,
				0.0,
				0.0,
				0.25
			)
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
	# الرأس
	# =====================================================

	var head_color := Color("#4ADE80")


	if is_dead:

		head_color = Color("#6B7280")


	draw_circle(
		Vector2(2.0, 4.0),
		29.0,
		Color(
			0.0,
			0.0,
			0.0,
			0.25
		)
	)


	draw_circle(
		Vector2.ZERO,
		27.0,
		head_color
	)


	draw_circle(
		Vector2.ZERO,
		22.0,
		Color("#22C55E")
	)


	# =====================================================
	# العيون
	# =====================================================

	var side := direction.rotated(
		PI / 2.0
	)


	var eye_forward := (
		direction * 10.0
	)


	var eye_side := (
		side * 9.0
	)


	var left_eye := (
		eye_forward + eye_side
	)


	var right_eye := (
		eye_forward - eye_side
	)


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
	# اللمعة
	# =====================================================

	draw_circle(
		left_eye
		+ direction * 3.0
		- Vector2(1.0, 1.0),
		0.9,
		Color.WHITE
	)


	draw_circle(
		right_eye
		+ direction * 3.0
		- Vector2(1.0, 1.0),
		0.9,
		Color.WHITE
	)
