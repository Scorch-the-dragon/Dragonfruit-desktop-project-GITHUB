extends SceneTree

var failures = 0


func check(condition, description):
	if not condition:
		failures += 1
		push_error(description)


func _init():
	call_deferred("run_checks")


func run_checks():
	var path = "res://.godot/options-test-" + str(Time.get_ticks_usec()) + ".cfg"
	var pet = load("res://Main.tscn").instantiate()
	pet.preferences.path = path
	root.add_child(pet)
	pet.set_physics_process(false)
	pet.care_menu.set_process(false)
	pet.screen_size = Vector2(1000, 800)
	pet.window_size = Vector2(200, 200)
	pet.surface = pet.Surface.FLOOR
	var menu = pet.care_menu
	var events = pet.events
	var master = AudioServer.get_bus_index("Master")
	check(menu.volume_slider.value == 100 and menu.care_toggle.button_pressed, "Fresh preferences default to full volume and care enabled")
	for button in menu.find_children("*", "Button", true, false):
		if button.text == "Options":
			button.pressed.emit()
	check(menu.options_view.visible and not menu.care_view.visible, "Options button opens its page")
	menu.care_toggle.button_pressed = false
	check(menu.hunger == 100 and menu.thirst == 100 and menu.happiness == 100, "Disabling care immediately fills all stats")
	menu._decay_stats(10000)
	check(menu.hunger == 100 and menu.thirst == 100 and menu.happiness == 100, "Care disabled prevents stat decay")
	menu.care_toggle.button_pressed = true
	menu._decay_stats(10)
	check(menu.hunger < 100 and menu.thirst < 100 and menu.happiness < 100, "Re-enabling care resumes decay")
	menu.random_toggle.button_pressed = false
	events.wait_remaining = 0.0
	events.event_chance = 1.0
	events.advance(1)
	check(events.active_id.is_empty(), "Random-events toggle stops automatic triggers")
	check(events.trigger("blow_up"), "Turning off randomness still allows manual events")
	menu.event_toggles["blow_up"].button_pressed = false
	check(events.active_id == "blow_up", "Disabling a running event allows it to finish safely")
	for i in range(240):
		if not events.active_id.is_empty():
			events.advance(1.0 / 60.0)
	pet.surface = pet.Surface.FLOOR
	check(not events.trigger("blow_up") and menu.event_buttons["blow_up"].disabled, "Disabled event cannot be manually triggered")
	menu.event_toggles["bring_note"].button_pressed = false
	menu.event_toggles["bring_image"].button_pressed = false
	menu.event_toggles["mouse_pounce"].button_pressed = false
	menu.event_toggles["hop_window"].button_pressed = false
	menu.random_toggle.button_pressed = true
	events.wait_remaining = 0.0
	events.advance(1.0)
	check(events.active_id.is_empty(), "Disabling every event leaves the random picker safely empty")
	menu.event_toggles["blow_up"].button_pressed = true
	events.wait_remaining = 0.0
	events.advance(0.1)
	check(events.active_id == "blow_up", "Random picker chooses only an enabled event")
	for i in range(240):
		if not events.active_id.is_empty():
			events.advance(1.0 / 60.0)
	pet.surface = pet.Surface.FLOOR
	pet._begin_consuming("food")
	menu.volume_slider.value = 40
	check(pet.consumption_audio.playing and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(master)), 0.4), "Slider affects the master bus during playback")
	menu.volume_slider.value = 0
	check(AudioServer.is_bus_mute(master) and menu.volume_label.text == "Volume: 0%", "Zero percent mutes all audio")
	menu.volume_slider.value = 100
	check(not AudioServer.is_bus_mute(master) and is_zero_approx(AudioServer.get_bus_volume_db(master)), "100 percent restores master volume")
	menu.volume_slider.value = 37
	menu.care_toggle.button_pressed = false
	menu.random_toggle.button_pressed = false
	var restored = preload("res://Code/PetPreferences.gd").new()
	restored.path = path
	restored.load_preferences()
	check(restored.volume_percent == 37 and not restored.care_enabled and not restored.random_events_enabled,
		"Volume and general toggles persist to disk")
	check(restored.disabled_events == ["bring_note", "bring_image", "mouse_pounce", "hop_window"], "Per-event choices persist by event ID")
	var replacement = load("res://Main.tscn").instantiate()
	replacement.preferences.path = path
	root.add_child(replacement)
	replacement.set_physics_process(false)
	replacement.care_menu.set_process(false)
	check(replacement.care_menu.volume_slider.value == 37 and replacement.events.disabled_events.has("bring_note")
		and not replacement.care_menu.care_enabled, "New pet instance applies saved preferences and updates controls")
	await process_frame
	await process_frame
	var minimum = menu.get_child(0).get_combined_minimum_size()
	check(minimum.x <= menu.size.x and minimum.y <= menu.size.y, "Options layout fits the menu window")
	replacement.free()
	pet.free()
	DirAccess.remove_absolute(path)
	AudioServer.set_bus_mute(master, false)
	AudioServer.set_bus_volume_db(master, 0)
	if failures == 0:
		print("PASS: options navigation, care toggles, event filtering, active-event safety, live volume, and saved preferences")
	quit(1 if failures else 0)


