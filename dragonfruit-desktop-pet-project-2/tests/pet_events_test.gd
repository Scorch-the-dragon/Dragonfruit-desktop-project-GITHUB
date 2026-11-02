extends SceneTree

var failures = 0


func check(condition, description):
	if not condition:
		failures += 1
		push_error(description)


func _init():
	call_deferred("run_checks")


func run_checks():
	var pet = load("res://Main.tscn").instantiate()
	root.add_child(pet)
	pet.set_physics_process(false)
	pet.care_menu.set_process(false)
	pet.screen_size = Vector2(1000, 800)
	pet.window_size = Vector2(200, 200)
	pet.win_pos = Vector2(400, 600)
	pet.surface = pet.Surface.FLOOR
	pet.idle_chance = 0.0
	var events = pet.events
	events.random_events_enabled = false
	var menu = pet.care_menu
	var original_position = pet.sprite.position
	var hunger = menu.hunger
	check(events.catalog.size() == menu.events_list.get_child_count(), "Menu lists every catalog event")
	for button in menu.find_children("*", "Button", true, false):
		if button.text == "Shenanigans":
			button.pressed.emit()
	check(menu.events_view.visible and not menu.care_view.visible, "Shenanigans opens the event list")
	menu.events_list.get_child(0).pressed.emit()
	check(events.active_id == "blow_up", "Event button triggers the registered event")
	check(menu.care_view.visible and not menu.events_view.visible, "Event selection returns to care feedback")
	check(not pet.sprite.visible and events.burst.visible, "Explosion replaces the pet with a burst")
	check(not events.trigger("blow_up"), "Events cannot overlap")
	check(not pet._begin_consuming("food"), "Consumption cannot interrupt an event")
	pet._offer_item("food")
	check(not pet.care_item.visible, "Food cannot spawn during disappearance")
	for i in range(3):
		pet._update_petting(0.05, Vector2(i * 30, 0), true, false)
	check(not pet.is_petting, "Petting cannot interrupt an event")
	var old_position = pet.win_pos
	pet._physics_process(0.2)
	check(pet.win_pos == old_position and events.burst.progress > 0, "Event owns movement while the burst expands")
	check(events.explosion_audio.playing and events.explosion_audio.stream != null, "Explosion plays supplied sound")
	events.advance(events.burst.duration - events.elapsed + 0.01)
	check(not pet.sprite.visible and not events.burst.visible, "Pet disappears briefly after the burst")
	events.advance(0.6)
	check(pet.sprite.visible and pet.win_pos.y == 0, "Pet returns at the top of the screen")
	check(pet.sprite.position.y < original_position.y, "Returning sprite enters from above")
	for i in range(120):
		if not events.active_id.is_empty():
			events.advance(1.0 / 60.0)
	check(events.active_id.is_empty() and pet.sprite.visible, "Event finishes and leaves the pet visible")
	check(pet.sprite.position == original_position, "Sprite position is restored")
	check(pet.surface == pet.Surface.FALLING and pet.fall_speed > 0, "Event hands motion back to gravity")
	check(menu.hunger == hunger, "Event preserves care stats")
	for i in range(120):
		pet._advance_motion(1.0 / 60.0, Vector2(800, 600))
	check(pet.surface == pet.Surface.FLOOR, "Pet lands after returning")
	check(not events.trigger("unknown_event"), "Unknown event ID is rejected")

	# Force deterministic probability endpoints to test the random scheduler.
	events.random_events_enabled = true
	events.event_chance = 1.0
	events.wait_remaining = 0.0
	pet.is_dragging = true
	events.advance(1.0)
	check(events.active_id.is_empty(), "Random event waits while dragging")
	pet.is_dragging = false
	pet.is_petting = true
	check(not events.trigger("blow_up"), "Manual event waits while petting")
	pet.is_petting = false
	pet.consuming_kind = "food"
	check(not events.trigger("blow_up"), "Manual event waits while consuming")
	pet.consuming_kind = ""
	pet.surface = pet.Surface.FALLING
	check(not events.trigger("blow_up"), "Manual event waits while falling")
	pet.surface = pet.Surface.FLOOR
	pet.care_item.show()
	check(not events.trigger("blow_up"), "An offered item blocks events")
	pet.care_item.hide()
	events.event_chance = 0.0
	events.advance(0.1)
	check(events.active_id.is_empty() and events.wait_remaining > 0, "Zero chance skips the event and schedules another check")
	events.event_chance = 1.0
	events.wait_remaining = 0.0
	check(events.advance(0.1) and not events.active_id.is_empty(), "Random scheduler can trigger a registered event")
	for i in range(1800):
		if not events.active_id.is_empty():
			events.advance(1.0 / 60.0)
	check(events.wait_remaining >= events.minimum_wait, "Completion resets the random cooldown")
	# Test expansion: the same registry supplies both manual and random triggers.
	events.register_event("test_event", "Test event", "Test registry extension", func(): pass, func(_delta): return true)
	menu.set_events(events.catalog)
	pet.surface = pet.Surface.FLOOR
	check(menu.events_list.get_child_count() == events.catalog.size(), "Newly registered event appears in the menu")
	menu.events_list.get_child(menu.events_list.get_child_count() - 1).pressed.emit()
	check(events.active_id == "test_event", "Each menu button dispatches its own event ID")
	events.advance(0.1)
	check(events.active_id.is_empty(), "Custom event can finish through the common scheduler")
	# Use an isolated folder to test note reading without changing users' notes.
	var delivery = events.note_delivery
	var fixture_folder = "res://.godot/note-test-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(fixture_folder)
	delivery.notes_folder = fixture_folder
	var empty_note = delivery.read_random_note()
	check(empty_note.filename == "No notes yet", "Empty note folders give helpful text")
	var fixture = FileAccess.open(fixture_folder.path_join("sample.txt"), FileAccess.WRITE)
	fixture.store_string("A note for the boi.\n[b]This is literal text.[/b]\nUnicode: café")
	fixture.close()
	var ignored = FileAccess.open(fixture_folder.path_join("ignore.md"), FileAccess.WRITE)
	ignored.store_string("Ignore this non-txt file")
	ignored.close()
	var note = delivery.read_random_note()
	check(note.filename == "sample.txt" and note.contents.contains("café"), "Reads UTF-8 text and ignores other extensions")
	for chosen_side in [-1, 1]:
		pet.surface = pet.Surface.FLOOR
		pet.win_pos = Vector2(400, 600)
		check(events.trigger("bring_note"), "Bring a note can be manually triggered")
		watch_visibility(delivery.note_window)
		delivery.side = chosen_side
		var phases = {}
		for i in range(1800):
			if events.active_id.is_empty():
				break
			phases[delivery.phase] = true
			events.advance(1.0 / 60.0)
			check(delivery.note_window.size == Vector2i(int(delivery.note_width), int(delivery.note_height)), "Note keeps fixed size during delivery")
			if delivery.phase == "pull":
				check(delivery.sliding_audio.playing and delivery.sliding_audio.stream.loop, "Note pulling loops sliding sound")
			else:
				check(not delivery.sliding_audio.playing, "Note sound is silent outside pulling")
			if delivery.phase == "pull":
				check_delivery_position(delivery, pet, chosen_side)
		check(events.active_id.is_empty(), "Note delivery finishes from either side")
		check(not delivery.sliding_audio.playing, "Note release stops sliding sound")
		check(delivery.note_window.get_meta("visibility_changes") == 1, "Note is shown once with no hide/show at release")
		# Headless DisplayServer does not retain native focus flags after show().
		check(not delivery.note_window.transparent and not delivery.note_window.transparent_bg and (DisplayServer.get_name() == "headless" or delivery.note_window.unfocusable),
			"Note flags: transparent=%s background=%s unfocusable=%s" % [delivery.note_window.transparent, delivery.note_window.transparent_bg, delivery.note_window.unfocusable])
		check(phases.has("vanish") and phases.has("fetch") and phases.has("pull"), "Pet leaves, fetches, and pulls the note")
		check(pet.sprite.visible and pet.sprite.position == original_position, "Delivery restores the pet sprite")
		check(pet.surface == pet.Surface.FLOOR, "Pet resumes floor walking after delivery")
		check(delivery.note_window.visible and not delivery.note_window.borderless, "Delivered text window stays open with native controls")
		check(delivery.note_window.text_box.text == note.contents, "The window shows the selected file verbatim")
		check(not delivery.note_window.text_box.editable, "Viewing notes cannot edit source files")
		delivery.note_window.close_requested.emit()
		check(not delivery.note_window.visible, "Note window can be closed")
	fixture = FileAccess.open(fixture_folder.path_join("sample.txt"), FileAccess.WRITE)
	fixture.store_string("Updated between events")
	fixture.close()
	check(delivery.read_random_note().contents == "Updated between events", "Notes are read fresh each time")
	delivery.max_note_bytes = 5
	check(delivery.read_random_note().contents.begins_with("Updat\n"), "Large notes are bounded")
	DirAccess.remove_absolute(fixture_folder.path_join("sample.txt"))
	DirAccess.remove_absolute(fixture_folder.path_join("ignore.md"))
	var image_delivery = events.image_delivery
	image_delivery.images_folder = fixture_folder
	check(image_delivery.read_random_image().texture == null, "Empty image folder gives helpful fallback")
	var test_image = Image.create(320, 160, false, Image.FORMAT_RGBA8)
	test_image.fill(Color.CORNFLOWER_BLUE)
	check(test_image.save_png(fixture_folder.path_join("picture.png")) == OK, "Creates an unimported image fixture")
	var selected_image = image_delivery.read_random_image()
	check(selected_image.filename == "picture.png" and selected_image.texture.get_size() == Vector2(320, 160),
		"Loads newly added image files without an editor import")
	for chosen_side in [-1, 1]:
		pet.surface = pet.Surface.FLOOR
		pet.win_pos = Vector2(400, 600)
		check(events.trigger("bring_image"), "Image event can be triggered")
		watch_visibility(image_delivery.note_window)
		image_delivery.side = chosen_side
		var phases = {}
		for i in range(1800):
			if events.active_id.is_empty():
				break
			phases[image_delivery.phase] = true
			events.advance(1.0 / 60.0)
			check(image_delivery.note_window.size == Vector2i(int(image_delivery.note_width), int(image_delivery.note_height)), "Image keeps fixed size during delivery")
			if image_delivery.phase == "pull":
				check(image_delivery.sliding_audio.playing, "Image pulling uses sliding sound too")
			else:
				check(not image_delivery.sliding_audio.playing, "Image sound is silent outside pulling")
			if image_delivery.phase == "pull":
				check_delivery_position(image_delivery, pet, chosen_side)
		check(events.active_id.is_empty() and phases.has("fetch") and phases.has("pull"), "Image retrieved from either side")
		check(pet.surface == pet.Surface.FLOOR and pet.sprite.position == original_position, "Image delivery restores normal movement")
		var viewer = image_delivery.note_window
		check(viewer.get_meta("visibility_changes") == 1, "Image is shown once with no hide/show at release")
		check(not viewer.transparent and not viewer.transparent_bg and (DisplayServer.get_name() == "headless" or viewer.unfocusable),
			"Image flags: transparent=%s background=%s unfocusable=%s" % [viewer.transparent, viewer.transparent_bg, viewer.unfocusable])
		check(viewer.visible and viewer.picture.visible and not viewer.text_box.visible, "Delivered window shows the image")
		check(viewer.picture.texture.get_size() == Vector2(320, 160), "Image texture is preserved")
		check(viewer.picture.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and not viewer.unresizable,
			"Resizable image window preserves aspect ratio")
		viewer.close_requested.emit()
		check(not viewer.visible, "Image window closes normally")
	test_image.fill(Color.RED)
	test_image.save_png(fixture_folder.path_join("picture.png"))
	check(image_delivery.read_random_image().texture.get_image().get_pixel(0, 0) == Color.RED, "Changed images reload on subsequent events")
	image_delivery.max_image_bytes = 1
	check(image_delivery.read_random_image().texture == null, "Oversize images are skipped gracefully")
	# Leave successive notes AND images open and verify they are independent.
	delivery.max_note_bytes = 262144
	image_delivery.max_image_bytes = 32 * 1024 * 1024
	fixture = FileAccess.open(fixture_folder.path_join("sample.txt"), FileAccess.WRITE)
	fixture.store_string("First note")
	fixture.close()
	complete_delivery(pet, "bring_note")
	var first_note = delivery.note_window
	var first_note_position = first_note.position
	fixture = FileAccess.open(fixture_folder.path_join("sample.txt"), FileAccess.WRITE)
	fixture.store_string("Second note")
	fixture.close()
	complete_delivery(pet, "bring_note")
	var second_note = delivery.note_window
	check(first_note != second_note and first_note.visible and second_note.visible, "Multiple note windows stay open")
	check(first_note.text_box.text == "First note" and second_note.text_box.text == "Second note", "Each note keeps its own content")
	check(first_note.position == first_note_position, "Later delivery does not move earlier note")
	complete_delivery(pet, "bring_image")
	var first_image = image_delivery.note_window
	test_image.fill(Color.BLUE)
	test_image.save_png(fixture_folder.path_join("picture.png"))
	complete_delivery(pet, "bring_image")
	var second_image = image_delivery.note_window
	check(first_image != second_image and first_image.visible and second_image.visible and first_note.visible and second_note.visible,
		"Notes and images coexist after repeated deliveries")
	check(first_image.picture.texture.get_image().get_pixel(0, 0) == Color.RED and second_image.picture.texture.get_image().get_pixel(0, 0) == Color.BLUE,
		"Each image keeps its own texture")
	first_note.close_requested.emit()
	first_image.close_requested.emit()
	await process_frame
	await process_frame
	check(not is_instance_valid(first_note) and not is_instance_valid(first_image), "Closing a delivered window releases its resources")
	check(second_note.visible and second_image.visible, "Closing older windows leaves newer ones intact")
	DirAccess.remove_absolute(fixture_folder.path_join("sample.txt"))
	DirAccess.remove_absolute(fixture_folder.path_join("picture.png"))
	DirAccess.remove_absolute(fixture_folder)
	# Simulate cursor IO so event tests never warp the user's actual pointer.
	var pounce = events.mouse_pounce
	var cursor = {"position": pet.screen_origin + Vector2(700, 350), "moves": 0}
	pounce.read_pointer = func(): return cursor.position
	pounce.move_pointer = func(at):
		cursor.position = at
		cursor.moves += 1
	pet.surface = pet.Surface.FLOOR
	pet.win_pos = Vector2(400, 600)
	check(events.trigger("mouse_pounce"), "Pounce event starts")
	check(pet.sprite.animation == "splat", "Pounce uses the splat artwork")
	var first_cursor = cursor.position
	var saw_jump_rotation = false
	var saw_carry_fall = false
	var saw_walk = false
	var walk_start_x = 0.0
	for i in range(600):
		if events.active_id.is_empty():
			break
		events.advance(1.0 / 60.0)
		if pounce.phase == "jump" and not is_zero_approx(pet.sprite.rotation):
			saw_jump_rotation = true
		if pounce.phase == "carry_fall":
			saw_carry_fall = true
			check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Carried cursor remains visible")
		if pounce.phase == "carry_walk":
			if not saw_walk:
				walk_start_x = pet.win_pos.x
			saw_walk = true
			check(saw_carry_fall and pet.win_pos.y == pounce.limits.y, "Carrying walk starts only after landing")
			check(pet.sprite.animation in ["walk_left", "walk_right"], "Carry uses walking animation on floor")
	check(events.active_id.is_empty() and saw_jump_rotation and saw_carry_fall and saw_walk, "Pounce rotates in flight, catches, lands, walks, and completes")
	check(cursor.moves > 0 and cursor.position.distance_to(first_cursor) > 10, "Caught cursor is pulled elsewhere")
	check(Rect2(pet.screen_origin, pet.screen_size).has_point(cursor.position), "Carry keeps the cursor on the monitor")
	check(pet.surface == pet.Surface.FLOOR and is_zero_approx(pet.sprite.rotation), "Pounce releases on the floor upright")
	check(absf(pet.win_pos.x - walk_start_x) >= pounce.carry_walk_distance - 1.0, "Pet walks the carrying distance before release")
	pet.surface = pet.Surface.FLOOR
	pet.win_pos = Vector2(400, 600)
	cursor.position = pet.screen_origin + Vector2(700, 350)
	cursor.moves = 0
	events.trigger("mouse_pounce")
	cursor.position = pet.screen_origin - Vector2(1000, 1000)
	for i in range(120):
		if events.active_id.is_empty():
			break
		events.advance(1.0 / 60.0)
	check(events.active_id.is_empty() and cursor.moves == 0, "Dodged pounce never moves the cursor")
	pet.surface = pet.Surface.FLOOR
	cursor.position = pet.screen_origin + Vector2(700, 350)
	events.trigger("mouse_pounce")
	pounce.cancel_requested = true
	events.advance(0.01)
	check(events.active_id.is_empty() and cursor.moves == 0, "Cancellation immediately releases control without cursor movement")
	for cancel_phase in ["carry_fall", "carry_walk"]:
		pet.surface = pet.Surface.FLOOR
		pet.win_pos = Vector2(400, 600)
		cursor.position = pet.screen_origin + Vector2(700, 350)
		events.trigger("mouse_pounce")
		for i in range(300):
			if pounce.phase == cancel_phase or events.active_id.is_empty():
				break
			events.advance(1.0 / 60.0)
		check(pounce.phase == cancel_phase, "Reached cancellation phase: " + cancel_phase)
		var moves_before_cancel = cursor.moves
		pounce.cancel_requested = true
		events.advance(0.01)
		check(events.active_id.is_empty() and cursor.moves == moves_before_cancel, "Cancellation stops pointer movement during " + cancel_phase)
		check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Released pointer stays visible")
	# Both floor edges must lead inward, so there is room to carry the cursor.
	for edge in [0.0, pounce.limits.x]:
		pet.win_pos = Vector2(edge, pounce.limits.y)
		pounce._start_walk()
		check(absf(pounce.walk_target_x - edge) > 0.0, "Carry walk heads inward from either edge")
	pounce._finish()
	pet.free()
	if failures == 0:
		print("PASS: event menu, explosion lifecycle, return/landing, busy guards, random scheduling, and registry extension")
	quit(1 if failures else 0)


