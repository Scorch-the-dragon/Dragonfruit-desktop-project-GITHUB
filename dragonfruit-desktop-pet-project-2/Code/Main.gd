# DESKTOP PET CONTROLLER
# Moves the whole window. Gravity pulls the pet down when it is not holding
# an edge. On landing, it walks around the floor, walls, and ceiling.
extends Node2D

# QUICK CHANGES (pixels and seconds):
# Higher speed means faster walking AND climbing.
var speed = 100.0
# Average care level: 1 = full speed, 0 = motionless until cared for.
var vitality = 1.0
var stat_material: ShaderMaterial
# Gravity adds this much downward speed each second. Keep it positive.
var gravity = 900.0
# Limits how fast the pet can fall. Keep it positive.
var max_fall_speed = 1000.0
# THROW SETTINGS: sample the last 0.12 seconds of mouse movement on release.
# Increase throw_strength for stronger throws; max_throw_speed limits fast flicks.
var throw_strength = 1.0
var max_throw_speed = 1800.0
var throw_sample_seconds = 0.12
var throw_bounce = 0.35 # Side-wall bounce: 0 stops sideways motion, 1 keeps it all.
var horizontal_fall_speed = 0.0
# Only a mouse throw enables screen-impact sounds; ordinary falls stay quiet.
var throw_in_progress = false
# Pause in the splat pose after a thrown pet hits the desktop floor.
var landing_splat_seconds = 0.8
var landing_splat_remaining = 0.0
var landing_splat_faces_left = false
var impact_audio: AudioStreamPlayer
var impact_sounds: Array[AudioStream] = []
var impact_volume_db = -8.0 # Also controlled by the Options volume slider.
# The fall artwork faces right by default. Remember facing for straight drops.
var falling_faces_left = false
var drag_samples: Array = []
# Chance of resting when landing or reaching a floor corner: 0 = never, 1 = always.
var idle_chance = 0.3
var idle_min_seconds = 1.0
var idle_max_seconds = 3.0

# These are filled from the actual screen and window dimensions at startup.
var screen_size = Vector2()
var window_size = Vector2()
var screen_origin = Vector2()
# Keep fractional pixels between ticks so slow movement still accumulates.
# This position is relative to the current screen's top-left corner.
var win_pos = Vector2()
# Positive x goes right; positive y goes DOWN.
var direction = Vector2.RIGHT
var fall_speed = 0.0

# An enum gives readable names to the five movement states.
# Gravity runs only in FALLING; the other states hold onto a screen edge.
enum Surface { FALLING, FLOOR, LEFT_WALL, RIGHT_WALL, CEILING, WINDOW_TOP }
var window_platforms
var surface = Surface.FALLING
var is_dragging = false
# Right-click opens care; a short left-click squeaks, while moving 6 pixels drags.
var drag_threshold = 6.0
var click_squish
var click_pending = false
var press_position = Vector2()
var care_menu
var care_item
var props
var portals
var events
var preferences = preload("res://Code/PetPreferences.gd").new()
# Seconds spent eating/drinking. Refill happens once, when this timer finishes.
var consume_seconds = 2.0
var consume_timer = 0.0
var consuming_kind = ""
var before_consuming_rotation = 0.0
var before_consuming_flip_h = false
# Eating/drinking volume in decibels: 0 is full volume, -12 is quieter.
var consumption_volume_db = -8.0
var consumption_audio: AudioStreamPlayer
var eating_sounds: Array[AudioStream] = []
var drinking_sound: AudioStream
# PETTING SETTINGS: rub the mouse over Area2D without holding a button.
# A little accumulated movement avoids treating a single tiny twitch as a pet.
var petting_start_distance = 40.0
var petting_grace_seconds = 0.35
var happiness_per_pixel = 0.12
var happiness_per_second = 15.0
var is_petting = false
var mouse_over_pet = false
var last_pet_mouse_position = Vector2()
var petting_distance = 0.0
var petting_samples = 0
var petting_timer = 0.0
# Save the sprite's normal transform so petting does not rotate the existing
# walking/climbing artwork (those animations already have their own orientation).
var before_petting_rotation = 0.0
var before_petting_flip_h = false
# Offset from the window's top-left corner to the point where it was grabbed.
var drag_offset = Vector2()
var idle_timer = 0.0
var is_idling = false

