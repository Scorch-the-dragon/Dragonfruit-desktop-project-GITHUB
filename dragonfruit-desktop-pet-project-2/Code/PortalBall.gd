extends "res://Code/BallProp.gd"
var portal_color = "blue"
var portals
var armed = false

func _ready():
	super._ready()
	title = portal_color.capitalize() + " portal ball"
	picture.texture = preload("res://Sprites/portal_ball.svg")
	picture.self_modulate = Color(0.15, 0.65, 1.0) if portal_color == "blue" else Color(1.0, 0.45, 0.08)

func _release():
	super._release()
	armed = true

func advance_motion(delta):
	if not armed:
		super.advance_motion(delta)
		return
	var remaining = minf(delta, 0.25)
	var high = (screen_rect.end - Vector2(size)).max(screen_rect.position)
	while remaining > 0:
		var step = minf(remaining, 1.0 / 120.0)
		remaining -= step
		velocity.y += gravity * step
		ball_position += velocity * step
		var edge = ""
		if ball_position.x <= screen_rect.position.x and velocity.x < 0: edge = "left"
		elif ball_position.x >= high.x and velocity.x > 0: edge = "right"
		elif ball_position.y <= screen_rect.position.y and velocity.y < 0: edge = "top"
		elif ball_position.y >= high.y and velocity.y > 0: edge = "bottom"
		if not edge.is_empty():
			portals.place_portal(portal_color, edge, ball_position + Vector2(size) * 0.5, screen_rect)
			hide()
			queue_free()
			return
