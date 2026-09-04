extends Node2D

var food_id: int = 0
var food_position := Vector2.ZERO

var pulse := 0.0


func setup(
	id: int,
	position_value: Vector2
) -> void:

	food_id = id
	food_position = position_value

	position = position_value

	queue_redraw()


func _process(delta: float) -> void:

	pulse += delta

	queue_redraw()


func _draw() -> void:

	var scale_value := (
		1.0 +
		sin(pulse * 4.0) * 0.08
	)

	var radius := 11.0 * scale_value

	draw_circle(
		Vector2.ZERO,
		radius + 5.0,
		Color(
			1.0,
			0.75,
			0.10,
			0.15
		)
	)

	draw_circle(
		Vector2.ZERO,
		radius,
		Color(
			1.0,
			0.75,
			0.10
		)
	)

	draw_circle(
		Vector2(
			-3,
			-3
		),
		3.0,
		Color(
			1,
			1,
			1,
			0.45
		)
	)
