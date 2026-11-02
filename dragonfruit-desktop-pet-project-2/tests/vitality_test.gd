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
	pet.care_menu.care_enabled = true
	pet.events.random_events_enabled = false
	pet.screen_origin = Vector2.ZERO
	pet.screen_size = Vector2(1000,800)
	pet.window_size = Vector2(200,200)
	pet.surface = pet.Surface.FLOOR
	pet.direction = Vector2.RIGHT
	pet.win_pos = Vector2(200,600)
	var menu = pet.care_menu
	menu.hunger = 50
	menu.thirst = 50
	menu.happiness = 50
	pet._physics_process(0.1)
	check(is_equal_approx(pet.win_pos.x, 205) and pet.sprite.speed_scale == 0.5, "Half stats give half movement and animation speed")
	menu.hunger = 0
	menu.thirst = 100
	menu.happiness = 50
	pet._update_vitality()
	check(pet.stat_material.get_shader_parameter("care_color") == Vector3(0,0.5,1), "Stats independently drive red, green, blue color")
	pet.props.apply_paint("green_paint")
	var paint = pet.sprite.self_modulate
	menu.hunger = 0
	menu.thirst = 0
	menu.happiness = 0
	var before = pet.win_pos
	pet._physics_process(1.0)
	check(pet.win_pos == before and pet.vitality == 0 and pet.sprite.speed_scale == 0, "Zero stats stop movement and sprite playback")
	check(pet.stat_material.get_shader_parameter("care_color") == Vector3.ZERO and pet.sprite.self_modulate == paint, "Grayscale does not erase the underlying applied paint")
	check(not pet.events.can_start(), "Exhausted pet cannot start events")
	check(pet._begin_consuming("food"), "Exhausted pet still accepts food")
	pet._physics_process(pet.consume_seconds)
	pet._update_vitality()
	check(menu.hunger > 0 and pet.vitality > 0, "Feeding revives the pet")
	menu.care_enabled = false
	pet._update_vitality()
	check(pet.vitality == 1 and pet.stat_material.get_shader_parameter("care_color") == Vector3.ONE, "Care-disabled mode restores full movement and color")
	pet.free()
	if failures == 0: print("PASS: stat speed, individual colors, exhaustion, paint preservation, revival, and care-disabled mode")
	quit(1 if failures else 0)
