extends Node2D

# =========================================================
# SNAKE ARAB ONLINE
# 6.6.11 - Network Movement & Interpolation
# =========================================================

# =========================================================
# PLAYER DATA
# =========================================================

var peer_id: int = 0
var player_name: String = "لاعب"

# =========================================================
# MOVEMENT
# =========================================================

var direction: Vector2 = Vector2.RIGHT
var target_direction: Vector2 = Vector2.RIGHT

var current_position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO

# السرعة البصرية للثعبان البعيد
var visual_speed: float = 260.0

# سرعة تنعيم الموقع
var interpolation_speed: float = 14.0

# سرعة تنعيم الاتجاه
var rotation_interpolation_speed: float = 12.0

# تصحيح الموقع عند وجود فرق كبير
var correction_speed: float = 20.0

# المسافة التي عندها نعتبر أن الموقع يحتاج تصحيحًا سريعًا
var snap_distance: float = 500.0

# =========================================================
# SNAKE LENGTH
# =========================================================

var current_length: int = 10
var target_length: int = 10

var minimum_length: int = 5

# =========================================================
# BODY
# =========================================================

var body: Array[Vector2] = []

var segment_distance: float = 24.0

# =========================================================
# STATE
# =========================================================

var is_alive: bool = true

var target_alive: bool = true

var movement_enabled: bool = true

# =========================================================
# NETWORK TIMING
# =========================================================

var last_network_update_time: float = 0.0
var network_update_interval: float = 0.05

var time_since_network_update: float = 0.0

# =========================================================
# VISUAL
# =========================================================

var display_color: Color = Color(
	0.15,
	0.75,
	0.95,
	1.0
)

var head_radius: float = 17.0
var body_radius: float = 14.0

var name_label: Label

# =========================================================
# SMOOTHING
# =========================================================

var velocity_estimate: Vector2 = Vector2.ZERO
var previous_target_position: Vector2 = Vector2.ZERO

var has_received_first_update: bool = false

# =========================================================
# READY
# =========================================================

func _ready() -> void:
	set_process(true)
	set_physics_process(false)

	queue_redraw()


# =========================================================
# SETUP
# =========================================================

func setup(
	id: int,
	name: String,
	start_position: Vector2
) -> void:

	peer_id = id

	player_name = name

	current_position = start_position
	target_position = start_position

	previous_target_position = start_position

	global_position = start_position

	current_length = 10
	target_length = 10

	direction = Vector2.RIGHT
	target_direction = Vector2.RIGHT

	is_alive = true
	target_alive = true

	has_received_first_update = false

	_create_name_label()

	_rebuild_body()

	queue_redraw()


# =========================================================
# PROCESS
# =========================================================

func _process(delta: float) -> void:

	if not is_alive:
		return

	if not movement_enabled:
		return

	time_since_network_update += delta

	_update_network_movement(delta)

	_update_direction(delta)

	_update_length(delta)

	_rebuild_body()

	queue_redraw()


# =========================================================
# NETWORK MOVEMENT
# =========================================================

func _update_network_movement(delta: float) -> void:

	var distance := global_position.distance_to(
		target_position
	)

	# -----------------------------------------------------
	# إذا كان الفرق كبيرًا جدًا
	# -----------------------------------------------------

	if distance >= snap_distance:

		global_position = target_position

		current_position = target_position

		velocity_estimate = Vector2.ZERO

		return

	# -----------------------------------------------------
	# تقدير السرعة من آخر تحديث للشبكة
	# -----------------------------------------------------

	if has_received_first_update:

		var target_delta := (
			target_position
			- previous_target_position
		)

		if delta > 0.0001:

			var estimated_velocity := (
				target_delta / delta
			)

			velocity_estimate = velocity_estimate.lerp(
				estimated_velocity,
				min(
					1.0,
					10.0 * delta
				)
			)

	# -----------------------------------------------------
	# Interpolation
	# -----------------------------------------------------

	var interpolation_factor := min(
		1.0,
		interpolation_speed * delta
	)

	current_position = current_position.lerp(
		target_position,
		interpolation_factor
	)

	global_position = current_position

	# -----------------------------------------------------
	# تصحيح إضافي للموقع
	# -----------------------------------------------------

	if distance > 100.0:

		var correction_factor := min(
			1.0,
			correction_speed * delta
		)

		global_position = global_position.lerp(
			target_position,
			correction_factor
		)

		current_position = global_position


# =========================================================
# DIRECTION SMOOTHING
# =========================================================

func _update_direction(delta: float) -> void:

	if target_direction.length() <= 0.01:
		return

	target_direction = target_direction.normalized()

	var factor := min(
		1.0,
		rotation_interpolation_speed * delta
	)

	direction = direction.lerp(
		target_direction,
		factor
	)

	if direction.length() > 0.01:
		direction = direction.normalized()


# =========================================================
# LENGTH SMOOTHING
# =========================================================

func _update_length(delta: float) -> void:

	if current_length == target_length:
		return

	var difference := target_length - current_length

	var change_speed := 12.0

	var amount := change_speed * delta

	if abs(difference) <= amount:

		current_length = target_length

	else:

		if difference > 0:
			current_length += int(
				ceil(amount)
			)
		else:
			current_length -= int(
				ceil(amount)
			)

	current_length = clamp(
		current_length,
		minimum_length,
		10000
	)


# =========================================================
# UPDATE STATE
# =========================================================

