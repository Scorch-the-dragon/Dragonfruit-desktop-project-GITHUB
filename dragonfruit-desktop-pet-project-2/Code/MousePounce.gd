# Catch the cursor, carry it down under gravity, then walk before letting go.
# Moving away dodges the jump; Escape or a mouse press releases early.
extends Node

var pet
# QUICK CHANGES: seconds, pixels, and pixels per second.
var jump_seconds = 0.65
var jump_height = 140.0
var catch_radius = 60.0
var carry_walk_distance = 180.0
var carry_walk_speed = 100.0
var phase = ""
var elapsed = 0.0
var origin = Vector2()
var target = Vector2()
var limits = Vector2()
var sprite_offset = Vector2()
var velocity = Vector2()
var saved_rotation = 0.0
var saved_flip = false
var walk_target_x = 0.0
var cursor_offset = Vector2()
var cancel_requested = false
var last_focused_window = DisplayServer.MAIN_WINDOW_ID
# Replace these in tests so tests never move the real desktop cursor.
var read_pointer: Callable = _read_pointer
var move_pointer: Callable = _move_pointer


func setup(pet_node):
	pet = pet_node
	# warp_mouse uses the last focused Godot window, even after it loses focus.
	# Remember that window without taking focus away from the user's other apps.
	_watch_window(get_tree().root)
	for node in get_tree().root.find_children("*", "Window", true, false):
		_watch_window(node)
	get_tree().node_added.connect(_watch_window)


func _watch_window(node):
	if node is Window:
		node.focus_entered.connect(func(): last_focused_window = node.get_window_id())
		if node.has_focus():
			last_focused_window = node.get_window_id()


func _read_pointer():
	return Vector2(DisplayServer.mouse_get_position())


func _move_pointer(position):
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var window_id = DisplayServer.window_get_active_popup()
	if window_id == DisplayServer.INVALID_WINDOW_ID:
		window_id = last_focused_window
	if not DisplayServer.get_window_list().has(window_id):
		window_id = DisplayServer.MAIN_WINDOW_ID
	# Convert desktop coordinates into the client coordinates warp_mouse expects.
	# Passing desktop coordinates directly adds the window offset a second time.
	var local_position = position - Vector2(DisplayServer.window_get_position(window_id))
	DisplayServer.warp_mouse(Vector2i(local_position.round()))


func start():
	limits = (pet.screen_size - pet.window_size).max(Vector2.ZERO)
	sprite_offset = pet.sprite.position * pet.window_size / pet.get_viewport_rect().size.max(Vector2.ONE)
	origin = pet.win_pos
	var mouse = read_pointer.call() - pet.screen_origin
	target = _clamp_position(mouse - sprite_offset)
	saved_rotation = pet.sprite.rotation
	saved_flip = pet.sprite.flip_h
	pet.sprite.flip_h = false
	pet.sprite.play("splat")
	pet.horizontal_fall_speed = 0.0
	pet.fall_speed = 0.0
	elapsed = 0.0
	velocity = Vector2.ZERO
	cancel_requested = false
	phase = "jump"


func advance(delta):
	if cancel_requested or Input.is_key_pressed(KEY_ESCAPE) or Input.get_mouse_button_mask() != 0:
		_finish()
		return true
	elapsed += delta
	var before = pet.win_pos
	var finished = false
	if phase == "jump":
		var t = clampf(elapsed / jump_seconds, 0.0, 1.0)
		pet.win_pos = _clamp_position(origin.lerp(target, t) - Vector2(0.0, sin(t * PI) * jump_height))
		velocity = (pet.win_pos - before) / maxf(delta, 0.0001)
		_orient_sprite()
		var mouse = read_pointer.call()
		var center = pet.screen_origin + pet.win_pos + sprite_offset
		if t >= 0.3 and Rect2(pet.screen_origin, pet.screen_size).has_point(mouse) and center.distance_to(mouse) <= catch_radius:
			cursor_offset = mouse - pet.screen_origin - pet.win_pos
			# Start descending on a catch, even if the leap was still rising.
			velocity = Vector2(0.0, maxf(0.0, velocity.y))
			phase = "carry_fall"
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif t >= 1.0:
			finished = true
	elif phase == "carry_fall":
		velocity.y = minf(velocity.y + pet.gravity * delta, pet.max_fall_speed)
		pet.win_pos.y = minf(pet.win_pos.y + velocity.y * delta, limits.y)
		_orient_sprite()
		if pet.win_pos.y >= limits.y:
			_start_walk()
	elif phase == "carry_walk":
		pet.win_pos.x = move_toward(pet.win_pos.x, walk_target_x, maxf(1.0, carry_walk_speed) * delta)
		finished = is_equal_approx(pet.win_pos.x, walk_target_x)
	# Move the window FIRST so the pointer conversion uses its new position.
	pet._apply_window_position()
	if phase == "carry_fall" or phase == "carry_walk":
		_carry_pointer()
	if finished:
		_finish()
		return true
	return false


func _start_walk():
	phase = "carry_walk"
	velocity = Vector2.ZERO
	pet.surface = pet.Surface.FLOOR
	pet.sprite.rotation = 0.0
	pet.sprite.flip_h = saved_flip
	var heading = -1.0 if randf() < 0.5 else 1.0
	var distance = maxf(0.0, carry_walk_distance)
	# Near an edge choose the direction with more room, instead of walking off it.
	var room = pet.win_pos.x if heading < 0.0 else limits.x - pet.win_pos.x
	var opposite_room = limits.x - room
	if room < distance and opposite_room > room:
		heading *= -1.0
	walk_target_x = clampf(pet.win_pos.x + heading * distance, 0.0, limits.x)
	pet.direction = Vector2(heading, 0.0)
	pet._update_animation()


func _carry_pointer():
	# Keep the complete arrow away from screen edges, rather than just its tip.
	var mouse = pet.win_pos + cursor_offset
	mouse = mouse.clamp(Vector2.ZERO, (pet.screen_size - Vector2(32, 32)).max(Vector2.ZERO))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	move_pointer.call(pet.screen_origin + mouse)


func _clamp_position(position):
	return Vector2(clampf(position.x, 0.0, limits.x), clampf(position.y, 0.0, limits.y))


func _orient_sprite():
	# Splat artwork faces right, so its rotation follows the current flight angle.
	if velocity.length_squared() > 1.0:
		pet.sprite.rotation = velocity.angle()


func _finish():
	phase = ""
	pet.sprite.rotation = saved_rotation
	pet.sprite.flip_h = saved_flip
	pet.surface = pet.Surface.FLOOR if pet.win_pos.y >= limits.y else pet.Surface.FALLING
	pet.horizontal_fall_speed = 0.0
	pet.fall_speed = 0.0 if pet.surface == pet.Surface.FLOOR else clampf(velocity.y, 0.0, pet.max_fall_speed)
	pet.mouse_over_pet = false
	pet.last_pet_mouse_position = read_pointer.call()
	pet._update_animation()
