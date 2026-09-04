extends Node2D

var loot_id: int = 0
var loot_position := Vector2.ZERO

var animation_time := 0.0


func setup(
	id: int,
	position_value: Vector2
) -> void:

	loot_id = id
	loot_position = position_value

	position = position_value

	queue_redraw()


func _process(delta: float) -> void:

	animation_time += delta

	queue_redraw()


func _draw() -> void:

	var bounce := sin(
		animation_time * 5.0
	) * 3.0

	var center := Vector2(
		0,
		-bounce
	)

	# Glow
	draw_circle(
		center,
		16.0,
		Color(
			1.0,
			0.55,
			0.05,
			0.15
		)
	)

	# Loot
	draw_circle(
		center,
		10.0,
		Color(
			1.0,
			0.55,
			0.05
		)
	)

	# Inner shine
	draw_circle(
		center + Vector2(
			-3,
			-3
		),
		3.0,
		Color(
			1,
			1,
			1,
			0.55
		)
	)
