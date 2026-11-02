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
	var menu = pet.care_menu
	menu.set_process(false)
	check(not menu.visible, "Menu starts closed")
	check(not root.gui_embed_subwindows, "Menu uses a separate desktop window")
	menu.hunger = 40.0
	menu.thirst = 50.0
	menu.happiness = 60.0
	# Exercise actual button signal connections, not just the stat methods.
	var buttons = menu.find_children("*", "Button", true, false)
	for button in buttons:
		check(button.text != "Play", "Play button has been removed")
		if button.text in ["Feed", "Drink"]:
			button.pressed.emit()
			check(pet.care_item.visible, "Care button shows a draggable item")
			check(pet.care_item.picture.texture != null, "Item has an image")
			var stat_before = menu.hunger if button.text == "Feed" else menu.thirst
			var kind = "food" if button.text == "Feed" else "drink"
			check(pet.care_item.kind == kind, "Button selects the matching item")
			check(not pet.consumption_audio.playing, "Offering an item does not play consumption audio")
			check(pet._begin_consuming(kind), "Pet accepts item")
			check(pet.consumption_audio.playing, "Accepted item starts sound playback")
			if kind == "food":
				check(pet.consumption_audio.stream in pet.eating_sounds, "Eating selects a Minecraft bite sound")
			else:
				check(pet.consumption_audio.stream == pet.drinking_sound, "Drinking selects the Minecraft sip sound")
			check(pet.consumption_audio.stream.get_length() > 0, "Sound file decodes successfully")
			pet.consumption_audio.stop()
			pet.consumption_audio.finished.emit()
			check(pet.consumption_audio.playing, "Finished clip restarts while consumption is active")
			check(pet.sprite.animation == ("eating" if kind == "food" else "drinking"), "Dedicated consumption animation plays")
			check(not pet._begin_consuming(kind), "Cannot consume two items at once")
			var still_position = pet.win_pos
			pet._physics_process(0.5)
			check(pet.win_pos == still_position, "Pet stays still while consuming")
			check((menu.hunger if kind == "food" else menu.thirst) == stat_before, "No refill before consumption finishes")
			pet._advance_consumption(pet.consume_seconds)
			check(pet.consuming_kind.is_empty(), "Consumption completes")
			check(not pet.consumption_audio.playing, "Consumption completion stops sound")
			pet.consumption_audio.finished.emit()
			check(not pet.consumption_audio.playing, "Late finished signal cannot restart sound after completion")
			pet.care_item.cancel()
	check(menu.hunger == 65 and menu.thirst == 75 and menu.happiness == 60, "Food and drink do not refill happiness")
	check(menu.bars["Hunger"].value == 65, "Displayed bar updates after feeding")
	menu.receive_pets(20.0)
	check(menu.values["Happiness"].text == "80 / 100", "Displayed number updates after petting")
	for i in range(10):
		pet._begin_consuming("food")
		pet._advance_consumption(pet.consume_seconds)
		pet._begin_consuming("drink")
		pet._advance_consumption(pet.consume_seconds)
		menu.receive_pets(20.0)
	check(menu.hunger == 100 and menu.thirst == 100 and menu.happiness == 100, "Repeated care caps all stats at 100")
	menu.hunger = 50
	menu.feed()
	check(menu.hunger == 50, "Offering food alone does not feed the pet")
	pet._on_item_dropped("food", Vector2i(-10000, -10000))
	check(pet.care_item.visible and menu.hunger == 50 and pet.consuming_kind.is_empty(), "Missed drop is retryable and does not feed")
	var item_escape = InputEventKey.new()
	item_escape.pressed = true
	item_escape.keycode = KEY_ESCAPE
	pet.care_item._on_input(item_escape)
	check(not pet.care_item.visible, "Escape cancels the item")
	menu._decay_stats(10.0)
	check(menu.hunger < 100 and menu.thirst < 100 and menu.happiness < 100, "Stats drain with menu closed")
	menu._decay_stats(100000.0)
	check(menu.hunger == 0 and menu.thirst == 0 and menu.happiness == 0, "Stats cannot drop below zero")
	menu.hunger = 100
	menu.thirst = 100
	menu.happiness = 100
	pet._update_vitality()

	pet.click_pending = true
	pet.press_position = Vector2(100, 100)
	pet._track_pointer(Vector2(102, 100))
	check(pet.click_pending and not pet.is_dragging, "Small pointer jitter remains a click")
	pet._finish_pointer()
	check(not menu.visible and not pet.click_pending and pet.click_squish.active, "Left click squishes instead of opening menu")
	check(pet.click_squish.player.playing and pet.sprite.scale.y < pet.click_squish.normal_scale.y, "Squish starts sound and compression together")
	check(pet.click_squish.profile.envelope.max() > 0.9, "Animation has a measured sound envelope")
	pet.click_squish.advance(2.0)
	check(not pet.click_squish.active and pet.sprite.scale == pet.click_squish.normal_scale, "Squish restores normal sprite scale")
	var right_click = InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	pet._on_area_input(null, right_click, 0)
	check(menu.visible and not pet.click_pending, "Right click opens care without starting a drag")
	pet.screen_size = Vector2(1000, 800)
	pet.window_size = Vector2(200, 200)
	pet.win_pos = Vector2(400, 600)
	pet.surface = pet.Surface.FLOOR
	pet.direction = Vector2.RIGHT
	var old_position = pet.win_pos
	pet._physics_process(1.0)
	check(pet.win_pos.x > old_position.x, "Pet continues walking while menu is open")
	var menu_position = menu.position
	pet._physics_process(0.1)
	check(menu.position == menu_position, "Menu remains stationary while pet moves")

	menu.happiness = 50.0
	pet.last_pet_mouse_position = Vector2.ZERO
	for i in range(5):
		pet._update_petting(0.05, Vector2.ZERO, true, false)
	check(not pet.is_petting and menu.happiness == 50, "Stationary hovering cannot earn happiness")
	pet._update_petting(0.05, Vector2(20, 0), true, false)
	check(not pet.is_petting, "One motion sample does not trigger petting")
	pet._update_petting(0.05, Vector2(0, 0), true, false)
	pet._update_petting(0.05, Vector2(20, 0), true, false)
	check(pet.is_petting and menu.happiness > 50, "Repeated strokes trigger petting and happiness")
	check(pet.sprite.animation == "petting", "Petting uses its dedicated animation")
	check(pet.sprite.sprite_frames.get_frame_count("petting") == 2, "Petting animation contains artwork")
	pet.mouse_over_pet = true
	pet.last_pet_mouse_position = Vector2(DisplayServer.mouse_get_position())
	old_position = pet.win_pos
	var happy_before = menu.happiness
	pet._physics_process(0.05)
	check(pet.win_pos == old_position, "Petting pauses movement")
	check(menu.happiness == happy_before, "Grace period does not award happiness without strokes")
	pet._physics_process(0.5)
	check(not pet.is_petting and pet.win_pos.x > old_position.x, "Walking resumes after petting stops")
	check(pet.sprite.animation == "walk_right", "Walking animation is restored")
	for i in range(3):
		pet._update_petting(0.05, Vector2(i * 30, 0), true, true)
	check(not pet.is_petting, "Holding a mouse button cannot pet")
	check(menu.happiness == happy_before, "Dragging cannot earn happiness")
	menu.hide()
	for i in range(3):
		pet._update_petting(0.05, Vector2(i * 30, 0), true, false)
	check(pet.is_petting and menu.happiness > happy_before, "Petting works with the menu closed")
	pet._update_petting(0.05, Vector2(100, 0), false, false)
	check(not pet.is_petting, "Leaving the pet ends petting")
	pet.mouse_over_pet = false
	menu.show()
	var escape = InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	menu._on_window_input(escape)
	check(not menu.visible, "Escape closes menu")
	pet.click_pending = true
	pet._track_pointer(Vector2(120, 100))
	check(pet.is_dragging and not pet.click_pending, "Moving beyond threshold starts dragging")
	pet._finish_pointer()
	check(not menu.visible and pet.surface == pet.Surface.FALLING, "Drag release falls without opening menu")
	menu.show()
	for button in buttons:
		if button.text == "Close menu":
			button.pressed.emit()
	check(not menu.visible, "Close button dismisses menu")
	# Feet should face the supporting edge, and the head should face travel.
	for example in [
		[pet.Surface.FLOOR, Vector2.RIGHT, Vector2.DOWN],
		[pet.Surface.FLOOR, Vector2.LEFT, Vector2.DOWN],
		[pet.Surface.LEFT_WALL, Vector2.UP, Vector2.LEFT],
		[pet.Surface.LEFT_WALL, Vector2.DOWN, Vector2.LEFT],
		[pet.Surface.RIGHT_WALL, Vector2.UP, Vector2.RIGHT],
		[pet.Surface.RIGHT_WALL, Vector2.DOWN, Vector2.RIGHT],
		[pet.Surface.CEILING, Vector2.LEFT, Vector2.UP],
		[pet.Surface.CEILING, Vector2.RIGHT, Vector2.UP],
	]:
		pet.surface = example[0]
		pet.direction = example[1]
		pet._update_animation() # Establish this surface's directional artwork first.
		pet.last_pet_mouse_position = Vector2.ZERO
		var original_rotation = pet.sprite.rotation
		var original_flip = pet.sprite.flip_h
		for i in range(1, 4):
			pet._update_petting(0.05, Vector2(i * 20, 0), true, false)
		check(pet.is_petting, "Petting starts on each surface")
		var feet = Vector2.DOWN.rotated(pet.sprite.rotation)
		var face = (Vector2.LEFT if pet.sprite.flip_h else Vector2.RIGHT).rotated(pet.sprite.rotation)
		check(feet.is_equal_approx(example[2]), "Petting feet face supporting edge")
		check(face.is_equal_approx(example[1]), "Petting faces travel direction")
		pet._update_petting(0.5, Vector2(60, 0), true, false)
		check(not pet.is_petting, "Petting ends on each surface")
		check(is_equal_approx(pet.sprite.rotation, original_rotation) and pet.sprite.flip_h == original_flip,
			"Normal sprite orientation is restored after petting")
		pet._begin_consuming("drink")
		check(Vector2.DOWN.rotated(pet.sprite.rotation).is_equal_approx(example[2]), "Consumption aligns to supporting edge")
		pet._advance_consumption(pet.consume_seconds)
		check(is_equal_approx(pet.sprite.rotation, original_rotation) and pet.sprite.flip_h == original_flip,
			"Orientation restores after consumption")
	# Allow container layout to settle and check that the controls fit the menu.
	await process_frame
	await process_frame
	var minimum = menu.get_child(0).get_combined_minimum_size()
	check(minimum.x <= menu.size.x and minimum.y <= menu.size.y, "All menu controls fit inside the window: %s within %s" % [minimum, menu.size])
	# Register the collision shape with physics, then check the actual drop target.
	await physics_frame
	await process_frame
	var shape_center = pet.get_node("Area2D/CollisionShape2D").global_position
	check(pet._item_hits_scene_point(shape_center), "Drop target accepts the pet's collision shape")
	check(not pet._item_hits_scene_point(Vector2(-10000, -10000)), "Drop target rejects points away from the pet")
	menu.feed()
	var item_press = InputEventMouseButton.new()
	item_press.button_index = MOUSE_BUTTON_LEFT
	item_press.pressed = true
	pet.care_item._on_input(item_press)
	check(pet.care_item.dragging, "Clicking the item starts dragging it")
	pet.care_item.cancel()
	check(not pet.care_item.dragging and not pet.care_item.visible, "Cancel clears the item drag")
	pet.free()
	if failures == 0:
		print("PASS: care, menu movement, petting gesture/reward/animation, movement resume, dragging, and dismissal")
	quit(1 if failures else 0)

