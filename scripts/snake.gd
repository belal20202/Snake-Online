extends Node2D

# =========================================================
# SNAKE ARAB ONLINE
# 6.6.12 - BOOST SYSTEM
# =========================================================

# =========================================================
# PLAYER
# =========================================================

var player_name: String = "لاعب"

# =========================================================
# MOVEMENT
# =========================================================

var direction: Vector2 = Vector2.RIGHT
var target_direction: Vector2 = Vector2.RIGHT

var speed: float = 260.0
var boost_speed: float = 430.0

var boosting: bool = false
var movement_enabled: bool = true

# مقدار التنعيم عند تغيير الاتجاه
var direction_smoothing: float = 12.0

# =========================================================
# BOOST SETTINGS
# =========================================================

# أقل طول يسمح باستخدام الـBoost
const BOOST_MIN_LENGTH := 8

# مقدار الطول الذي يتم استهلاكه
const BOOST_COST_INTERVAL := 0.15

# كم Segment يتم استهلاكها في كل مرة
const BOOST_COST_AMOUNT := 1

# الحد الأدنى بين عمليات الاستهلاك
var boost_cost_timer: float = 0.0

# هل زر الـBoost مضغوط؟
var boost_pressed: bool = false

# =========================================================
# BODY
# =========================================================

var body: Array[Vector2] = []

var starting_length: int = 10
var body_count: int = 10

var segment_distance: float = 24.0

# =========================================================
# COLLISION
# =========================================================

var collision_enabled: bool = true

const COLLISION_START_INDEX := 5

# =========================================================
# STATE
# =========================================================

var is_dead: bool = false
var death_position: Vector2 = Vector2.ZERO

# =========================================================
# TOUCH
# =========================================================

var touch_start_position: Vector2 = Vector2.ZERO
var touch_current_position: Vector2 = Vector2.ZERO

var touch_active: bool = false

const TOUCH_MIN_DISTANCE := 35.0

# =========================================================
# VISUAL
# =========================================================

var body_radius: float = 14.0
var head_radius: float = 17.0

var snake_color := Color(
	0.15,
	0.75,
	0.95,
	1.0
)

# =========================================================
# READY
# =========================================================

func _ready() -> void:

	set_process(true)

	body_count = starting_length

	_create_initial_body()

	queue_redraw()


# =========================================================
# SETUP
# =========================================================

func setup(
	new_player_name: String = "لاعب"
) -> void:

	player_name = new_player_name

	body_count = starting_length

	direction = Vector2.RIGHT
	target_direction = Vector2.RIGHT

	boosting = false
	boost_pressed = false

	is_dead = false
	movement_enabled = true

	boost_cost_timer = 0.0

	_create_initial_body()

	queue_redraw()


# =========================================================
# PROCESS
# =========================================================

func _process(delta: float) -> void:

	if is_dead:
		return

	if not movement_enabled:
		return

	_handle_keyboard_input()
	_update_direction(delta)
	_update_boost(delta)
	_move_snake(delta)
	_update_body()

	_check_self_collision()

	queue_redraw()


# =========================================================
# KEYBOARD INPUT
# =========================================================

func _handle_keyboard_input() -> void:

	var input_direction := Vector2.ZERO

	if Input.is_action_pressed("move_up"):
		input_direction = Vector2.UP

	elif Input.is_action_pressed("move_down"):
		input_direction = Vector2.DOWN

	elif Input.is_action_pressed("move_left"):
		input_direction = Vector2.LEFT

	elif Input.is_action_pressed("move_right"):
		input_direction = Vector2.RIGHT

	if input_direction != Vector2.ZERO:
		_set_direction(input_direction)

	# -----------------------------------------------------
	# BOOST - SPACE
	# -----------------------------------------------------

	boost_pressed = Input.is_action_pressed("boost")


# =========================================================
# DIRECTION
# =========================================================