# @onready waits until the scene's children are ready.
# Update these paths if you rename the nodes. Animation names in sprite.play()
# must match the animations in AnimatedSprite2D's SpriteFrames.
@onready var sprite = $AnimatedSprite2D
# Resize Area2D's collision shape in the editor to change the clickable area.
@onready var area = $Area2D


func _ready():
	_refresh_screen_bounds()
	win_pos = Vector2(DisplayServer.window_get_position()) - screen_origin
	area.input_event.connect(_on_area_input)
	area.mouse_entered.connect(func(): mouse_over_pet = true)
	area.mouse_exited.connect(func(): mouse_over_pet = false)
	get_window().mouse_exited.connect(func(): mouse_over_pet = false)
	last_pet_mouse_position = Vector2(DisplayServer.mouse_get_position())
	_pick_new_direction()
	_update_animation()
	# A separate native window lets the menu extend beyond the tiny pet window.
	get_tree().root.gui_embed_subwindows = false
	care_menu = preload("res://Code/PetCareMenu.gd").new()
	click_squish = preload("res://Code/ClickSquish.gd").new()
	click_squish.pet = self
	add_child(click_squish)
	add_child(care_menu)
	care_item = preload("res://Code/CareItem.gd").new()
	add_child(care_item)
	care_menu.item_requested.connect(_offer_item)
	care_item.dropped.connect(_on_item_dropped)
	props = preload("res://Code/PetProps.gd").new()
	portals = preload("res://Code/PetPortals.gd").new()
	portals.pet = self
	add_child(portals)
	props.pet = self
	add_child(props)
	care_menu.prop_requested.connect(func(kind):
		var prop = props.spawn_prop(kind)
		care_menu._show_feedback("Prop spawned! Drag it to play." if prop != null else "Prop limit reached. Remove props to make room."))
	care_menu.remove_props_requested.connect(props.remove_props)
	# AudioStreamPlayer keeps the sound volume independent of screen position.
	consumption_audio = AudioStreamPlayer.new()
	consumption_audio.name = "ConsumptionAudio"
	add_child(consumption_audio)
	for sound_path in ["res://Audio/eat1.ogg", "res://Audio/eat2.ogg", "res://Audio/eat3.ogg"]:
		eating_sounds.append(load(sound_path))
	drinking_sound = load("res://Audio/drink.ogg")
	consumption_audio.finished.connect(_play_consumption_sound)
	impact_audio = AudioStreamPlayer.new()
	impact_audio.name = "ThrowImpactAudio"
	add_child(impact_audio)
	for index in range(1, 7):
		impact_sounds.append(load("res://Audio/body_medium_impact_hard%d.wav" % index))
	events = preload("res://Code/PetEvents.gd").new()
	window_platforms = preload("res://Code/WindowPlatforms.gd").new()
	add_child(window_platforms)
	window_platforms.setup(self)
	add_child(events)
	events.setup(self)
	care_menu.set_events(events.catalog)
	care_menu.event_requested.connect(_on_event_requested)
	events.event_started.connect(func(label): care_menu._show_feedback(label + "!"))
	events.event_finished.connect(func(_label): care_menu._show_feedback("The boi is back!"))
	preferences.load_preferences()
	_apply_preferences()
	care_menu.configure_options(preferences, events.catalog)
	care_menu.option_changed.connect(_on_option_changed)
	stat_material = ShaderMaterial.new()
	stat_material.shader = preload("res://Code/StatColors.gdshader")
	sprite.material = stat_material
	_update_vitality()


func _update_vitality():
	if care_menu == null:
		return
	var levels = Vector3(care_menu.hunger, care_menu.happiness, care_menu.thirst) / 100.0
	levels = levels.clamp(Vector3.ZERO, Vector3.ONE) if care_menu.care_enabled else Vector3.ONE
	vitality = (levels.x + levels.y + levels.z) / 3.0
	sprite.speed_scale = vitality
	if stat_material != null:
		stat_material.set_shader_parameter("care_color", levels)


func _advance_exhausted(delta):
	# Keep care available even if depletion happened mid-event or in midair.
	# Existing events pause and resume after recovery; their state is preserved.
	if not consuming_kind.is_empty():
		_advance_consumption(delta)
		return
	_update_petting(delta, Vector2(DisplayServer.mouse_get_position()), mouse_over_pet, Input.get_mouse_button_mask() != 0)
	if click_pending or is_dragging:
		_track_pointer(Vector2(DisplayServer.mouse_get_position()))
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_finish_pointer()
		elif is_dragging:
			win_pos = Vector2(DisplayServer.mouse_get_position()) - drag_offset - screen_origin
			_apply_window_position()
	_update_vitality()


