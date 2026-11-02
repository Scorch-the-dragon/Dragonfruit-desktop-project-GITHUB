# Prop factory and play behavior. Add more kinds to spawn_prop() in the future.
extends Node

const RECOVERY_PROFILES = preload("res://Audio/ReverseSqueakProfiles.gd").DATA
# Keep these in the same order as RECOVERY_SOUNDS: one random index selects
# both the impact squeak and its reversed version for unflattening.
const HIT_SOUNDS = [
	preload("res://Audio/soft-squeak-made-with-Voicemod.mp3"),
	preload("res://Audio/squeaky-made-with-Voicemod.mp3"),
	preload("res://Audio/squeaky-toy-made-with-Voicemod.mp3"),
]
const RECOVERY_SOUNDS = [
	preload("res://Audio/soft-squeak-reversed.wav"),
	preload("res://Audio/squeaky-reversed.wav"),
	preload("res://Audio/squeaky-toy-reversed.wav"),
]

var pet
var balls: Array = []
var kick_wait = 0.0
var chase_speed = 170.0
var maximum_balls = 5
var paint_props: Array = []
var maximum_paint_props = 10
var original_color = Color.WHITE
var color_saved = false
var contact_bounds = {}
var anvils: Array = []
var portal_balls: Array = []
# Seconds flattened, followed by a springy return to normal size.
var flatten_seconds = 2.5
var recover_seconds = 1.0
var squash_remaining = 0.0
var saved_scale = Vector2.ONE
var saved_position = Vector2.ZERO
var saved_rotation = 0.0
var saved_flip = false
var squash_foot = 0.0
var recovery_audio: AudioStreamPlayer
var hit_audio: AudioStreamPlayer
var recovery_started = false
var recovery_elapsed = 0.0
var recovery_profile = {}

func _ready():
	hit_audio = AudioStreamPlayer.new()
	hit_audio.volume_db = -5.0
	add_child(hit_audio)
	recovery_audio = AudioStreamPlayer.new()
	recovery_audio.volume_db = -5.0
	add_child(recovery_audio)

func is_squashed():
	return squash_remaining > 0.0

func check_anvil_hit(anvil, previous):
	if pet.vitality <= 0.0:
		return
	if pet.click_squish != null and pet.click_squish.active:
		return
	if anvil.dragging or is_squashed() or not pet.sprite.is_visible_in_tree():
		return
	if pet.is_dragging or pet.click_pending or not pet.consuming_kind.is_empty() or (pet.events != null and not pet.events.active_id.is_empty()):
		return
	var bounds = pet_artwork_bounds()
	var old_bottom = previous.y + anvil.size.y
	var new_bottom = anvil.ball_position.y + anvil.size.y
	# Swept top contact detects a fast drop even if it crosses the pet in one tick.
	if new_bottom <= old_bottom or old_bottom > bounds.position.y or new_bottom < bounds.position.y:
		return
	var fraction = (bounds.position.y - old_bottom) / (new_bottom - old_bottom)
	var hit_x = lerpf(previous.x, anvil.ball_position.x, fraction)
	if hit_x + anvil.size.x <= bounds.position.x or hit_x >= bounds.end.x:
		return
	pet._end_petting()
	pet.is_idling = false
	saved_scale = pet.sprite.scale
	saved_position = pet.sprite.position
	saved_rotation = pet.sprite.rotation
	saved_flip = pet.sprite.flip_h
	pet.sprite.rotation = 0.0
	# Splat faces right by default; walking uses separate left/right artwork,
	# so use travel direction rather than copying the walking sprite's flip.
	var heading = pet.horizontal_fall_speed if pet.surface == pet.Surface.FALLING else pet.direction.x
	pet.sprite.flip_h = heading < 0.0 if not is_zero_approx(heading) else pet.falling_faces_left
	pet.sprite.play("splat")
	var texture = pet.sprite.sprite_frames.get_frame_texture("splat", 0)
	squash_foot = texture.get_image().get_used_rect().end.y - texture.get_height() * 0.5 + pet.sprite.offset.y
	# Squeak immediately, then remember the matching reverse for recovery.
	var squeak_index = randi_range(0, HIT_SOUNDS.size() - 1)
	hit_audio.stream = HIT_SOUNDS[squeak_index]
	hit_audio.play()
	recovery_audio.stop()
	recovery_audio.stream = RECOVERY_SOUNDS[squeak_index]
	recovery_profile = RECOVERY_PROFILES[recovery_audio.stream.resource_path.get_file()]
	# Allow a short settling bounce after the selected squeak finishes.
	recover_seconds = recovery_profile.length + 0.3
	recovery_started = false
	recovery_elapsed = 0.0
	squash_remaining = flatten_seconds + recover_seconds
	_set_squash(Vector2(1.25, 0.18))