func _set_direction(
	new_direction: Vector2
) -> void:

	if new_direction.length() <= 0.01:
		return

	new_direction = new_direction.normalized()

	# منع الدوران 180 درجة مباشرة
	if direction.dot(new_direction) < -0.8:
		return

	target_direction = new_direction


func _update_direction(delta: float) -> void:

	if target_direction.length() <= 0.01:
		return

	var factor := min(
		1.0,
		direction_smoothing * delta
	)

	direction = direction.lerp(
		target_direction,
		factor
	)

	if direction.length() > 0.01:
		direction = direction.normalized()


# =========================================================
# BOOST
# =========================================================

func _update_boost(delta: float) -> void:

	boost_cost_timer += delta

	# لا يمكن استخدام الـBoost إذا كان الطول قليلًا
	if body_count < BOOST_MIN_LENGTH:

		boosting = false

		return

	# -----------------------------------------------------
	# تفعيل / إلغاء Boost
	# -----------------------------------------------------

	if boost_pressed:

		boosting = true

	else:

		boosting = false

	# -----------------------------------------------------
	# استهلاك الطول
	# -----------------------------------------------------

	if boosting:

		if boost_cost_timer >= BOOST_COST_INTERVAL:

			boost_cost_timer = 0.0

			_consume_boost_length()


func _consume_boost_length() -> void:

	if body_count <= BOOST_MIN_LENGTH:
		boosting = false
		return

	body_count = max(
		BOOST_MIN_LENGTH,
		body_count - BOOST_COST_AMOUNT
	)

	# تحديث الجسم مباشرة
	_trim_body()


# =========================================================
# MOVEMENT
# =========================================================

func _move_snake(delta: float) -> void:

	var current_speed := speed

	if boosting:
		current_speed = boost_speed

	var movement := direction * current_speed * delta

	position += movement


# =========================================================
# INITIAL BODY
# =========================================================

func _create_initial_body() -> void:

	body.clear()

	var safe_length := max(
		BOOST_MIN_LENGTH,
		body_count
	)

	for i in range(safe_length):

		var segment_position := (
			position
			- direction
			* (
				float(i)
				* segment_distance
			)
		)

		body.append(
			segment_position
		)


# =========================================================
# BODY UPDATE
# =========================================================

func _update_body() -> void:

	if body.is_empty():
		_create_initial_body()
		return

	# الرأس
	body[0] = position

	var safe_direction := direction

	if safe_direction.length() <= 0.01:
		safe_direction = Vector2.RIGHT

	safe_direction = safe_direction.normalized()

	# باقي الجسم يتبع الرأس
	for i in range(1, body.size()):

		var previous_position: Vector2 = body[i - 1]

		var current_position: Vector2 = body[i]

		var desired_position := (
			previous_position
			- safe_direction
			* segment_distance
		)

		current_position = current_position.lerp(
			desired_position,
			0.35
		)

		body[i] = current_position

	# التأكد من عدد الأجزاء
	while body.size() > body_count:
		body.pop_back()

	while body.size() < body_count:

		var last_position := body.back()

		body.append(
			last_position
			- safe_direction
			* segment_distance
		)


# =========================================================
# TRIM BODY
# =========================================================

func _trim_body() -> void:

	while body.size() > body_count:
		body.pop_back()

	queue_redraw()


# =========================================================
# GROW
# =========================================================

func grow(amount: int = 1) -> void:

	if amount <= 0:
		return

	body_count += amount

	body_count = clamp(
		body_count,
		BOOST_MIN_LENGTH,
		10000
	)

	# إضافة أجزاء جديدة
	while body.size() < body_count:

		var safe_direction := direction

		if safe_direction.length() <= 0.01:
			safe_direction = Vector2.RIGHT

		safe_direction = safe_direction.normalized()

		var last_position := body.back()

		body.append(
			last_position
			- safe_direction
			* segment_distance
		)

	queue_redraw()


# =========================================================
# SELF COLLISION
# =========================================================

