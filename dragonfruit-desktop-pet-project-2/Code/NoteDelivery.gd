# Bring a text file onto the desktop. PetEvents registers start() and advance().
extends Node

var pet
var note_window
var notes_folder = ""
var delivery_speed = 260.0
var max_note_bytes = 262144
var side = -1 # -1: left edge; +1: right edge. Chosen randomly each delivery.
var phase = ""
var sprite_home = Vector2()
var sprite_rotation = 0.0
var sprite_flip = false
var pause_remaining = 0.0
var travel = 0.0
var note_width = 420.0
var note_height = 280.0
var limits = Vector2()
var sliding_audio: AudioStreamPlayer
var sliding_volume_db = -12.0 # Also controlled by the Options volume slider.


func setup(pet_node):
	pet = pet_node
	sliding_audio = AudioStreamPlayer.new()
	var sound = load("res://Audio/stone-sliding-loop-made-with-Voicemod.mp3").duplicate()
	sound.loop = true
	sliding_audio.stream = sound
	sliding_audio.volume_db = sliding_volume_db
	add_child(sliding_audio)
	notes_folder = "res://PetNotes" if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("PetNotes")

func _process(_delta):
	if sliding_audio != null and sliding_audio.playing:
		# Exhaustion pauses event movement; do not leave a sliding sound running.
		sliding_audio.stream_paused = pet.vitality <= 0.0 or not is_instance_valid(note_window) or not note_window.visible


# ImageDelivery overrides these two hooks and reuses the same movement sequence.
func _create_delivery_window():
	return preload("res://Code/PetNoteWindow.gd").new()


func _prepare_content():
	var note = read_random_note()
	note_window.set_note(note.filename, note.contents)


func read_random_note():
	var candidates: Array[String] = []
	var directory = DirAccess.open(notes_folder)
	if directory != null:
		for filename in directory.get_files():
			if filename.get_extension().to_lower() == "txt":
				candidates.append(filename)
	candidates.shuffle()
	# Skip unreadable files instead of getting stuck mid-event.
	for filename in candidates:
		var file = FileAccess.open(notes_folder.path_join(filename), FileAccess.READ)
		if file == null:
			continue
		var contents = file.get_buffer(mini(file.get_length(), max_note_bytes)).get_string_from_utf8()
		if file.get_length() > max_note_bytes:
			contents += "\n\n[Preview limited to the first 256 KiB.]"
		return {"filename": filename, "contents": contents}
	return {"filename": "No notes yet", "contents": "Add UTF-8 .txt files to:\n" + ProjectSettings.globalize_path(notes_folder) + "\n\nThen choose Bring a note again."}


func start():
	sliding_audio.stop()
	sliding_audio.stream_paused = false
	# Each delivery owns a fresh window. Earlier windows remain children of the
	# pet scene and keep their contents/position until the user closes them.
	note_window = _create_delivery_window()
	pet.add_child(note_window)
	note_window.begin_delivery()
	_prepare_content()
	# Keep the normal native title bar and frame throughout delivery, so there
	# is no switch from a bare image/text panel to a decorated window at the end.
	note_window.borderless = false
	note_window.unfocusable = true
	note_window.unresizable = false
	# Match the delivered window's stacking from the start; changing this at
	# release can blank the native surface and require a visible hide/show cycle.
	note_window.always_on_top = false
	side = -1 if randf() < 0.5 else 1
	sprite_home = pet.sprite.position
	sprite_rotation = pet.sprite.rotation
	sprite_flip = pet.sprite.flip_h
	limits = (pet.screen_size - pet.window_size).max(Vector2.ZERO)
	note_width = minf(420.0, maxf(64.0, limits.x - 16.0))
	note_height = minf(280.0, maxf(64.0, pet.screen_size.y - 48.0))
	# Set the final content size once while hidden. During delivery only POSITION
	# changes, so images never zoom and wrapped text never changes its line breaks.
	note_window.size = Vector2i(int(note_width), int(note_height))
	pet.surface = pet.Surface.FALLING
	pet.fall_speed = 0.0
	pet.horizontal_fall_speed = 0.0
	pet.sprite.rotation = 0.0
	pet.sprite.flip_h = false
	pet.sprite.play("fall")
	phase = "descend"


func advance(delta):
	match phase:
		"descend":
			# First reach the floor naturally if the event started on a wall/ceiling.
			pet.fall_speed = minf(pet.fall_speed + pet.gravity * delta, pet.max_fall_speed)
			pet.win_pos.y = minf(limits.y, pet.win_pos.y + pet.fall_speed * delta)
			if pet.win_pos.y >= limits.y:
				pet.fall_speed = 0.0
				phase = "exit"
				pet.sprite.play("walk_left" if side < 0 else "walk_right")
		"exit":
			var edge = 0.0 if side < 0 else limits.x
			pet.win_pos.x = move_toward(pet.win_pos.x, edge, delivery_speed * delta)
			if is_equal_approx(pet.win_pos.x, edge):
				phase = "vanish"
		"vanish":
			# Walk the sprite out of its viewport, without relying on Windows
			# allowing the actual pet window to leave the screen.
			pet.sprite.position.x += side * delivery_speed * delta
			if absf(pet.sprite.position.x - sprite_home.x) >= pet.get_viewport_rect().size.x:
				pet.sprite.hide()
				phase = "fetch"
				pause_remaining = 0.5
		"fetch":
			pause_remaining -= delta
			if pause_remaining <= 0.0:
				phase = "reappear"
				pet.sprite.show()
				pet.sprite.play("walk_right" if side < 0 else "walk_left")
		"reappear":
			pet.sprite.position.x = move_toward(pet.sprite.position.x, sprite_home.x, delivery_speed * delta)
			if is_equal_approx(pet.sprite.position.x, sprite_home.x):
				phase = "pull"
				travel = 0.0
				# Spawn at full size just beyond the selected edge, behind the pet.
				var spawn_position = _trailing_window_position()
				note_window.position = spawn_position
				note_window.show()
				# Reapply after showing in case native window creation placed it.
				note_window.position = spawn_position
				sliding_audio.play()
		"pull":
			travel = minf(travel + delivery_speed * delta, minf(note_width + 12.0, limits.x))
			pet.win_pos.x = travel if side < 0 else limits.x - travel
			# Off-screen coordinates are intentional; the desktop clips the window
			# naturally as the pet pulls it into view. Do not clamp or resize here.
			note_window.position = _trailing_window_position()
			if travel >= minf(note_width + 12.0, limits.x):
				_finish()
				pet._apply_window_position()
				return true
	pet._apply_window_position()
	return false


func _trailing_window_position():
	var x = travel - note_width - 8.0 if side < 0 else pet.screen_size.x + 8.0 - travel
	return Vector2i(pet.screen_origin + Vector2(x, maxf(24.0, pet.screen_size.y - note_height - 40.0)))


func _finish():
	sliding_audio.stop()
	note_window.finish_delivery()
	pet.sprite.position = sprite_home
	pet.sprite.rotation = sprite_rotation
	pet.sprite.flip_h = sprite_flip
	pet.sprite.show()
	pet.surface = pet.Surface.FLOOR
	pet.direction = Vector2.RIGHT if side < 0 else Vector2.LEFT
	pet.fall_speed = 0.0
	pet.horizontal_fall_speed = 0.0
	pet.mouse_over_pet = false
	pet._update_animation()
	phase = ""