# Refresh after a drag so dropping onto another monitor uses that monitor.
# Full screen bounds are used, including the taskbar area.
func _refresh_screen_bounds():
	var screen = DisplayServer.window_get_current_screen()
	screen_origin = Vector2(DisplayServer.screen_get_position(screen))
	screen_size = Vector2(DisplayServer.screen_get_size(screen))
	window_size = Vector2(DisplayServer.window_get_size())


# Godot calls this every physics tick. delta is elapsed time in seconds.
func _physics_process(delta):
	_update_vitality()
	if vitality <= 0.0:
		_advance_exhausted(delta)
		return
	if window_platforms != null:
		window_platforms.refresh(delta)
		window_platforms.follow_support()
		if surface == Surface.WINDOW_TOP:
			_apply_window_position()
	if props != null and props.advance_squash(delta):
		return
	if click_squish != null and click_squish.advance(delta):
		return
	if landing_splat_remaining > 0.0:
		landing_splat_remaining = maxf(0.0, landing_splat_remaining - delta)
		_update_animation()
		return
	if events != null and events.advance(delta if events.active_id == "blow_up" else delta * vitality):
		return
	if not consuming_kind.is_empty():
		_advance_consumption(delta)
		return
	# The menu stays where it was opened; it does not stop the pet moving.
	# Use DESKTOP mouse movement, so the pet walking under a still cursor
	# cannot accidentally count as being petted.
	_update_petting(delta, Vector2(DisplayServer.mouse_get_position()),
		mouse_over_pet, Input.get_mouse_button_mask() != 0)
	if is_petting:
		return
	if click_pending:
		_track_pointer(Vector2(DisplayServer.mouse_get_position()))
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_finish_pointer()
		if not is_dragging:
			return
	if is_dragging:
		_track_pointer(Vector2(DisplayServer.mouse_get_position()))
		# Poll release too, so releasing outside Area2D does not leave the pet stuck.
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_finish_pointer()
		else:
			var mouse_pos = Vector2(DisplayServer.mouse_get_position())
			win_pos = mouse_pos - drag_offset - screen_origin
			_apply_window_position()
			sprite.play("pick_up")
			return

	if props != null and props.advance_play(delta * vitality):
		return
	# Only the floor allows rests; the pet cannot pause a fall in midair.
	if is_idling and surface == Surface.FLOOR:
		idle_timer -= delta
		if idle_timer > 0.0:
			return
		is_idling = false

	# The window's top-left cannot pass these limits without part going offscreen.
	# maxf keeps limits valid even if the window is larger than the screen.
	var limits = Vector2(
		maxf(0.0, screen_size.x - window_size.x),
		maxf(0.0, screen_size.y - window_size.y)
	)
	_advance_motion(delta * vitality, limits)
	_apply_window_position()
	if not is_idling:
		_update_animation()


