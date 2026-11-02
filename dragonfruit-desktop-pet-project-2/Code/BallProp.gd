# A real desktop window with simple ball physics. Distances are desktop pixels.
extends Window

var ball_position = Vector2.ZERO
var velocity = Vector2.ZERO
var screen_rect = Rect2()
var dragging = false
var drag_offset = Vector2.ZERO
var samples: Array = []
var picture: TextureRect
# QUICK CHANGES: gravity, bounce energy retained, rolling friction, throw cap.
var gravity = 1000.0
var bounce = 0.65
var friction = 180.0
var max_throw_speed = 2000.0

func _init():
	visible = false

func _ready():
	title = "Pet ball"
	size = Vector2i(64, 64)
	borderless = true
	unresizable = true
	always_on_top = true
	transparent = true
	transparent_bg = true
	picture = TextureRect.new()
	picture.texture = preload("res://Sprites/Football.svg")
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window_input.connect(_on_input)
	close_requested.connect(queue_free)

func place(at, bounds):
	screen_rect = bounds
	ball_position = at.clamp(bounds.position, bounds.end - Vector2(size))
	position = Vector2i(ball_position.round())
	show()

func _on_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			velocity = Vector2.ZERO
			drag_offset = Vector2(DisplayServer.mouse_get_position()) - ball_position
			samples.clear()
			_sample(Vector2(DisplayServer.mouse_get_position()), Time.get_ticks_usec() / 1000000.0)
		elif dragging:
			_release()

func _sample(at, seconds):
	samples.append({"at": at, "time": seconds})
	while samples.size() > 1 and samples[0].time < seconds - 0.12:
		samples.pop_front()

func throw_velocity():
	if samples.size() < 2:
		return Vector2.ZERO
	var seconds = samples.back().time - samples.front().time
	if seconds < 0.001:
		return Vector2.ZERO
	return ((samples.back().at - samples.front().at) / seconds).limit_length(max_throw_speed)

func _release():
	_sample(Vector2(DisplayServer.mouse_get_position()), Time.get_ticks_usec() / 1000000.0)
	velocity = throw_velocity()
	dragging = false
	# A ball dropped on another monitor belongs to that monitor.
	var monitor = DisplayServer.window_get_current_screen(get_window_id())
	screen_rect = Rect2(Vector2(DisplayServer.screen_get_position(monitor)), Vector2(DisplayServer.screen_get_size(monitor)))

func _physics_process(delta):
	if dragging:
		var mouse = Vector2(DisplayServer.mouse_get_position())
		_sample(mouse, Time.get_ticks_usec() / 1000000.0)
		ball_position = mouse - drag_offset
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_release()
	else:
		advance_motion(delta)
	position = Vector2i(ball_position.round())

func advance_motion(delta):
	# Small steps keep fast throws from tunneling through the desktop edges.
	var remaining = minf(delta, 0.25)
	var low = screen_rect.position
	var high = (screen_rect.end - Vector2(size)).max(low)
	while remaining > 0.0:
		var step = minf(remaining, 1.0 / 120.0)
		remaining -= step
		velocity.y += gravity * step
		ball_position += velocity * step
		if ball_position.x < low.x or ball_position.x > high.x:
			velocity.x = absf(velocity.x) * bounce if ball_position.x < low.x else -absf(velocity.x) * bounce
		if ball_position.y < low.y:
			velocity.y = absf(velocity.y) * bounce
		if ball_position.y >= high.y:
			velocity.y = -absf(velocity.y) * bounce if absf(velocity.y) > 65.0 else 0.0
			velocity.x = move_toward(velocity.x, 0.0, friction * step)
		ball_position = ball_position.clamp(low, high)