func _set_squash(factor):
	pet.sprite.scale = saved_scale * factor
	# Keep the feet in place rather than shrinking toward the sprite's center.
	pet.sprite.position = saved_position + Vector2(0.0, squash_foot * (saved_scale.y - pet.sprite.scale.y))

func advance_squash(delta):
	if not is_squashed():
		return false
	if not recovery_started:
		squash_remaining = maxf(recover_seconds, squash_remaining - delta)
		if squash_remaining <= recover_seconds:
			recovery_started = true
			hit_audio.stop()
			recovery_audio.play()
	else:
		recovery_elapsed += delta
		if recovery_audio.playing:
			# Follow the audible playback clock, including output latency, so
			# frame-rate changes do not make the bounce run ahead of the squeak.
			recovery_elapsed = maxf(0.0, recovery_audio.get_playback_position()
				+ AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())
		squash_remaining = maxf(0.0, recover_seconds - recovery_elapsed)
	if squash_remaining <= 0.0:
		recovery_audio.stop()
		pet.sprite.scale = saved_scale
		pet.sprite.position = saved_position
		pet.sprite.rotation = saved_rotation
		pet.sprite.flip_h = saved_flip
		pet._update_animation()
	elif recovery_started:
		_set_squash(_recovery_shape(recovery_elapsed))
	# An airborne hit still falls; flattening must not suspend gravity.
	if pet.surface == pet.Surface.FALLING:
		pet._advance_motion(delta, (pet.screen_size - pet.window_size).max(Vector2.ZERO))
		pet._apply_window_position()
	pet.is_idling = false
	if is_squashed():
		pet.sprite.play("splat")
	else:
		pet._update_animation()
	return true

func _recovery_shape(audio_time):
	var t = clampf(audio_time / recover_seconds, 0.0, 1.0)
	if t >= 1.0:
		return Vector2.ONE
	var sample = maxf(0.0, audio_time) / recovery_profile.step
	var index = int(sample)
	var level = 0.0
	if index < recovery_profile.envelope.size() and audio_time < recovery_profile.length:
		level = lerpf(recovery_profile.envelope[index],
			recovery_profile.envelope[mini(index + 1, recovery_profile.envelope.size() - 1)], sample - index)
	# A fading spring supplies the cartoon bounce. The actual reversed audio's
	# loudness adds extra stretch; sin() fades it out at both ends.
	var spring = exp(-5.0 * t) * cos(t * TAU * 2.0) * (1.0 - t)
	var stretch = level * 0.18 * sin(PI * t)
	return Vector2(1.0 + 0.25 * spring - stretch * 0.5, 1.0 - 0.82 * spring + stretch)

func _physics_process(_delta):
	# Main pauses recovery when all needs reach zero; pause its sound as well.
	recovery_audio.stream_paused = pet.vitality <= 0.0
	hit_audio.stream_paused = pet.vitality <= 0.0
	check_paint_contacts()

func check_paint_contacts():
	paint_props = paint_props.filter(func(prop): return is_instance_valid(prop) and not prop.is_queued_for_deletion())
	if paint_props.is_empty() or not pet.sprite.is_visible_in_tree():
		return
	var bounds = pet_artwork_bounds()
	for prop in paint_props:
		if prop.visible and bounds.intersects(Rect2(prop.ball_position, Vector2(prop.size))):
			apply_paint(prop.kind)
			prop.hide()
			prop.queue_free()

func pet_artwork_bounds():
	# Contact uses the visible artwork bounds, not the transparent 200px window.
	var texture = pet.sprite.sprite_frames.get_frame_texture(pet.sprite.animation, pet.sprite.frame)
	if texture == null:
		return Rect2()
	if not contact_bounds.has(texture):
		contact_bounds[texture] = Rect2(texture.get_image().get_used_rect())
	var local = contact_bounds[texture]
	local.position += pet.sprite.offset
	if pet.sprite.centered:
		local.position -= texture.get_size() * 0.5
	if pet.sprite.flip_h:
		local.position.x = -local.end.x
	if pet.sprite.flip_v:
		local.position.y = -local.end.y
	var bounds = pet.sprite.get_global_transform() * local
	var scale_factor = pet.window_size / pet.get_viewport_rect().size.max(Vector2.ONE)
	bounds = Rect2(pet.screen_origin + pet.win_pos + bounds.position * scale_factor, bounds.size * scale_factor)
	return bounds

func apply_paint(kind):
	if not color_saved:
		original_color = pet.sprite.self_modulate
		color_saved = true
	# Tint the sprite itself so the color survives animation/state changes.
	pet.sprite.self_modulate = original_color * Color(0.25, 1.0, 0.25) if kind == "green_paint" else original_color