func check_delivery_position(delivery, pet, chosen_side):
	var pos = delivery._trailing_window_position()
	if delivery.travel == 0.0:
		if chosen_side < 0:
			check(pos.x + delivery.note_width < pet.screen_origin.x, "Left delivery spawns fully offscreen")
		else:
			check(pos.x > pet.screen_origin.x + pet.screen_size.x, "Right delivery spawns fully offscreen")
	var expected_x = pet.win_pos.x - delivery.note_width - 8 if chosen_side < 0 else pet.win_pos.x + pet.window_size.x + 8
	check(absf(pos.x - pet.screen_origin.x - expected_x) <= 1.0, "Window trails the pet at a constant distance")


func watch_visibility(viewer):
	viewer.set_meta("visibility_changes", 0)
	viewer.visibility_changed.connect(func():
		viewer.set_meta("visibility_changes", viewer.get_meta("visibility_changes") + 1))


func complete_delivery(pet, id):
	pet.surface = pet.Surface.FLOOR
	pet.win_pos = Vector2(400, 600)
	check(pet.events.trigger(id), "Repeated delivery starts")
	for i in range(1800):
		if pet.events.active_id.is_empty():
			break
		pet.events.advance(1.0 / 60.0)
	check(pet.events.active_id.is_empty(), "Repeated delivery finishes")


