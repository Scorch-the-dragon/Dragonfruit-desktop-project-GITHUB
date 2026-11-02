# Procedural glow: no extra portal artwork needed.
extends Control
var color = Color.DEEP_SKY_BLUE
func _draw():
	draw_set_transform(size * 0.5, 0.0, size / Vector2(2.0, 2.0))
	for i in range(8, 0, -1):
		var tint = color
		tint.a = 0.035
		draw_arc(Vector2.ZERO, 0.52 + i * 0.045, 0, TAU, 64, tint, 0.12, true)
	draw_arc(Vector2.ZERO, 0.6, 0, TAU, 64, color, 0.07, true)
	draw_arc(Vector2.ZERO, 0.6, 0, TAU, 64, Color(1, 1, 1, 0.8), 0.02, true)
