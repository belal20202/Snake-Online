extends Node2D

var player_name: String = "لاعب"

var direction: Vector2 = Vector2.RIGHT
var target_direction: Vector2 = Vector2.RIGHT

var speed: float = 260.0
var boost_speed: float = 430.0

var boosting: bool = false

var body: Array[Vector2] = []
var body_count: int = 10

var segment_distance: float = 24.0

var touch_start: Vector2 = Vector2.ZERO
var touching: bool = false


func _ready() -> void:
	if body.is_empty():
		_initialize_body()

	queue_redraw()


func setup(new_name: String) -> void:

	player_name = new_name.strip_edges()

	if player_name.is_empty():
		player_name = "لاعب"

	body.clear()
	body_count = 10

	_initialize_body()

	queue_redraw()


func _initialize_body() -> void:

	for i in range(body_count):

		body.append(
			global_position -
			direction * segment_distance * i
		)


func _physics_process(delta: float) -> void:

	_read_keyboard()

	if target_direction.length_squared() > 0.01:
		direction = target_direction.normalized()

	boosting = Input.is_action_pressed("boost")

	var current_speed := boost_speed if boosting else speed

	global_position += direction * current_speed * delta

	_update_body()

	queue_redraw()


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

	target_direction = new_direction.normalized()


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


func grow(amount: int = 1) -> void:

	if amount <= 0:
		return

	for i in range(amount):

		if body.is_empty():
			body.append(global_position)
		else:
			body.append(body.back())

	body_count = body.size()

	queue_redraw()


func get_length() -> int:

	return body.size()


func _draw() -> void:

	if body.is_empty():
		return

	# الجسم
	for i in range(body.size() - 1, 0, -1):

		var local_position := to_local(body[i])

		var radius := 20.0

		if i < 3:
			radius = 22.0

		draw_circle(
			local_position,
			radius,
			Color("#22C55E")
		)

		draw_circle(
			local_position,
			radius - 4.0,
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
