# EVENT CATALOG AND SCHEDULER
# To add an event, register it in setup() with an ID, label, description, and
# two Callables. The start function sets up the event; tick(delta) returns true
# when finished. Both the random picker and Shenanigans use this same catalog.
# Keep animations/effects in those functions and restore changes before finishing.
extends Node

signal event_started(label)
signal event_finished(label)

# Random events wait 30-90 eligible seconds, then have a 25% chance to happen.
# Busy time (dragging, petting, consuming, falling, or moving an item) does not count.
var random_events_enabled = true
var disabled_events: Array[String] = []
var minimum_wait = 30.0
var maximum_wait = 90.0
var event_chance = 0.25
var wait_remaining = 0.0
var catalog: Array[Dictionary] = []
var active_id = ""
var pet
var elapsed = 0.0
var burst
var saved_position = Vector2()
var saved_rotation = 0.0
var saved_flip = false
var returned = false
var return_speed = 0.0
var note_delivery
var image_delivery
var mouse_pounce
var explosion_audio: AudioStreamPlayer
# Throw count lasts for this run and resets whenever the pet explodes.
var throws_since_explosion = 0
var explosion_chance_per_throw = 0.10
var maximum_landing_explosion_chance = 0.75


func setup(pet_node):
	pet = pet_node
	burst = preload("res://Code/PetBurst.gd").new()
	burst.visible = false
	pet.add_child(burst)
	explosion_audio = AudioStreamPlayer.new()
	explosion_audio.stream = load("res://Audio/deltarune-explosion-made-with-Voicemod.mp3")
	explosion_audio.volume_db = -8.0 # Uses the same Master volume as Options.
	add_child(explosion_audio)
	register_event("blow_up", "Blow up", "A cartoon burst, a brief disappearance, then a fall from above.", _start_blow_up, _tick_blow_up)
	note_delivery = preload("res://Code/NoteDelivery.gd").new()
	add_child(note_delivery)
	note_delivery.setup(pet)
	register_event("bring_note", "Bring a note", "Walk off-screen and return dragging a random .txt file from PetNotes.", note_delivery.start, note_delivery.advance)
	image_delivery = preload("res://Code/ImageDelivery.gd").new()
	add_child(image_delivery)
	image_delivery.setup(pet)
	register_event("bring_image", "Bring an image", "Run off-screen and return dragging a random image from PetImages.", image_delivery.start, image_delivery.advance)
	mouse_pounce = preload("res://Code/MousePounce.gd").new()
	add_child(mouse_pounce)
	mouse_pounce.setup(pet)
	register_event("hop_window", "Hop onto a window", "Fly onto a visible window with enough room above it.", pet.window_platforms.start_hop, pet.window_platforms.advance_hop)
	register_event("mouse_pounce", "Pounce at mouse", "Catch the cursor, fall to the floor, then carry it left or right before releasing. Escape or a mouse press cancels.", mouse_pounce.start, mouse_pounce.advance)
	_reset_wait()


func register_event(id, label, description, start_action: Callable, tick_action: Callable):
	for entry in catalog:
		if entry.id == id:
			push_error("Duplicate pet event ID: " + id)
			return
	catalog.append({"id": id, "label": label, "description": description, "start": start_action, "tick": tick_action})


func can_start():
	if pet.vitality <= 0.0:
		return false
	if pet.landing_splat_remaining > 0.0:
		return false
	if pet.click_squish != null and pet.click_squish.active:
		return false
	if pet.props != null and pet.props.is_squashed():
		return false
	return active_id.is_empty() and not pet.is_dragging and not pet.click_pending \
		and not pet.is_petting and pet.consuming_kind.is_empty() \
		and pet.surface != pet.Surface.FALLING and not pet.care_item.visible


# Returns false for unknown IDs or while the pet is busy; events never overlap.
func trigger(id):
	if id == "hop_window" and pet.window_platforms.platforms.is_empty():
		return false
	if disabled_events.has(id) or not can_start():
		return false
	for entry in catalog:
		if entry.id == id:
			active_id = id
			pet.is_idling = false
			pet.idle_timer = 0.0
			elapsed = 0.0
			entry.start.call()
			event_started.emit(entry.label)
			return true
	return false


# Main.gd calls this before normal movement. A true result owns this physics tick.
func advance(delta):
	if not active_id.is_empty():
		for entry in catalog:
			if entry.id == active_id:
				if entry.tick.call(delta):
					active_id = ""
					_reset_wait()
					event_finished.emit(entry.label)
				return true
	if random_events_enabled and can_start():
		wait_remaining -= delta
		if wait_remaining <= 0.0:
			_reset_wait()
			var enabled = catalog.filter(func(entry): return not disabled_events.has(entry.id) and (entry.id != "hop_window" or not pet.window_platforms.platforms.is_empty()))
			if not enabled.is_empty() and randf() < event_chance:
				return trigger(enabled.pick_random().id)
	return false


func _reset_wait():
	wait_remaining = randf_range(minimum_wait, maximum_wait)


func record_throw():
	throws_since_explosion += 1


func landing_explosion_chance():
	return minf(throws_since_explosion * explosion_chance_per_throw, maximum_landing_explosion_chance)


func try_landing_explosion():
	# Called only on an actual landing after a mouse throw, not wall bounces
	# or portal passages. Respect the user's existing automatic-event options.
	if not random_events_enabled or disabled_events.has("blow_up") or not can_start():
		return false
	if randf() >= landing_explosion_chance():
		return false
	return trigger("blow_up")


func _start_blow_up():
	throws_since_explosion = 0
	pet.throw_in_progress = false
	pet.landing_splat_remaining = 0.0
	explosion_audio.play()
	saved_position = pet.sprite.position
	saved_rotation = pet.sprite.rotation
	saved_flip = pet.sprite.flip_h
	returned = false
	return_speed = 0.0
	pet.sprite.hide()
	burst.position = pet.get_viewport_rect().size * 0.5
	burst.progress = 0.0
	burst.show()
	burst.queue_redraw()


func _tick_blow_up(delta):
	elapsed += delta
	if elapsed < burst.duration:
		burst.progress = elapsed / burst.duration
		burst.queue_redraw()
		return false
	burst.hide()
	if elapsed < burst.duration + 0.6:
		return false
	if not returned:
		returned = true
		# Keep the real window on-screen, and slide the sprite in from above its
		# viewport. This avoids Windows clamping an off-screen window position.
		pet.win_pos.x = clampf(pet.win_pos.x, 0.0, maxf(0.0, pet.screen_size.x - pet.window_size.x))
		pet.win_pos.y = 0.0
		pet._apply_window_position()
		pet.sprite.rotation = 0.0
		pet.sprite.flip_h = false
		pet.sprite.position = saved_position - Vector2(0, pet.get_viewport_rect().size.y)
		pet.sprite.play("fall")
		pet.sprite.show()
		# Begin entry on the next tick; do not apply time spent disappearing
		# as a giant fall step if the game briefly stalled.
		return false
	# Entry movement uses scene units; regular falling below uses desktop pixels.
	return_speed = minf(return_speed + pet.gravity * delta, pet.max_fall_speed)
	pet.sprite.position.y = minf(saved_position.y, pet.sprite.position.y + return_speed * delta)
	if pet.sprite.position.y < saved_position.y:
		return false
	pet.sprite.position = saved_position
	pet.sprite.rotation = saved_rotation
	pet.sprite.flip_h = saved_flip
	pet.surface = pet.Surface.FALLING
	pet.horizontal_fall_speed = 0.0
	pet.fall_speed = return_speed
	pet.mouse_over_pet = false
	pet._update_animation()
	return true