# Keep motion calculations separate from applying the desktop window position.
func _advance_motion(delta, limits):
	if portals != null:
		portals.cooldown = maxf(0.0, portals.cooldown - delta)
	if landing_splat_remaining > 0.0:
		return
	var previous = win_pos
	var screen_impact = false
	var was_thrown = throw_in_progress
	match surface:
		Surface.FALLING:
			# Accelerate downwards until reaching the maximum fall speed.
			# A portal may redirect a fast sideways throw downward. Keep that
			# existing speed instead of abruptly cutting it to the gravity cap.
			fall_speed = minf(fall_speed + gravity * delta, maxf(max_fall_speed, fall_speed))
			win_pos.y += fall_speed * delta
			win_pos.x += horizontal_fall_speed * delta
			# Portal entry wins over wall bounces, floor splats, and impact audio.
			if portals != null and portals.try_travel(previous, true):
				return
			# Thrown pets bounce gently off side walls, then keep falling.
			if (win_pos.x <= 0.0 and horizontal_fall_speed < 0.0) or (win_pos.x >= limits.x and horizontal_fall_speed > 0.0):
				screen_impact = true
				horizontal_fall_speed *= -throw_bounce
			if win_pos.y <= 0.0 and fall_speed < 0.0:
				screen_impact = true
				fall_speed = 0.0 # Hitting the ceiling ends upward travel.
			if window_platforms != null and window_platforms.land(previous):
				throw_in_progress = false
				if was_thrown and events != null and events.try_landing_explosion():
					return
			elif win_pos.y >= limits.y and fall_speed >= 0.0:
				# Establish the landing before testing the explosion's busy guards.
				win_pos.y = limits.y
				surface = Surface.FLOOR
				throw_in_progress = false
				if was_thrown and events != null and events.try_landing_explosion():
					fall_speed = 0.0
					horizontal_fall_speed = 0.0
					return
				if was_thrown:
					landing_splat_remaining = landing_splat_seconds
					landing_splat_faces_left = horizontal_fall_speed < 0.0 if not is_zero_approx(horizontal_fall_speed) else falling_faces_left
				screen_impact = true
				throw_in_progress = false
				win_pos.y = limits.y
				fall_speed = 0.0
				horizontal_fall_speed = 0.0
				surface = Surface.FLOOR
				_pick_new_direction()
				if was_thrown:
					is_idling = false
					_update_animation()
				else:
					_maybe_idle()

		Surface.WINDOW_TOP:
			window_platforms.walk(delta)

		Surface.FLOOR:
			win_pos.y = limits.y
			win_pos.x += direction.x * speed * delta
			# At a floor corner, start climbing UP the wall instead of bouncing.
			if direction.x > 0.0 and win_pos.x >= limits.x:
				win_pos.x = limits.x
				surface = Surface.RIGHT_WALL
				direction = Vector2.UP
			elif direction.x < 0.0 and win_pos.x <= 0.0:
				win_pos.x = 0.0
				surface = Surface.LEFT_WALL
				direction = Vector2.UP

		Surface.LEFT_WALL, Surface.RIGHT_WALL:
			var on_left = surface == Surface.LEFT_WALL
			win_pos.x = 0.0 if on_left else limits.x
			win_pos.y += direction.y * speed * delta
			if direction.y < 0.0 and win_pos.y <= 0.0:
				# At the top, turn onto the ceiling and travel toward the other wall.
				win_pos.y = 0.0
				surface = Surface.CEILING
				direction = Vector2.RIGHT if on_left else Vector2.LEFT
			elif direction.y > 0.0 and win_pos.y >= limits.y:
				# At the bottom, turn onto the floor and travel away from this wall.
				win_pos.y = limits.y
				surface = Surface.FLOOR
				direction = Vector2.RIGHT if on_left else Vector2.LEFT
				_maybe_idle()

		Surface.CEILING:
			win_pos.y = 0.0
			win_pos.x += direction.x * speed * delta
			# At either end of the ceiling, climb DOWN the next wall.
			if direction.x > 0.0 and win_pos.x >= limits.x:
				win_pos.x = limits.x
				surface = Surface.RIGHT_WALL
				direction = Vector2.DOWN
			elif direction.x < 0.0 and win_pos.x <= 0.0:
				win_pos.x = 0.0
				surface = Surface.LEFT_WALL
				direction = Vector2.DOWN

	# Prevent overshooting an edge, including after a large physics step.
	if not was_thrown and surface != Surface.FALLING and portals != null and portals.try_travel(previous, false):
		return
	# One sound for a corner hit, even when two edges collide in the same tick.
	if screen_impact and was_thrown:
		_play_throw_impact()
	win_pos.x = clampf(win_pos.x, 0.0, limits.x)
	# Window perches may clip the top of the pet, provided its artwork remains
	# visible. Do not snap those perches back down to the monitor's top edge.
	var minimum_y = window_platforms.minimum_perch_y() if surface == Surface.WINDOW_TOP and window_platforms != null else 0.0
	win_pos.y = clampf(win_pos.y, minimum_y, limits.y)


func _apply_window_position():
	# Desktop window coordinates must be whole pixels, but win_pos keeps fractions.
	DisplayServer.window_set_position(Vector2i((win_pos + screen_origin).round()))


func _play_throw_impact():
	if impact_audio == null or impact_sounds.is_empty():
		return
	impact_audio.stream = impact_sounds.pick_random()
	impact_audio.volume_db = impact_volume_db
	impact_audio.play()


