extends Node2D

var peer_id: int = 0
var player_name: String = "لاعب"

var direction: Vector2 = Vector2.RIGHT
var target_direction: Vector2 = Vector2.RIGHT

var current_position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO

var current_length: int = 10
var target_length: int = 10

var is_alive: bool = true

var interpolation_speed: float = 12.0

var body: Array = []
var target_body: Array = []

var segment_distance: float = 24.0

var display_color: Color = Color(
	0.15,
	0.75,
	0.95,
	1.0
)

var name_label: Label


func setup(
	id: int,
	name: String,
	start_position: Vector2
) -> void:

	peer_id = id
	player_name = name

	current_position = start_position
	target_position = start_position

	position = start_position

	current_length = 10
	target_length = 10

	_create_name_label()
	_rebuild_body()

	queue_redraw()


func _ready() -> void:

	set_process(true)

	queue_redraw()


func _process(delta: float) -> void:

	if not is_alive:
		return

	var interpolation := min(
		1.0,
		interpolation_speed * delta
	)

	global_position = global_position.lerp(
		target_position,
		interpolation
	)

	direction = direction.lerp(
		target_direction,
		min(1.0, 10.0 * delta)
	)

	if direction.length() > 0.01:
		direction = direction.normalized()

	_interpolate_body(delta)

	queue_redraw()


func _create_name_label() -> void:

	if is_instance_valid(name_label):
		name_label.queue_free()

	name_label = Label.new()

	name_label.name = "PlayerName"
	name_label.text = player_name

	name_label.position = Vector2(-100, -65)
	name_label.size = Vector2(200, 40)

	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	name_label.add_theme_font_size_override(
		"font_size",
		20
	)

	name_label.add_theme_color_override(
		"font_color",
		Color.WHITE
	)

	name_label.add_theme_color_override(
		"font_shadow_color",
		Color(0, 0, 0, 0.8)
	)

	name_label.add_theme_constant_override(
		"shadow_offset_x",
		2
	)

	name_label.add_theme_constant_override(
		"shadow_offset_y",
		2
	)

	add_child(name_label)


func update_state(
	new_position: Vector2,
	new_direction: Vector2,
	new_length: int,
	alive: bool,
	new_body: Array = []
) -> void:

	target_position = new_position

	if new_direction.length() > 0.01:
		target_direction = new_direction.normalized()

	target_length = max(
		5,
		new_length
	)

	if new_body.size() > 0:

		target_body.clear()

		for point in new_body:
			if point is Vector2:
				target_body.append(point)

	if alive != is_alive:

		if alive:
			respawn(new_position)
		else:
			die()

	is_alive = alive


func set_player_name(new_name: String) -> void:

	player_name = new_name

	if is_instance_valid(name_label):
		name_label.text = player_name


func set_length(new_length: int) -> void:

	target_length = max(
		5,
		new_length
	)


func set_target_position(new_position: Vector2) -> void:

	target_position = new_position


func _interpolate_body(delta: float) -> void:

	if target_body.is_empty():
		_rebuild_body()
		return

	while body.size() < target_body.size():

		body.append(
			target_body[body.size()]
		)

	while body.size() > target_body.size():
		body.pop_back()

	var amount := min(
		1.0,
		15.0 * delta
	)

	for i in range(body.size()):

		if i >= target_body.size():
			break

		body[i] = body[i].lerp(
			target_body[i],
			amount
		)

	if not body.is_empty():

		body[0] = global_position


func _rebuild_body() -> void:

	var required_count := max(
		5,
		target_length
	)

	while body.size() < required_count:

		if body.is_empty():

			body.append(
				global_position
			)

		else:

			var previous: Vector2 = body[
				body.size() - 1
			]

			body.append(
				previous -
				direction *
				segment_distance
			)

	while body.size() > required_count:
		body.pop_back()

	if body.is_empty():
		return

	body[0] = global_position

	for i in range(1, body.size()):

		var desired := (
			body[i - 1] -
			direction *
			segment_distance
		)

		body[i] = body[i].lerp(
			desired,
			0.35
		)


func _draw() -> void:

	if not is_alive:
		return

	if body.is_empty():
		return

	for i in range(
		body.size() - 1,
		-1,
		-1
	):

		var point: Vector2 = (
			body[i] -
			global_position
		)

		var progress := float(i) / max(
			1,
			body.size() - 1
		)

		var radius := lerp(
			19.0,
			12.0,
			progress
		)

		draw_circle(
			point,
			radius + 3.0,
			Color(0, 0, 0, 0.18)
		)

		draw_circle(
			point,
			radius,
			display_color
		)

		draw_circle(
			point +
			Vector2(
				-radius * 0.25,
				-radius * 0.25
			),
			radius * 0.25,
			Color(1, 1, 1, 0.20)
		)

	var head: Vector2 = (
		body[0] -
		global_position
	)

	var head_radius := 22.0

	draw_circle(
		head,
		head_radius + 4.0,
		Color(0, 0, 0, 0.20)
	)

	draw_circle(
		head,
		head_radius,
		display_color
	)

	var forward := direction.normalized()

	if forward.length() < 0.1:
		forward = Vector2.RIGHT

	var side := Vector2(
		-forward.y,
		forward.x
	)

	var eye_distance := 8.0

	var eye_left := (
		head +
		forward * 9.0 +
		side * eye_distance
	)

	var eye_right := (
		head +
		forward * 9.0 -
		side * eye_distance
	)

	draw_circle(
		eye_left,
		5.5,
		Color.WHITE
	)

	draw_circle(
		eye_right,
		5.5,
		Color.WHITE
	)

	draw_circle(
		eye_left +
		forward * 2.0,
		2.5,
		Color(0.02, 0.02, 0.02)
	)

	draw_circle(
		eye_right +
		forward * 2.0,
		2.5,
		Color(0.02, 0.02, 0.02)
	)


func die() -> void:

	is_alive = false
	visible = false


func respawn(
	new_position: Vector2
) -> void:

	is_alive = true
	visible = true

	global_position = new_position
	target_position = new_position

	body.clear()
	target_body.clear()

	_rebuild_body()

	queue_redraw()


func get_peer_id() -> int:
	return peer_id


func get_player_name() -> String:
	return player_name


func get_length() -> int:
	return target_length


func get_is_alive() -> bool:
	return is_alive
