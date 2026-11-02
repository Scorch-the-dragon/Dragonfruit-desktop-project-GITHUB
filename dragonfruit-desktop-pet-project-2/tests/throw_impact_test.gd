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
	pet.idle_chance = 0.0
	check(pet.impact_sounds.size() == 6, "All six impact sounds are loaded")
	for sound in pet.impact_sounds:
		check(sound != null and sound.get_length() > 0, "Impact sound decodes")
	for hit in [[Vector2(799, 300), Vector2(500, 0)], [Vector2(1, 300), Vector2(-500, 0)], [Vector2(400, 1), Vector2(0, -500)], [Vector2(400, 599), Vector2(0, 500)]]:
		pet.surface = pet.Surface.FALLING
		pet.win_pos = hit[0]
		pet.horizontal_fall_speed = hit[1].x
		pet.fall_speed = hit[1].y
		pet.throw_in_progress = true
		pet.impact_audio.stop()
		pet._advance_motion(0.02, Vector2(800, 600))
		check(pet.impact_audio.playing and pet.impact_audio.stream in pet.impact_sounds, "Thrown pet plays a supplied sound on screen impact")
		pet.impact_audio.stop()
		pet._advance_motion(0.02, Vector2(800, 600))
		check(not pet.impact_audio.playing, "Impact does not repeat after leaving the edge or landing")
	check(not pet.throw_in_progress, "Floor landing ends the throw")
	check(pet.sprite.animation == "splat" and pet.landing_splat_remaining > 0, "Thrown floor landing enters splat pause")
	var landed_position = pet.win_pos
	pet._physics_process(0.2)
	check(pet.win_pos == landed_position and pet.sprite.animation == "splat", "Pet stays still in splat pose")
	check(not pet.events.can_start(), "Events wait for landing pause")
	pet._physics_process(pet.landing_splat_seconds)
	check(pet.landing_splat_remaining == 0 and pet.sprite.animation != "splat", "Landing pause ends and restores normal animation")
	pet.surface = pet.Surface.FALLING
	pet.win_pos = Vector2(400, 599)
	pet.fall_speed = 500
	pet.throw_in_progress = false
	pet._advance_motion(0.02, Vector2(800, 600))
	check(not pet.impact_audio.playing, "Ordinary gravity landing stays silent")
	pet.free()
	if failures == 0:
		print("PASS: six impact clips, all four edges, no repeated contact sound, quiet ordinary falls")
	quit(1 if failures else 0)