func spawn_prop(kind = "ball"):
	portal_balls = portal_balls.filter(func(prop): return is_instance_valid(prop) and not prop.is_queued_for_deletion())
	if kind in ["blue_portal", "orange_portal"]:
		if portal_balls.size() >= 10: return null
		var prop = preload("res://Code/PortalBall.gd").new()
		prop.portal_color = "blue" if kind == "blue_portal" else "orange"
		prop.portals = pet.portals
		add_child(prop)
		_place_near_menu(prop)
		portal_balls.append(prop)
		return prop
	anvils = anvils.filter(func(prop): return is_instance_valid(prop) and not prop.is_queued_for_deletion())
	if kind == "anvil":
		if anvils.size() >= 5:
			return null
		var anvil = preload("res://Code/AnvilProp.gd").new()
		anvil.props = self
		add_child(anvil)
		_place_near_menu(anvil)
		anvils.append(anvil)
		return anvil
	paint_props = paint_props.filter(func(prop): return is_instance_valid(prop) and not prop.is_queued_for_deletion())
	if kind in ["green_paint", "paint_remover"]:
		if paint_props.size() >= maximum_paint_props:
			return null
		var prop = preload("res://Code/PaintProp.gd").new()
		prop.kind = kind
		add_child(prop)
		_place_near_menu(prop)
		paint_props.append(prop)
		return prop
	balls = balls.filter(func(ball): return is_instance_valid(ball) and not ball.is_queued_for_deletion())
	if kind != "ball" or balls.size() >= maximum_balls:
		return null
	var ball = preload("res://Code/BallProp.gd").new()
	add_child(ball)
	_place_near_menu(ball)
	balls.append(ball)
	return ball

func _place_near_menu(prop):
	# Use the menu's monitor, even if the pet has wandered onto another one.
	var menu = pet.care_menu
	var screen = DisplayServer.window_get_current_screen(menu.get_window_id())
	var bounds = Rect2(Vector2(DisplayServer.screen_get_position(screen)), Vector2(DisplayServer.screen_get_size(screen)))
	var usable = Rect2(DisplayServer.screen_get_usable_rect(screen))
	var prop_size = Vector2(prop.size)
	var desired = Vector2(menu.position) + Vector2(menu.size.x + 12, 64)
	# Prefer the right side; use the left when the menu is near the right edge.
	if desired.x + prop_size.x > usable.end.x:
		desired.x = menu.position.x - prop_size.x - 12
	desired = desired.clamp(usable.position, (usable.end - prop_size).max(usable.position))
	prop.place(desired, bounds)

func remove_props():
	for ball in balls + paint_props + anvils + portal_balls:
		if is_instance_valid(ball):
			ball.queue_free()
	balls.clear()
	paint_props.clear()
	anvils.clear()
	portal_balls.clear()
	pet.portals.clear_portals()

func advance_play(delta):
	var previous_position = pet.win_pos
	kick_wait = maxf(0.0, kick_wait - delta)
	balls = balls.filter(func(ball): return is_instance_valid(ball) and not ball.is_queued_for_deletion())
	var target = null
	var nearest = INF
	var center = pet.screen_origin + pet.win_pos + pet.window_size * 0.5
	for ball in balls:
		if ball.dragging or not ball.visible or not Rect2(pet.screen_origin, pet.screen_size).has_point(ball.ball_position + Vector2(ball.size) * 0.5):
			continue
		var distance = center.distance_squared_to(ball.ball_position)
		if distance < nearest:
			nearest = distance
			target = ball
	if target == null:
		return false
	pet.is_idling = false
	# Leave walls/perches under gravity to go play on the desktop floor.
	if pet.surface not in [pet.Surface.FLOOR, pet.Surface.FALLING]:
		pet.surface = pet.Surface.FALLING
		pet.fall_speed = 0.0
	var offset = target.ball_position.x + target.size.x * 0.5 - center.x
	var heading = signf(offset)
	if not is_zero_approx(heading):
		pet.direction = Vector2(heading, 0)
	if pet.surface == pet.Surface.FALLING:
		return false
	var limits = (pet.screen_size - pet.window_size).max(Vector2.ZERO)
	pet.win_pos.y = limits.y
	if absf(offset) > 65.0:
		pet.win_pos.x = clampf(pet.win_pos.x + heading * minf(chase_speed * delta, absf(offset)), 0.0, limits.x)
	# Kick only when close in both axes; never kick a ball still high in the air.
	if absf(offset) <= 90.0 and target.ball_position.y + target.size.y >= pet.screen_origin.y + pet.screen_size.y - 110.0 and kick_wait <= 0.0:
		if is_zero_approx(heading):
			heading = -1.0 if randf() < 0.5 else 1.0
		var ball_x = target.ball_position.x - pet.screen_origin.x
		if ball_x < 90.0:
			heading = 1.0
		elif ball_x > pet.screen_size.x - 150.0:
			heading = -1.0
		target.velocity = Vector2(heading * randf_range(300.0, 460.0), -randf_range(180.0, 320.0))
		kick_wait = 1.2
	pet.portals.cooldown = maxf(0.0, pet.portals.cooldown - delta)
	pet.portals.try_travel(previous_position, false)
	pet._update_animation()
	pet._apply_window_position()
	return true