func update_state(
	new_position: Vector2,
	new_direction: Vector2,
	new_length: int,
	alive: bool
) -> void:

	# -----------------------------------------------------
	# أول تحديث
	# -----------------------------------------------------

	if not has_received_first_update:

		current_position = new_position
		target_position = new_position

		previous_target_position = new_position

		global_position = new_position

		has_received_first_update = true

	else:

		previous_target_position = target_position

		target_position = new_position

	# -----------------------------------------------------
	# Direction
	# -----------------------------------------------------

	if new_direction.length() > 0.01:

		target_direction = new_direction.normalized()

	# -----------------------------------------------------
	# Length
	# -----------------------------------------------------

	target_length = max(
		minimum_length,
		new_length
	)

	# -----------------------------------------------------
	# Alive
	# -----------------------------------------------------

	target_alive = alive

	if alive != is_alive:

		if alive:
			respawn(new_position)
		else:
			die()

	# -----------------------------------------------------
	# Timing
	# -----------------------------------------------------

	last_network_update_time = Time.get_ticks_msec() / 1000.0

	time_since_network_update = 0.0


# =========================================================
# NAME LABEL
# =========================================================

func _create_name_label() -> void:

	if name_label != null:
		if is_instance_valid(name_label):
			name_label.queue_free()

	name_label = Label.new()

	name_label.text = player_name

	name_label.position = Vector2(
		-80,
		-70
	)

	name_label.size = Vector2(
		160,
		35
	)

	name_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	name_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	name_label.add_theme_font_size_override(
		"font_size",
		20
	)

	name_label.add_theme_color_override(
		"font_color",
		Color(
			1.0,
			1.0,
			1.0,
			1.0
		)
	)

	name_label.add_theme_color_override(
		"font_shadow_color",
		Color(
			0.0,
			0.0,
			0.0,
			0.8
		)
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


# =========================================================
# CHANGE NAME
# =========================================================

func set_player_name(
	new_name: String
) -> void:

	player_name = new_name

	if name_label != null:
		name_label.text = player_name


# =========================================================
# LENGTH
# =========================================================

func set_length(
	new_length: int
) -> void:

	target_length = max(
		minimum_length,
		new_length
	)


func get_length() -> int:
	return current_length


# =========================================================
# BODY REBUILD
# =========================================================

func _rebuild_body() -> void:

	body.clear()

	var safe_length := max(
		minimum_length,
		current_length
	)

	var segment_count := min(
		safe_length,
		300
	)

	var body_direction := direction

	if body_direction.length() <= 0.01:
		body_direction = Vector2.RIGHT

	body_direction = body_direction.normalized()

	for i in range(segment_count):

		var segment_position := (
			global_position
			- body_direction
			* (
				float(i)
				* segment_distance
			)
		)

		body.append(
			segment_position
		)


# =========================================================
# DRAW
# =========================================================

func _draw() -> void:

	if not is_alive:
		return

	if body.is_empty():
		return

	# -----------------------------------------------------
	# BODY
	# -----------------------------------------------------

	for i in range(body.size() - 1, 0, -1):

		var world_position: Vector2 = body[i]

		var local_position := (
			world_position
			- global_position
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

		var body_color := display_color.lightened(
			0.04 * (1.0 - progress)
		)

		draw_circle(
			local_position,
			radius,
			body_color
		)

	# -----------------------------------------------------
	# HEAD
	# -----------------------------------------------------

	draw_circle(
		Vector2.ZERO,
		head_radius,
		display_color
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
		forward * eye_forward_distance
		+ side * eye_side_distance
	)

	var right_eye_position := (
		forward * eye_forward_distance
		- side * eye_side_distance
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


# =========================================================
# DEATH
# =========================================================

func die() -> void:

	is_alive = false
	target_alive = false

	visible = false

	body.clear()

	queue_redraw()


# =========================================================
# RESPAWN
# =========================================================

func respawn(
	new_position: Vector2
) -> void:

	is_alive = true
	target_alive = true

	visible = true

	global_position = new_position

	current_position = new_position
	target_position = new_position

	previous_target_position = new_position

	direction = Vector2.RIGHT
	target_direction = Vector2.RIGHT

	current_length = minimum_length + 5
	target_length = minimum_length + 5

	velocity_estimate = Vector2.ZERO

	has_received_first_update = false

	body.clear()

	_rebuild_body()

	queue_redraw()


# =========================================================
# MOVEMENT CONTROL
# =========================================================

func stop_movement() -> void:
	movement_enabled = false


func resume_movement() -> void:
	movement_enabled = true


# =========================================================
# GETTERS
# =========================================================

func get_peer_id() -> int:
	return peer_id


func get_player_name() -> String:
	return player_name


func get_is_alive() -> bool:
	return is_alive


func get_target_position() -> Vector2:
	return target_position


func get_current_position() -> Vector2:
	return current_position


func get_direction() -> Vector2:
	return direction


# =========================================================
# NETWORK QUALITY HELPERS
# =========================================================

func set_interpolation_speed(
	value: float
) -> void:

	interpolation_speed = clamp(
		value,
		4.0,
		30.0
	)


func set_correction_speed(
	value: float
) -> void:

	correction_speed = clamp(
		value,
		5.0,
		50.0
	)


func get_distance_from_target() -> float:
	return global_position.distance_to(
		target_position
	)


# =========================================================
# RESET
# =========================================================

func reset() -> void:

	current_position = global_position
	target_position = global_position

	previous_target_position = global_position

	direction = Vector2.RIGHT
	target_direction = Vector2.RIGHT

	current_length = 10
	target_length = 10

	is_alive = true
	target_alive = true

	movement_enabled = true

	velocity_estimate = Vector2.ZERO

	has_received_first_update = false

	body.clear()

	_rebuild_body()

	queue_redraw()
