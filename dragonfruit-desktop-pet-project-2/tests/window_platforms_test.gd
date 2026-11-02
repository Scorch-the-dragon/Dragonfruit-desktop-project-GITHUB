extends SceneTree

var failures = 0

func check(ok, message):
	if not ok:
		failures += 1
		push_error(message)

func _initialize():
	var pet = load("res://Main.tscn").instantiate()
	pet.sprite = pet.get_node("AnimatedSprite2D")
	pet.screen_size = Vector2(1200, 900)
	pet.window_size = Vector2(200, 200)
	pet.screen_origin = Vector2(1200, 0)
	var platforms = preload("res://Code/WindowPlatforms.gd").new()
	pet.add_child(platforms)
	platforms.pet = pet
	pet.window_platforms = platforms
	var window = {"id": "one", "x": 1400, "y": 450, "w": 600, "h": 400}
	platforms.set_windows([window])
	check(platforms.platforms.size() == 1 and platforms.platforms[0].y == 250, "Window top uses monitor-relative coordinates and full pet clearance")
	pet.win_pos = Vector2(300, 100)
	pet.fall_speed = 700
	pet._advance_motion(0.3, Vector2(1000, 700))
	check(pet.surface == pet.Surface.WINDOW_TOP and pet.win_pos.y == 250, "Fast fall lands on window instead of passing through")
	window.x += 50
	window.y += 20
	platforms.set_windows([window])
	platforms.follow_support()
	check(pet.win_pos == Vector2(350, 270), "Pet follows supporting window movement")
	pet.direction = Vector2.RIGHT
	platforms.walk(10)
	check(pet.surface == pet.Surface.FALLING, "Walking off a window starts falling")
	platforms.attach(platforms.platforms[0])
	platforms.set_windows([])
	platforms.follow_support()
	check(pet.surface == pet.Surface.FALLING, "Closed or minimized support releases pet")
	for top in [-100, 0, 1]:
		window.y = top
		platforms.set_windows([window])
		check(platforms.platforms.is_empty(), "Window without enough headroom rejected")
	window.y = 150
	platforms.set_windows([window])
	check(not platforms.platforms.is_empty(), "Partly offscreen perch is allowed")
	pet.win_pos = Vector2(350, 700)
	pet.surface = pet.Surface.FLOOR
	platforms.start_hop()
	check(platforms.advance_hop(1.2) and pet.win_pos.y == -50, "Hop reaches partially clipped perch")
	pet._advance_motion(0.01, Vector2(1000, 700))
	check(pet.surface == pet.Surface.WINDOW_TOP and pet.win_pos.y == -50, "Walking preserves partially clipped perch")
	window.y = 0
	platforms.set_windows([window])
	platforms.follow_support()
	check(pet.surface == pet.Surface.FALLING, "Moving perch fully offscreen releases pet")
	window.y = 150
	platforms.set_windows([window])
	platforms.start_hop()
	window.y = 0
	platforms.set_windows([window])
	check(platforms.advance_hop(0.2) and pet.surface == pet.Surface.FALLING, "Hop cancels when destination moves fully offscreen")
	window.y = 450
	var covering = {"id": "front", "x": 1200, "y": 0, "w": 1200, "h": 900}
	platforms.set_windows([covering, window])
	check(platforms.platforms.is_empty(), "Maximized foreground window hides rear platforms")
	covering.w = 500
	platforms.set_windows([covering, window])
	check(platforms.platforms.size() == 1 and platforms.platforms[0].left == 500, "Only exposed top segment can support pet")
	pet.win_pos = Vector2(600, 200)
	pet.fall_speed = -200
	check(not platforms.land(Vector2(600, 100)), "Rising pet cannot land")
	platforms.start_hop()
	platforms.advance_hop(0.6)
	check(pet.win_pos.y >= 0 and pet.win_pos.x >= 0, "Hop stays on-screen")
	window.y += 20
	platforms.set_windows([window])
	check(platforms.advance_hop(0.6) and pet.surface == pet.Surface.WINDOW_TOP and pet.win_pos.y == 270, "Hop lands on the current position of a moving window")
	pet.surface = pet.Surface.FLOOR
	platforms.support = ""
	platforms.start_hop()
	platforms.set_windows([])
	check(platforms.advance_hop(0.1) and pet.surface == pet.Surface.FALLING, "Hop aborts into gravity when destination disappears")
	# Write the embedded helper for a separate read-only native smoke check.
	var helper = FileAccess.open("res://.godot/probe-smoke.ps1", FileAccess.WRITE)
	helper.store_string(preload("res://Code/WindowProbe.gd").SCRIPT)
	helper.close()
	pet.free()
	if failures == 0:
		print("PASS: window landing, movement, headroom, occlusion, edge falls, and lost destinations")
	quit(1 if failures else 0)