# Select by movement state, so the correct climbing animation plays at corners.
func _update_animation():
	if landing_splat_remaining > 0.0:
		sprite.flip_h = landing_splat_faces_left
		sprite.play("splat")
		return
	if surface == Surface.FALLING:
		if not is_zero_approx(horizontal_fall_speed):
			falling_faces_left = horizontal_fall_speed < 0.0
		sprite.flip_h = falling_faces_left
	else:
		if not is_zero_approx(direction.x):
			falling_faces_left = direction.x < 0.0
		# Walking and climbing already have separate directional artwork.
		sprite.flip_h = false
	match surface:
		Surface.FALLING:
			sprite.play("fall")
		Surface.FLOOR, Surface.WINDOW_TOP:
			sprite.play("walk_right" if direction.x > 0.0 else "walk_left")
		Surface.CEILING:
			sprite.play("crawl_top_right" if direction.x > 0.0 else "crawl_top_left")
		Surface.LEFT_WALL:
			sprite.play("crawl_left_down" if direction.y > 0.0 else "crawl_left_up")
		Surface.RIGHT_WALL:
			sprite.play("crawl_right_down" if direction.y > 0.0 else "crawl_right_up")


func _maybe_idle():
	# These rest animations are upright, so use them only on the floor.
	if surface == Surface.FLOOR and randf() < idle_chance:
		is_idling = true
		idle_timer = randf_range(idle_min_seconds, idle_max_seconds)
		# % 3 gives 0, 1, or 2, choosing one of the three rest animations.
		var r = randi() % 3
		if r == 0:
			sprite.play("idle")
		elif r == 1:
			sprite.play("crouch")
		else:
			sprite.play("splat")


func _pick_new_direction():
	# Choose left or right only. Random diagonal directions caused the floating.
	direction = Vector2.RIGHT if randf() < 0.5 else Vector2.LEFT


