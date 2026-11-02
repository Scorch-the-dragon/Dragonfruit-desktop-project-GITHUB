extends SceneTree
var failures = 0
func check(ok, message):
	if not ok:
		failures += 1
		push_error(message)
func _initialize():
	call_deferred("run_checks")
func run_checks():
	var pet = load("res://Main.tscn").instantiate()
	root.add_child(pet)
	pet.set_physics_process(false)
	pet.care_menu.set_process(false)
	var events = pet.events
	events.random_events_enabled = true
	events.disabled_events.clear()
	check(events.landing_explosion_chance() == 0, "No throws means no landing explosion chance")
	events.record_throw()
	check(is_equal_approx(events.landing_explosion_chance(), 0.1), "First throw gives 10 percent chance")
	events.record_throw()
	check(is_equal_approx(events.landing_explosion_chance(), 0.2), "Next throw increases chance")
	for i in range(20): events.record_throw()
	check(events.landing_explosion_chance() == 0.75, "Chance has a cap")
	events.explosion_chance_per_throw = 1.0
	events.maximum_landing_explosion_chance = 1.0
	pet.surface = pet.Surface.FLOOR
	events.disabled_events.append("blow_up")
	check(not events.try_landing_explosion(), "Disabled explosion blocks throw-triggered explosions")
	events.disabled_events.clear()
	events.random_events_enabled = false
	check(not events.try_landing_explosion(), "Automatic event setting is respected")
	events.random_events_enabled = true
	pet.screen_size = Vector2(1000,800)
	pet.window_size = Vector2(200,200)
	pet.win_pos = Vector2(400,599)
	pet.surface = pet.Surface.FALLING
	pet.throw_in_progress = true
	pet.fall_speed = 500
	pet._advance_motion(0.02, Vector2(800,600))
	check(events.active_id == "blow_up" and events.burst.visible, "Thrown landing triggers explosion before splat")
	check(events.throws_since_explosion == 0 and not pet.throw_in_progress, "Explosion resets chance and ends throw")
	check(events.explosion_audio.playing and events.explosion_audio.stream.get_length() > 0, "Explosion sound loads and plays")
	check(events.burst.sheet.resource_path == "res://Sprites/explosion-deltarune-sheet.png" and events.burst.duration == 1.7, "Deltarune GIF animation is loaded at original timing")
	for i in range(300): events.advance(1.0 / 60.0)
	check(pet.sprite.visible and events.active_id.is_empty(), "Explosion still returns the pet")
	pet.free()
	if failures == 0: print("PASS: escalating probability, cap, options, actual landing, reset, assets, and return")
	quit(1 if failures else 0)
