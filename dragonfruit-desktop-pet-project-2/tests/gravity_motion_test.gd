extends SceneTree

const Pet = preload("res://Code/Main.gd")
var failures = 0


func check(condition, description):
	if not condition:
		failures += 1
		push_error(description)


func _init():
	var pet = load("res://Main.tscn").instantiate()
	# Keep the scene outside the tree to avoid moving the real desktop window.
	pet.sprite = pet.get_node("AnimatedSprite2D")
	pet.idle_chance = 0.0
	var limits = Vector2(800, 600)
	pet.win_pos = Vector2(400, 100)
	pet._advance_motion(0.1, limits)
	check(pet.win_pos.y > 100 and pet.win_pos.x == 400, "Free pet falls straight down")
	var first_speed = pet.fall_speed
	pet._advance_motion(0.1, limits)
	check(pet.fall_speed > first_speed, "Gravity accelerates the fall")
	pet.max_fall_speed = 200.0
	pet._advance_motion(0.1, limits)
	check(pet.fall_speed <= 200.0, "Fall speed is capped")
	pet._advance_motion(10.0, limits)
	check(pet.surface == Pet.Surface.FLOOR and pet.win_pos.y == 600, "Fall lands without overshooting")
	check(pet.fall_speed == 0.0, "Landing clears downward speed")

	# Walk a full circuit in each direction, checking every corner and animation.
	for heading in [Vector2.RIGHT, Vector2.LEFT]:
		pet.surface = Pet.Surface.FLOOR
		pet.direction = heading
		pet.win_pos = Vector2(400, 600)
		var first_wall = Pet.Surface.RIGHT_WALL if heading.x > 0 else Pet.Surface.LEFT_WALL
		var last_wall = Pet.Surface.LEFT_WALL if heading.x > 0 else Pet.Surface.RIGHT_WALL
		pet._advance_motion(5.0, limits)
		check(pet.surface == first_wall and pet.direction == Vector2.UP, "Floor turns up a wall")
		pet._update_animation()
		check(pet.sprite.animation == ("crawl_right_up" if heading.x > 0 else "crawl_left_up"), "Corner uses wall animation")
		pet._advance_motion(1.0, limits)
		check(pet.win_pos.y == 500, "Wall climbing holds position against gravity")
		pet._advance_motion(5.0, limits)
		check(pet.surface == Pet.Surface.CEILING and pet.direction == -heading, "Wall turns onto ceiling")
		pet._advance_motion(1.0, limits)
		check(pet.win_pos.y == 0, "Ceiling crawling stays attached")
		pet._advance_motion(7.0, limits)
		check(pet.surface == last_wall and pet.direction == Vector2.DOWN, "Ceiling turns down opposite wall")
		pet._advance_motion(6.0, limits)
		check(pet.surface == Pet.Surface.FLOOR and pet.direction == heading, "Wall returns to floor")

	pet.surface = Pet.Surface.FLOOR
	pet.win_pos = Vector2(400, 600)
	pet.direction = Vector2.RIGHT
	pet.speed = 0.5
	pet._advance_motion(0.1, limits)
	check(pet.win_pos.x > 400, "Subpixel movement is preserved")
	pet.idle_chance = 1.0
	pet.surface = Pet.Surface.FALLING
	pet.is_idling = false
	pet._maybe_idle()
	check(not pet.is_idling, "Pet cannot rest in midair")
	pet.surface = Pet.Surface.FLOOR
	pet._maybe_idle()
	check(pet.is_idling and pet.idle_timer >= pet.idle_min_seconds, "Floor resting still works")
	# Throw sampling uses elapsed seconds, including at large system uptime values.
	pet.drag_samples.clear()
	pet._record_drag_sample(Vector2(100, 200), 300000.0)
	pet._record_drag_sample(Vector2(140, 140), 300000.1)
	var launch = pet._get_throw_velocity()
	check(launch.is_equal_approx(Vector2(400, -600)), "Flick captures horizontal and upward velocity")
	pet._record_drag_sample(Vector2(140, 140), 300000.3)
	check(pet._get_throw_velocity() == Vector2.ZERO, "Pausing before release discards stale flick velocity")
	pet.drag_samples.clear()
	pet._record_drag_sample(Vector2.ZERO, 0.0)
	pet._record_drag_sample(Vector2(10000, -10000), 0.01)
	check(pet._get_throw_velocity().length() <= pet.max_throw_speed + 0.01, "Extreme throws are capped")
	pet.surface = Pet.Surface.FALLING
	pet.is_idling = false
	pet.win_pos = Vector2(300, 300)
	pet.horizontal_fall_speed = launch.x
	pet.fall_speed = launch.y
	pet.max_fall_speed = 1000.0
	pet.idle_chance = 0.0
	pet._advance_motion(0.1, limits)
	check(pet.win_pos.x > 300 and pet.win_pos.y < 300, "Upward flick launches sideways and up")
	for i in range(120):
		pet._advance_motion(1.0 / 60.0, limits)
	check(pet.surface == Pet.Surface.FLOOR, "Thrown pet eventually lands")
	check(pet.horizontal_fall_speed == 0 and pet.fall_speed == 0, "Landing clears throw momentum")
	pet.surface = Pet.Surface.FALLING
	pet.win_pos = Vector2(799, 300)
	pet.horizontal_fall_speed = 500
	pet._advance_motion(0.1, limits)
	check(pet.win_pos.x == 800 and pet.horizontal_fall_speed < 0, "Side wall keeps a throw onscreen and bounces it")
	pet._update_animation()
	check(pet.sprite.animation == "fall" and pet.sprite.flip_h, "Leftward bounce turns falling artwork left")
	pet.horizontal_fall_speed = 100
	pet._update_animation()
	check(not pet.sprite.flip_h, "Rightward fall faces right")
	pet.surface = Pet.Surface.FLOOR
	pet.direction = Vector2.LEFT
	pet._update_animation()
	check(not pet.sprite.flip_h and pet.sprite.animation == "walk_left", "Directional walking artwork is not mirrored twice")
	pet.surface = Pet.Surface.FALLING
	pet.horizontal_fall_speed = 0
	pet._update_animation()
	check(pet.sprite.flip_h, "Straight drop keeps previous leftward facing")
	pet.win_pos = Vector2(400, 1)
	pet.fall_speed = -500
	pet._advance_motion(0.01, limits)
	check(pet.win_pos.y == 0 and pet.fall_speed == 0, "Ceiling collision stops upward flight")
	for i in range(5):
		pet._update_petting(0.05, Vector2(i * 30, 0), true, false)
	check(not pet.is_petting and pet.petting_samples == 0, "Moving over airborne pet cannot interrupt falling")
	pet.free()
	if failures == 0:
		print("PASS: gravity, landing, both edge circuits, animations, subpixel movement, and floor rests")
	quit(1 if failures else 0)