# Area2D starts a possible click or drag when you press on the pet.
# Underscores mark signal arguments that this function does not use.
func _on_area_input(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not is_dragging:
		if care_menu.visible:
			care_menu.hide()
		else:
			care_menu.open_near_pet()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and click_squish != null:
		click_squish.cancel()
	if _event_is_active():
		return
	if not consuming_kind.is_empty() or (care_item != null and care_item.dragging):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not click_pending and not is_dragging:
			_end_petting()
			click_pending = true
			press_position = Vector2(DisplayServer.mouse_get_position())
			drag_samples.clear()
			_record_drag_sample(press_position, Time.get_ticks_usec() / 1000000.0)
			drag_offset = press_position - Vector2(DisplayServer.window_get_position())


# Handle release anywhere in the window, even outside the pet's collision shape.
# The polling check in _physics_process provides an additional release check.
func _input(event):
	if (click_pending or is_dragging) and event is InputEventMouseMotion:
		_track_pointer(Vector2(DisplayServer.mouse_get_position()))
	if (click_pending or is_dragging) and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_track_pointer(Vector2(DisplayServer.mouse_get_position()))
			_finish_pointer()


func _track_pointer(mouse_pos):
	if click_pending or is_dragging:
		_record_drag_sample(mouse_pos, Time.get_ticks_usec() / 1000000.0)
	if click_pending and mouse_pos.distance_to(press_position) >= drag_threshold:
		click_pending = false
		is_dragging = true
		throw_in_progress = false
		is_idling = false
		idle_timer = 0.0
		fall_speed = 0.0
		horizontal_fall_speed = 0.0


# Include stationary samples too: holding still before release gives a plain drop.
func _record_drag_sample(mouse_pos, time_seconds):
	if not drag_samples.is_empty() and absf(drag_samples.back().time - time_seconds) < 0.000001:
		drag_samples.back().position = mouse_pos
	else:
		drag_samples.append({"position": mouse_pos, "time": time_seconds})
	while not drag_samples.is_empty() and drag_samples[0].time < time_seconds - throw_sample_seconds:
		drag_samples.pop_front()


func _get_throw_velocity():
	if drag_samples.size() < 2:
		return Vector2.ZERO
	var elapsed = drag_samples.back().time - drag_samples[0].time
	if elapsed < 0.001:
		return Vector2.ZERO
	var velocity = (drag_samples.back().position - drag_samples[0].position) / elapsed
	return (velocity * throw_strength).limit_length(max_throw_speed)


func _finish_pointer():
	if is_dragging:
		_release_pet()
	elif click_pending:
		click_pending = false
		if vitality > 0.0:
			click_squish.start()


# Called once per physics tick. Happiness is awarded for actual mouse movement,
# never just hovering, and capped per second so fast mice do not fill it instantly.
func _update_petting(delta, mouse_pos, over_pet, button_down):
	if _event_is_active():
		return
	var distance = mouse_pos.distance_to(last_pet_mouse_position)
	last_pet_mouse_position = mouse_pos
	# Petting requires an attached surface; it must never suspend a falling throw.
	if (surface == Surface.FALLING and vitality > 0.0) or not over_pet or button_down or click_pending or is_dragging or not consuming_kind.is_empty() or (care_item != null and care_item.dragging):
		_end_petting()
		return
	petting_timer = maxf(0.0, petting_timer - delta)
	if petting_timer <= 0.0:
		_end_petting()
	if distance < 1.0:
		return
	petting_timer = petting_grace_seconds
	petting_distance += distance
	petting_samples += 1
	# Require several movement samples as well as distance: one crossing alone
	# should not freeze the pet. Continue rubbing to keep the petting state active.
	if not is_petting and petting_distance >= petting_start_distance and petting_samples >= 3:
		is_petting = true
		is_idling = false
		idle_timer = 0.0
		before_petting_rotation = sprite.rotation
		before_petting_flip_h = sprite.flip_h
		_orient_petting_sprite()
		sprite.play("petting")
	if is_petting and care_menu != null:
		care_menu.receive_pets(minf(distance * happiness_per_pixel, happiness_per_second * delta))


# Petting frames are drawn upright, facing right. Rotate only the sprite,
# keeping its feet toward the attached edge and its face toward travel.
# Godot's positive rotation is clockwise: 90 degrees puts feet on the left wall.
func _orient_petting_sprite():
	match surface:
		Surface.LEFT_WALL:
			sprite.rotation_degrees = 90.0
			sprite.flip_h = direction.y < 0.0
		Surface.RIGHT_WALL:
			sprite.rotation_degrees = -90.0
			sprite.flip_h = direction.y > 0.0
		Surface.CEILING:
			sprite.rotation_degrees = 180.0
			sprite.flip_h = direction.x > 0.0
		_: # Floor and falling pets stay upright.
			sprite.rotation_degrees = 0.0
			sprite.flip_h = direction.x < 0.0


func _end_petting():
	var was_petting = is_petting
	is_petting = false
	petting_timer = 0.0
	petting_distance = 0.0
	petting_samples = 0
	# Resume the previous surface (or gravity if falling) when strokes stop.
	if was_petting:
		sprite.rotation = before_petting_rotation
		sprite.flip_h = before_petting_flip_h
		_update_animation()


func _release_pet():
	_end_petting()
	var mouse_pos = Vector2(DisplayServer.mouse_get_position())
	_record_drag_sample(mouse_pos, Time.get_ticks_usec() / 1000000.0)
	var velocity = _get_throw_velocity()
	# Include the final mouse movement, even when release occurs between ticks.
	win_pos = mouse_pos - drag_offset - screen_origin
	_apply_window_position()
	is_dragging = false
	click_pending = false
	is_idling = false
	idle_timer = 0.0
	_refresh_screen_bounds()
	win_pos = Vector2(DisplayServer.window_get_position()) - screen_origin
	# Preserve the flick's horizontal AND vertical momentum; gravity bends it down.
	surface = Surface.FALLING
	horizontal_fall_speed = velocity.x
	fall_speed = velocity.y
	throw_in_progress = velocity.length() > 1.0
	if throw_in_progress and events != null:
		events.record_throw()
	drag_samples.clear()
	last_pet_mouse_position = mouse_pos
	_update_animation()


func _offer_item(kind):
	if _event_is_active():
		care_menu._show_feedback("Wait for the shenanigans to finish.")
		return
	if not consuming_kind.is_empty():
		care_menu._show_feedback("Let the boi finish this first.")
		return
	# Spawn over the menu, where the user can grab it for a second drag gesture.
	care_item.offer(kind, care_menu.position + Vector2i(110, 65))
	care_menu._show_feedback("Drag the item onto your pet. Esc cancels.")


func _on_item_dropped(kind, desktop_position):
	if _item_hits_pet(desktop_position) and _begin_consuming(kind):
		care_item.cancel()
	else:
		care_menu._show_feedback("Drop onto your pet; grab the item to retry.")


func _item_hits_pet(desktop_position):
	# Ignore drops over the menu even if the pet happens to walk underneath it.
	if care_menu.visible and Rect2i(care_menu.position, care_menu.size).has_point(desktop_position):
		return false
	var actual_size = Vector2(DisplayServer.window_get_size())
	if actual_size.x <= 0 or actual_size.y <= 0:
		return false
	var local = Vector2(desktop_position - DisplayServer.window_get_position())
	if not Rect2(Vector2.ZERO, actual_size).has_point(local):
		return false
	# Convert desktop pixels into scene coordinates, accounting for window stretch.
	local *= get_viewport_rect().size / actual_size
	return _item_hits_scene_point(get_canvas_transform().affine_inverse() * local)


func _item_hits_scene_point(scene_position):
	var query = PhysicsPointQueryParameters2D.new()
	query.position = scene_position
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for hit in get_world_2d().direct_space_state.intersect_point(query):
		if hit.collider == area:
			return true
	return false


func _begin_consuming(kind):
	if _event_is_active():
		return false
	if kind not in ["food", "drink"] or not consuming_kind.is_empty() or is_dragging or click_pending:
		return false
	_end_petting()
	is_idling = false
	idle_timer = 0.0
	consuming_kind = kind
	consume_timer = consume_seconds
	before_consuming_rotation = sprite.rotation
	before_consuming_flip_h = sprite.flip_h
	# The upright sitting placeholders use the same wall/ceiling alignment as pets.
	_orient_petting_sprite()
	sprite.play("eating" if kind == "food" else "drinking")
	_play_consumption_sound()
	care_menu._show_feedback("Enjoying a snack..." if kind == "food" else "Having a drink...")
	return true


func _advance_consumption(delta):
	if consuming_kind.is_empty():
		return
	consume_timer = maxf(0.0, consume_timer - delta)
	if consume_timer > 0.0:
		return
	care_menu.finish_consuming(consuming_kind)
	consuming_kind = ""
	consumption_audio.stop()
	sprite.rotation = before_consuming_rotation
	sprite.flip_h = before_consuming_flip_h
	last_pet_mouse_position = Vector2(DisplayServer.mouse_get_position())
	_update_animation()


# Play another bite/sip after each short clip finishes, but only while consuming.
# This also starts the first sound when an item is accepted. Rejected drops and
# clicking Feed/Drink alone do not play a sound.
func _play_consumption_sound():
	if consuming_kind.is_empty():
		return
	consumption_audio.volume_db = consumption_volume_db
	if consuming_kind == "food":
		consumption_audio.stream = eating_sounds.pick_random()
	else:
		consumption_audio.stream = drinking_sound
	consumption_audio.play()


func _event_is_active():
	if vitality <= 0.0:
		return false # Care can revive a depleted pet even during a paused event.
	if landing_splat_remaining > 0.0:
		return true
	if click_squish != null and click_squish.active:
		return true
	if props != null and props.is_squashed():
		return true
	return events != null and not events.active_id.is_empty()


func _apply_preferences():
	care_menu.care_enabled = preferences.care_enabled
	if not preferences.care_enabled:
		care_menu.hunger = 100.0
		care_menu.thirst = 100.0
		care_menu.happiness = 100.0
	events.random_events_enabled = preferences.random_events_enabled
	events.disabled_events = preferences.disabled_events.duplicate()
	preferences.apply_volume()
	care_menu._refresh_stats()
	_update_vitality()


func _on_option_changed(key, value):
	match key:
		"care_enabled": preferences.care_enabled = value
		"random_events_enabled": preferences.random_events_enabled = value
		"volume_percent": preferences.volume_percent = clampf(value, 0.0, 100.0)
		_:
			if key.begins_with("event:"):
				var id = key.trim_prefix("event:")
				preferences.disabled_events.erase(id)
				if not value:
					preferences.disabled_events.append(id)
	_apply_preferences()
	care_menu.refresh_options()
	if preferences.save_preferences() != OK:
		care_menu.options_status.text = "Applied, but preferences could not be saved."


func _on_event_requested(id):
	if id == "hop_window" and window_platforms.platforms.is_empty():
		care_menu._show_feedback("No visible window has enough room above it yet.")
		return
	if not events.trigger(id):
		care_menu._show_feedback("Let the boi finish what he's doing, then try again.")
