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
	pet.screen_origin = Vector2.ZERO
	pet.screen_size = Vector2(1000, 800)
	pet.window_size = Vector2(200, 200)
	var portals = pet.portals
	check(not portals.try_travel(pet.win_pos, true) and not portals.enter_audio.playing and not portals.exit_audio.playing, "Unpaired portals do not play travel sounds")
	for sound in portals.enter_sounds + portals.exit_sounds:
		check(sound != null and sound.get_length() > 0, "Portal travel clip loads and decodes")
	var screen = Rect2(Vector2.ZERO, pet.screen_size)
	var centers = {"left": Vector2(0,400), "right": Vector2(1000,400), "top": Vector2(500,0), "bottom": Vector2(500,800)}
	for entry in centers:
		for destination in centers:
			portals.place_portal("blue", entry, centers[entry], screen)
			portals.place_portal("orange", destination, centers[destination], screen)
			for color in ["blue", "orange"]:
				var player = portals.placement_audio[color]
				check(player.playing and player.stream.resource_path == "res://Audio/%s-portal-placed-made-with-Voicemod.mp3" % color, "Placement uses the matching color sound")
			portals.cooldown = 0
			var normal = portals.NORMALS[entry]
			var tangent = Vector2(-normal.y, normal.x)
			var velocity = -normal * 600 + tangent * 120
			pet.surface = pet.Surface.FALLING
			pet.throw_in_progress = true
			pet.win_pos = (centers[entry] - Vector2(100,100)).clamp(Vector2.ZERO, Vector2(800,600)) - normal * 2
			pet.horizontal_fall_speed = velocity.x
			pet.fall_speed = velocity.y
			var previous = pet.win_pos + normal * 10
			check(portals.try_travel(previous, true), "Travel between " + entry + " and " + destination)
			check(portals.enter_audio.playing and portals.enter_audio.stream in portals.enter_sounds, "Successful entry plays an enter sound")
			check(portals.exit_audio.playing and portals.exit_audio.stream in portals.exit_sounds, "Successful exit plays an exit sound")
			var result = Vector2(pet.horizontal_fall_speed, pet.fall_speed)
			check(is_equal_approx(result.length(), velocity.length()) and result.dot(portals.NORMALS[destination]) > 0, "Speed preserved and exit points inward")
			portals.enter_audio.stop()
			portals.exit_audio.stop()
			check(not portals.try_travel(previous, true), "Exit cannot immediately teleport back")
			check(not portals.enter_audio.playing and not portals.exit_audio.playing, "Cooldown blocks repeated travel sounds")
	portals.place_portal("blue", "bottom", centers.bottom, screen)
	portals.place_portal("orange", "top", centers.top, screen)
	portals.cooldown = 0
	pet.win_pos = Vector2(400,599)
	pet.horizontal_fall_speed = 0
	pet.fall_speed = 600
	pet.throw_in_progress = true
	pet.impact_audio.stop()
	pet._advance_motion(0.02, Vector2(800,600))
	check(pet.win_pos.y < 10 and pet.surface == pet.Surface.FALLING and pet.throw_in_progress, "Actual falling motion goes through paired portals")
	check(not pet.impact_audio.playing and pet.landing_splat_remaining == 0, "Portal passage skips impact sound and landing splat")
	pet.surface = pet.Surface.FLOOR
	pet.throw_in_progress = false
	pet.direction = Vector2.RIGHT
	pet.win_pos = Vector2(305,600)
	portals.cooldown = 0
	pet._advance_motion(0.1, Vector2(800,600))
	check(pet.surface == pet.Surface.CEILING, "Walking pet travels to ceiling portal")
	portals.clear_portals()
	var ball = pet.props.spawn_prop("blue_portal")
	ball.set_physics_process(false)
	ball.screen_rect = screen
	ball.ball_position = Vector2(400,735)
	ball.velocity = Vector2(0,200)
	ball.advance_motion(0.02)
	check(portals.endpoints.is_empty(), "Freshly spawned ball does not place a portal until released")
	ball.armed = true
	ball.ball_position = Vector2(400,735)
	ball.velocity = Vector2(0,200)
	ball.advance_motion(0.02)
	check(portals.endpoints.has("blue") and ball.is_queued_for_deletion(), "Released ball places portal and disappears")
	pet.props.remove_props()
	check(portals.endpoints.is_empty(), "Remove all props also clears portals")
	# Slow walkers remain inside an opening longer than the old 0.35s timer.
	pet.speed = 20.0
	pet.idle_chance = 0.0
	var surfaces = {"bottom": pet.Surface.FLOOR, "left": pet.Surface.LEFT_WALL, "right": pet.Surface.RIGHT_WALL}
	for pair in [["bottom", "left"], ["bottom", "right"], ["left", "bottom"], ["right", "bottom"]]:
		portals.clear_portals()
		portals.place_portal("blue", pair[0], centers[pair[0]], screen)
		portals.place_portal("orange", pair[1], centers[pair[1]], screen)
		var normal = portals.NORMALS[pair[0]]
		var tangent = Vector2(-normal.y, normal.x)
		pet.surface = surfaces[pair[0]]
		pet.direction = tangent
		pet.throw_in_progress = false
		pet.win_pos = (centers[pair[0]] - Vector2(100,100)).clamp(Vector2.ZERO, Vector2(800,600)) - tangent * 100
		pet._advance_motion(0.6, Vector2(800,600))
		check(pet.surface == surfaces[pair[1]], "Walker enters paired portal")
		portals.enter_audio.stop()
		portals.exit_audio.stop()
		for i in range(360):
			pet._advance_motion(0.02, Vector2(800,600))
			check(pet.surface == surfaces[pair[1]], "Slow walker escapes exit without teleport loop")
		check(not portals.enter_audio.playing and not portals.exit_audio.playing, "Walking out does not replay portal sounds")
		pet.direction *= -1
		for i in range(360):
			pet._advance_motion(0.02, Vector2(800,600))
			if pet.surface == surfaces[pair[0]]:
				break
		check(pet.surface == surfaces[pair[0]], "Portal works again after leaving and walking back")
	portals.clear_portals()
	await process_frame
	pet.free()
	if failures == 0: print("PASS: 16 edge pairs, momentum, quiet traversal, walking, portal balls, cleanup")
	quit(1 if failures else 0)
