extends Node2D

var player_name := "لاعب"
var direction := Vector2.RIGHT
var target_direction := Vector2.RIGHT

var speed := 260.0
var boost_speed := 430.0

var boosting := false

var body: Array[Vector2] = []
var body_count := 10

var segment_distance := 24.0
var last_segment_position := Vector2.ZERO

var touch_start := Vector2.ZERO
var touching := false


func _ready() -> void:
	body_count = 10

	for i in range(body_count):
		body.append(
			position - direction * segment_distance * i
		)

	queue_redraw()


func _process(delta: float) -> void:
	_read_keyboard()

	if target_direction.length() > 0.0:
		direction = target_direction.normalized()

	boosting = Input.is_action_pressed("boost")

	var current_speed := boost_speed if boosting else speed

	position += direction * current_speed * delta

	_update_body()

	queue_redraw()


# =========================================================
# INPUT
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


func _set_direction(new_direction: Vector2) -> void:

	if new_direction == -direction:
		return

	target_direction = new_direction


func _unhandled_input(event: InputEvent) -> void:

	if event is InputEventScreenTouch:

		if event.pressed:
			touch_start = event.position
			touching = true
		else:
			if touching:
				var swipe := event.position - touch_start

				if swipe.length() > 30.0:
					_process_swipe(swipe)

				touching = false

	elif event is InputEventScreenDrag:

		if touching:
			var swipe := event.position - touch_start

			if swipe.length() > 40.0:
				_process_swipe(swipe)
				touch_start = event.position


func _process_swipe(swipe: Vector2) -> void:

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
# BODY
# =========================================================

func _update_body() -> void:

	if body.is_empty():
		body.append(global_position)

	body[0] = global_position

	for i in range(1, body.size()):

		var previous := body[i - 1]
		var current := body[i]

		var distance := current.distance_to(previous)

		if distance > segment_distance:
			current = current.lerp(
				previous,
				min(1.0, (distance - segment_distance) / 10.0)
			)

		body[i] = current


# =========================================================
# GROW
# =========================================================

func grow(amount: int = 1) -> void:

	for i in range(amount):

		var tail := body.back()

		body.append(tail)

	body_count = body.size()


func get_length() -> int:
	return body.size()


# =========================================================
# DRAW
# =========================================================

func _draw() -> void:

	if body.is_empty():
		return

	# الجسم
	for i in range(body.size() - 1, 0, -1):

		var local_position := to_local(body[i])

		var size := 20.0

		if i < 3:
			size = 22.0

		draw_circle(
			local_position,
			size,
			Color("#22C55E")
		)

		draw_circle(
			local_position,
			size - 4.0,
			Color("#16A34A")
		)

	# الرأس
	draw_circle(
		Vector2.ZERO,
		27.0,
		Color("#4ADE80")
	)

	draw_circle(
		Vector2.ZERO,
		22.0,
		Color("#22C55E")
	)

	# العينان
	var side := direction.rotated(PI / 2.0)

	var eye_forward := direction * 10.0
	var eye_side := side * 9.0

	draw_circle(
		eye_forward + eye_side,
		5.0,
		Color.WHITE
	)

	draw_circle(
		eye_forward - eye_side,
		5.0,
		Color.WHITE
	)

	draw_circle(
		eye_forward + eye_side + direction * 2.0,
		2.5,
		Color.BLACK
	)

	draw_circle(
		eye_forward - eye_side + direction * 2.0,
		2.5,
		Color.BLACK
	)