func _check_self_collision() -> void:

	if not collision_enabled:
		return

	if body.size() <= COLLISION_START_INDEX:
		return

	var head_position := position

	for i in range(
		COLLISION_START_INDEX,
		body.size()
	):

		var segment_position := body[i]

		if head_position.distance_to(
			segment_position
		) <= body_radius * 1.5:

			die("self_collision")

			return


# =========================================================
# COLLISION WITH OTHER SNAKE
# =========================================================

func check_collision_with_snake(
	other_snake: Node
) -> bool:

	if other_snake == null:
		return false

	if not is_instance_valid(other_snake):
		return false

	if is_dead:
		return false

	if not other_snake.has_method(
		"get_body_positions"
	):
		return false

	var other_body: Array = (
		other_snake.get_body_positions()
	)

	if other_body.is_empty():
		return false

	for segment_position in other_body:

		if position.distance_to(
			segment_position
		) <= 30.0:

			return true

	return false


# =========================================================
# GET BODY
# =========================================================

func get_body_positions() -> Array[Vector2]:

	return body.duplicate()


# =========================================================
# DEATH
# =========================================================

func die(
	reason: String = "collision"
) -> void:

	if is_dead:
		return

	is_dead = true

	boosting = false
	boost_pressed = false

	death_position = position

	movement_enabled = false

	if get_parent() != null:

		var parent_node := get_parent()

		if parent_node.has_method(
			"snake_died"
		):

			parent_node.snake_died(
				self,
				reason
			)

	queue_redraw()


# =========================================================
# REVIVE
# =========================================================

func revive() -> void:

	is_dead = false

	boosting = false
	boost_pressed = false

	boost_cost_timer = 0.0

	movement_enabled = true

	body_count = starting_length

	direction = Vector2.RIGHT
	target_direction = Vector2.RIGHT

	_create_initial_body()

	queue_redraw()


# =========================================================
# STOP
# =========================================================

func stop_movement() -> void:

	movement_enabled = false

	boosting = false
	boost_pressed = false


# =========================================================
# RESUME
# =========================================================

func resume_movement() -> void:

	if not is_dead:
		movement_enabled = true


# =========================================================
# TOUCH CONTROLS
# =========================================================

func _input(event: InputEvent) -> void:

	if is_dead:
		return

	# -----------------------------------------------------
	# TOUCH
	# -----------------------------------------------------

	if event is InputEventScreenTouch:

		if event.pressed:

			touch_active = true

			touch_start_position = event.position
			touch_current_position = event.position

		else:

			touch_active = false

			var swipe := (
				event.position
				- touch_start_position
			)

			if swipe.length() >= TOUCH_MIN_DISTANCE:

				_process_swipe(swipe)


	# -----------------------------------------------------
	# TOUCH DRAG
	# -----------------------------------------------------

	elif event is InputEventScreenDrag:

		if touch_active:

			touch_current_position = event.position

			var swipe := (
				touch_current_position
				- touch_start_position
			)

			if swipe.length() >= TOUCH_MIN_DISTANCE:

				_process_swipe(swipe)

				touch_start_position = (
					touch_current_position
				)


# =========================================================
# SWIPE
# =========================================================

func _process_swipe(
	swipe: Vector2
) -> void:

	if abs(swipe.x) > abs(swipe.y):

		if swipe.x > 0:
			_set_direction(Vector2.RIGHT)
		else:
			_set_direction(Vector2.LEFT)

	else:

		if swipe.y > 0:
			_set_direction(Vector2.DOWN)
		else:
			_set_direction(Vector2.UP)


# =========================================================
# MOBILE BOOST
# =========================================================

func set_boost_pressed(
	pressed: bool
) -> void:

	boost_pressed = pressed

	if not pressed:
		boosting = false


func start_boost() -> void:

	if is_dead:
		return

	if body_count < BOOST_MIN_LENGTH:
		return

	boost_pressed = true
	boosting = true


func stop_boost() -> void:

	boost_pressed = false
	boosting = false


