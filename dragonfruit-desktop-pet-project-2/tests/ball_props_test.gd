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
	pet.props.set_physics_process(false)
	pet.screen_origin = Vector2(1000, 0)
	pet.screen_size = Vector2(1000, 800)
	pet.window_size = Vector2(200, 200)
	pet.win_pos = Vector2(100, 600)
	pet.surface = pet.Surface.FLOOR
	for button in pet.care_menu.find_children("*", "Button", true, false):
		if button.text == "Spawn ball":
			button.pressed.emit()
	check(pet.props.balls.size() == 1, "Menu spawns a ball")
	var ball = pet.props.balls[0]
	ball.set_physics_process(false)
	check(ball.visible and ball.picture.texture != null, "Ball uses supplied artwork in a visible window")
	# Physics fixtures use a synthetic monitor, independent of the menu monitor.
	ball.screen_rect = Rect2(pet.screen_origin, pet.screen_size)
	ball.ball_position = Vector2(1400, 200)
	ball.velocity = Vector2(300, 0)
	ball.advance_motion(0.1)
	check(ball.ball_position.x > 1400 and ball.ball_position.y > 200, "Ball flies sideways and falls under gravity")
	ball.ball_position = Vector2(1935, 400)
	ball.velocity = Vector2(900, 0)
	ball.advance_motion(0.1)
	check(ball.velocity.x < 0 and ball.ball_position.x <= 1936, "Fast ball bounces off side")
	ball.ball_position = Vector2(1400, 735)
	ball.velocity = Vector2(150, 800)
	ball.advance_motion(0.02)
	check(ball.velocity.y < 0, "Ball bounces off floor")
	for i in range(1800):
		ball.advance_motion(1.0 / 60.0)
	check(ball.velocity == Vector2.ZERO, "Unattended ball eventually settles")
	ball._sample(Vector2.ZERO, 10.0)
	ball._sample(Vector2(60, -60), 10.1)
	check(ball.throw_velocity().is_equal_approx(Vector2(600, -600)), "Mouse flick produces throw momentum")
	ball._sample(Vector2(60, -60), 10.5)
	check(ball.throw_velocity() == Vector2.ZERO, "Holding still discards stale throw momentum")
	ball.ball_position = Vector2(1700, 736)
	ball.dragging = true
	var before = pet.win_pos
	check(not pet.props.advance_play(0.1) and pet.win_pos == before, "Held ball is ignored")
	ball.dragging = false
	check(pet.props.advance_play(0.1) and pet.win_pos.x > before.x, "Pet chases a released ball")
	ball.ball_position = pet.screen_origin + pet.win_pos + Vector2(120, 136)
	ball.velocity = Vector2.ZERO
	pet.props.advance_play(0.1)
	check(ball.velocity.length() > 0 and ball.velocity.y < 0, "Pet knocks a nearby stationary ball")
	for i in range(8):
		var extra = pet.props.spawn_prop()
		if extra != null:
			extra.set_physics_process(false)
	check(pet.props.balls.size() == 5, "Prop count is bounded")
	for button in pet.care_menu.find_children("*", "Button", true, false):
		if button.text == "Remove all props":
			button.pressed.emit()
	await process_frame
	check(pet.props.balls.is_empty() and not is_instance_valid(ball), "Remove balls frees spawned windows")
	var menu = pet.care_menu
	for button in menu.find_children("*", "Button", true, false):
		if button.text == "Spawn menu":
			button.pressed.emit()
	check(menu.spawn_view.visible and not menu.care_view.visible, "Spawn button opens a dedicated page")
	var original_color = pet.sprite.self_modulate
	for kind in ["green_paint", "paint_remover"]:
		var label = "Green paint" if kind == "green_paint" else "Paint remover"
		for button in menu.find_children("*", "Button", true, false):
			if button.text == label:
				button.pressed.emit()
		var prop = pet.props.paint_props.back()
		prop.set_physics_process(false)
		prop.ball_position = pet.screen_origin + Vector2(800, 100)
		pet.props.check_paint_contacts()
		check(not prop.is_queued_for_deletion(), "Distant paint does not activate")
		prop.ball_position = pet.screen_origin + pet.win_pos + Vector2(90, 90)
		pet.props.check_paint_contacts()
		check(prop.is_queued_for_deletion() and not prop.visible, "Touching paint consumes the prop")
		if kind == "green_paint":
			check(pet.sprite.self_modulate.g > pet.sprite.self_modulate.r, "Green paint tints pet green")
			pet._update_animation()
			check(pet.sprite.self_modulate != original_color, "Paint survives animation changes")
		else:
			check(pet.sprite.self_modulate == original_color, "Remover restores original appearance")
		await process_frame
		check(not is_instance_valid(prop), "Consumed paint window is freed")
	menu._show_care()
	check(not menu.spawn_view.visible and menu.care_view.visible, "Back returns to care")
	pet.props.spawn_prop("green_paint")
	pet.props.spawn_prop("paint_remover")
	pet.props.remove_props()
	check(pet.props.paint_props.is_empty(), "Remove all includes paint props")
	await process_frame
	pet.free()
	# (The next scene is isolated so previous toy play cannot affect impact tests.)
	pet = load("res://Main.tscn").instantiate()
	root.add_child(pet)
	pet.set_physics_process(false)
	pet.props.set_physics_process(false)
	pet.surface = pet.Surface.FLOOR
	var anvil = pet.props.spawn_prop("anvil")
	pet.screen_origin = Vector2.ZERO
	pet.screen_size = Vector2(1000, 800)
	pet.window_size = Vector2(200, 200)
	pet.win_pos = Vector2(300, 600)
	pet._update_animation()
	anvil.set_physics_process(false)
	anvil.screen_rect = Rect2(Vector2.ZERO, Vector2(1000, 800))
	anvil.ball_position = Vector2(800, 730)
	anvil.velocity = Vector2(0, 500)
	anvil.advance_motion(0.05)
	check(anvil.landing_audio.stream != null and anvil.landing_audio.playing, "Anvil landing plays its sound")
	anvil.landing_audio.stop()
	anvil.advance_motion(0.1)
	check(not anvil.landing_audio.playing, "Resting anvil does not repeat its landing sound")
	anvil.ball_position.y = 700
	anvil.velocity = Vector2(0, 500)
	anvil.advance_motion(0.1)
	check(anvil.landing_audio.playing, "Dropping anvil again plays another landing sound")
	var body = pet.props.pet_artwork_bounds()
	var before_hit = Vector2(body.position.x, body.position.y - anvil.size.y - 100)
	anvil.ball_position = before_hit + Vector2(0, 200)
	anvil.dragging = true
	pet.props.check_anvil_hit(anvil, before_hit)
	check(not pet.props.is_squashed(), "Held anvil does not flatten pet")
	anvil.dragging = false
	pet.props.check_anvil_hit(anvil, before_hit + Vector2(1000, 0))
	check(not pet.props.is_squashed(), "Sideways miss does not flatten pet")
	check(not pet.props.hit_audio.playing, "Held anvil and misses do not squeak")
	var normal_scale = pet.sprite.scale
	var normal_position = pet.sprite.position
	pet.direction = Vector2.LEFT
	pet.props.check_anvil_hit(anvil, before_hit)
	check(pet.sprite.flip_h, "Flattened pet faces its leftward travel direction")
	check(pet.props.is_squashed() and pet.sprite.scale.y < normal_scale.y, "Fast descending anvil flattens pet")
	check(not pet.events.can_start(), "Events wait for squash recovery")
	check(pet.props.hit_audio.playing, "Anvil hit immediately plays a forward squeak")
	var chosen_squeak = pet.props.hit_audio.stream.resource_path.get_file().trim_suffix("-made-with-Voicemod.mp3")
	check(pet.props.recovery_audio.stream.resource_path.get_file() == chosen_squeak + "-reversed.wav", "Recovery uses the same squeak in reverse")
	pet.props.hit_audio.stop()
	pet.props.check_anvil_hit(anvil, before_hit)
	check(not pet.props.hit_audio.playing, "Already flattened pet does not repeat the hit squeak")
	check(not pet.props.recovery_audio.playing, "Reverse squeak waits until unflattening")
	pet.props.advance_squash(2.4)
	check(pet.props.is_squashed(), "Pet stays flattened for a few seconds")
	check(not pet.props.recovery_audio.playing, "No recovery sound during flattened hold")
	pet.props.advance_squash(0.11)
	check(pet.props.recovery_audio.playing, "Unflattening starts a reversed squeak")
	check(pet.props.recovery_audio.stream.resource_path.get_file() == chosen_squeak + "-reversed.wav", "Unflattening preserves the squeak chosen on impact")
	for sound in pet.props.RECOVERY_SOUNDS:
		var profile = pet.props.RECOVERY_PROFILES[sound.resource_path.get_file()]
		check(absf(sound.get_length() - profile.length) < 0.001, "Bounce profile matches sound duration")
		pet.props.recovery_profile = profile
		pet.props.recover_seconds = profile.length + 0.3
		check(pet.props._recovery_shape(0.0).is_equal_approx(Vector2(1.25, 0.18)), "Recovery begins flattened")
		var tallest = 0.0
		for i in range(101):
			tallest = maxf(tallest, pet.props._recovery_shape(pet.props.recover_seconds * i / 100.0).y)
		check(tallest > 1.0, "Each reversed squeak has a springy overshoot")
		check(pet.props._recovery_shape(pet.props.recover_seconds) == Vector2.ONE, "Each recovery settles exactly to normal")
	# Manually advance the settling tail without depending on real-time audio.
	pet.props.recovery_audio.stop()
	pet.props.advance_squash(pet.props.recover_seconds * 0.25)
	check(pet.sprite.scale.y > normal_scale.y, "Recovery springs past normal height")
	check(pet.sprite.flip_h, "Bouncy recovery preserves flattening direction")
	pet.props.remove_props()
	pet.props.advance_squash(1.0)
	check(not pet.props.is_squashed() and pet.sprite.scale == normal_scale and pet.sprite.position == normal_position, "Recovery restores original transform even if anvil is removed")
	await process_frame
	check(not is_instance_valid(anvil), "Remove all props includes anvils")
	pet.free()
	if failures == 0:
		print("PASS: prop menu, gravity, bounces, settling, throw sampling, chase, kicks, and cleanup")
	quit(1 if failures else 0)