func is_boosting() -> bool:

	return boosting


# =========================================================
# GETTERS
# =========================================================

func get_direction() -> Vector2:

	return direction


func get_length() -> int:

	return body_count


func get_speed() -> float:

	if boosting:
		return boost_speed

	return speed


func get_position() -> Vector2:

	return position


func is_snake_dead() -> bool:

	return is_dead


func get_player_name() -> String:

	return player_name


# =========================================================
# SETTERS
# =========================================================

func set_speed(
	new_speed: float
) -> void:

	speed = max(
		1.0,
		new_speed
	)


func set_boost_speed(
	new_speed: float
) -> void:

	boost_speed = max(
		speed,
		new_speed
	)


func set_player_name(
	new_name: String
) -> void:

	player_name = new_name


# =========================================================
# RESET
# =========================================================

func reset() -> void:

	is_dead = false

	movement_enabled = true

	boosting = false
	boost_pressed = false

	boost_cost_timer = 0.0

	body_count = starting_length

	direction = Vector2.RIGHT
	target_direction = Vector2.RIGHT

	_create_initial_body()

	queue_redraw()


# =========================================================
# DRAW
# =========================================================

func _draw() -> void:

	if is_dead:
		return

	if body.is_empty():
		return

	# -----------------------------------------------------
	# BODY
	# -----------------------------------------------------

	for i in range(
		body.size() - 1,
		0,
		-1
	):

		var world_position: Vector2 = body[i]

		var local_position := (
			world_position
			- position
		)

		var progress := float(i) / max(
			1.0,
			float(body.size())
		)

		var radius := lerp(
			body_radius,
			body_radius * 0.72,
			progress
		)

		var current_color := snake_color

		# تأثير بسيط أثناء الـBoost
		if boosting:
			current_color = current_color.lightened(
				0.12
			)

		draw_circle(
			local_position,
			radius,
			current_color
		)

	# -----------------------------------------------------
	# HEAD
	# -----------------------------------------------------

	var head_color := snake_color

	if boosting:
		head_color = head_color.lightened(
			0.18
		)

	draw_circle(
		Vector2.ZERO,
		head_radius,
		head_color
	)

	# -----------------------------------------------------
	# BOOST EFFECT
	# -----------------------------------------------------

	if boosting:

		draw_circle(
			Vector2.ZERO,
			head_radius + 5.0,
			Color(
				1.0,
				0.85,
				0.25,
				0.20
			),
			false,
			3.0
		)

	# -----------------------------------------------------
	# HEAD HIGHLIGHT
	# -----------------------------------------------------

	draw_circle(
		Vector2(
			-5,
			-5
		),
		5,
		Color(
			1.0,
			1.0,
			1.0,
			0.20
		)
	)

	# -----------------------------------------------------
	# EYES
	# -----------------------------------------------------

	var forward := direction

	if forward.length() <= 0.01:
		forward = Vector2.RIGHT

	forward = forward.normalized()

	var side := Vector2(
		-forward.y,
		forward.x
	)

	var eye_forward_distance := 7.0
	var eye_side_distance := 6.0

	var left_eye_position := (
		forward
		* eye_forward_distance
		+ side
		* eye_side_distance
	)

	var right_eye_position := (
		forward
		* eye_forward_distance
		- side
		* eye_side_distance
	)

	draw_circle(
		left_eye_position,
		4.5,
		Color.WHITE
	)

	draw_circle(
		right_eye_position,
		4.5,
		Color.WHITE
	)

	# -----------------------------------------------------
	# PUPILS
	# -----------------------------------------------------

	var pupil_offset := forward * 2.0

	draw_circle(
		left_eye_position + pupil_offset,
		2.2,
		Color(
			0.02,
			0.02,
			0.02,
			1.0
		)
	)

	draw_circle(
		right_eye_position + pupil_offset,
		2.2,
		Color(
			0.02,
			0.02,
			0.02,
			1.0
		)
	)
