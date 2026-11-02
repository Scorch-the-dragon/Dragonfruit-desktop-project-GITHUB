# Window-top platforms. All coordinates below are relative to the pet's monitor.
extends Node

var pet
var platforms: Array = []
var support = ""
var support_left = 0.0
var probe_pid = -1
var snapshot_path = ""
var poll_timer = 0.0
var hop_time = 0.0
var hop_start = Vector2()
var hop_target = {}
# Change these to adjust flight duration and the upward arc.
var hop_seconds = 1.2
var hop_height = 100.0
# Allow partial clipping, but keep a visible strip of the artwork (not merely
# the transparent pet window) on-screen. Increase this for more headroom.
var minimum_visible_pixels = 24.0
var artwork_bounds = {}


func minimum_perch_y():
	var visible_bottom = pet.window_size.y
	var scene_height = float(ProjectSettings.get_setting("display/window/size/viewport_height", 200))
	var pixel_scale = pet.window_size.y / maxf(1.0, scene_height)
	for animation in ["walk_left", "walk_right", "idle", "crouch", "splat", "petting", "eating", "drinking"]:
		if not pet.sprite.sprite_frames.has_animation(animation):
			continue
		for frame in pet.sprite.sprite_frames.get_frame_count(animation):
			var texture = pet.sprite.sprite_frames.get_frame_texture(animation, frame)
			if texture == null:
				continue
			if not artwork_bounds.has(texture):
				artwork_bounds[texture] = texture.get_image().get_used_rect()
			var used = artwork_bounds[texture]
			var center_offset = texture.get_height() * 0.5 if pet.sprite.centered else 0.0
			var bottom = pet.sprite.position.y + (used.end.y - center_offset + pet.sprite.offset.y) * pet.sprite.scale.y
			visible_bottom = minf(visible_bottom, bottom * pixel_scale)
	return minf(0.0, minimum_visible_pixels - visible_bottom)


func setup(pet_node):
	pet = pet_node
	if OS.get_name() != "Windows" or DisplayServer.get_name() == "headless":
		return
	var base = ProjectSettings.globalize_path("user://window_probe_" + str(OS.get_process_id()))
	snapshot_path = base + ".json"
	var script_path = base + ".ps1"
	var file = FileAccess.open(script_path, FileAccess.WRITE)
	if file == null:
		push_warning("Window platforms unavailable: could not create the window helper.")
		return
	file.store_string(preload("res://Code/WindowProbe.gd").SCRIPT)
	file.close()
	probe_pid = OS.create_process("powershell.exe", ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", script_path, "-OutputPath", snapshot_path, "-PetProcess", str(OS.get_process_id())], false)


func _exit_tree():
	if probe_pid > 0 and OS.is_process_running(probe_pid):
		OS.kill(probe_pid)
	if not snapshot_path.is_empty():
		for path in [snapshot_path, snapshot_path + ".tmp", snapshot_path.get_basename() + ".ps1"]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func refresh(delta):
	if snapshot_path.is_empty():
		return
	poll_timer -= delta
	if poll_timer > 0.0:
		return
	poll_timer = 0.25
	var data = JSON.parse_string(FileAccess.get_file_as_string(snapshot_path)) if FileAccess.file_exists(snapshot_path) else null
	var modified = FileAccess.get_modified_time(snapshot_path) if FileAccess.file_exists(snapshot_path) else 0
	if data is Array and Time.get_unix_time_from_system() - modified < 3.0:
		set_windows(data)
	else:
		platforms.clear() # A stopped helper must not leave invisible platforms.


func set_windows(windows):
	platforms.clear()
	var covers: Array[Rect2] = []
	# EnumWindows returns front-to-back order. Subtract covered parts of each top.
	for item in windows:
		var rect = Rect2(Vector2(item.x, item.y) - pet.screen_origin, Vector2(item.w, item.h))
		var top = rect.position.y
		var spans = [Vector2(maxf(0.0, rect.position.x), minf(pet.screen_size.x, rect.end.x))]
		for cover in covers:
			if cover.position.y <= top and cover.end.y > top:
				var remaining = []
				for span in spans:
					if cover.end.x <= span.x or cover.position.x >= span.y:
						remaining.append(span)
					else:
						if cover.position.x > span.x:
							remaining.append(Vector2(span.x, cover.position.x))
						if cover.end.x < span.y:
							remaining.append(Vector2(cover.end.x, span.y))
				spans = remaining
		# A partly clipped pet is fine; an entirely hidden sprite is not.
		if top > 0.0 and top - pet.window_size.y >= minimum_perch_y() and top < pet.screen_size.y:
			for span in spans:
				if span.y - span.x >= pet.window_size.x:
					platforms.append({"id": str(item.id), "left": span.x, "right": span.y - pet.window_size.x, "y": top - pet.window_size.y})
		covers.append(rect)


func land(previous):
	if pet.fall_speed < 0.0:
		return false
	var hit = {}
	for platform in platforms:
		if previous.y <= platform.y and pet.win_pos.y >= platform.y:
			var fraction = (platform.y - previous.y) / maxf(0.0001, pet.win_pos.y - previous.y)
			var x = lerpf(previous.x, pet.win_pos.x, fraction)
			if x >= platform.left and x <= platform.right and (hit.is_empty() or platform.y < hit.y):
				hit = platform.duplicate()
				hit["x"] = x
	if hit.is_empty():
		return false
	pet.win_pos.x = hit.x
	attach(hit)
	return true


func attach(platform):
	support = platform.id
	support_left = platform.left
	pet.win_pos.y = platform.y
	pet.surface = pet.Surface.WINDOW_TOP
	pet.fall_speed = 0.0
	pet.horizontal_fall_speed = 0.0
	pet._pick_new_direction()


func follow_support():
	if pet.surface != pet.Surface.WINDOW_TOP or pet.is_dragging:
		return
	for platform in platforms:
		if platform.id == support:
			var x = pet.win_pos.x + platform.left - support_left
			if x >= platform.left and x <= platform.right:
				pet.win_pos = Vector2(x, platform.y)
				support_left = platform.left
				return
	detach()


func detach():
	support = ""
	pet.surface = pet.Surface.FALLING
	pet.is_idling = false
	pet.fall_speed = 0.0
	pet.horizontal_fall_speed = pet.direction.x * pet.speed
	pet._end_petting()
	# Losing a perch must not leave care animations suspending the pet in midair.
	if not pet.consuming_kind.is_empty():
		pet.consuming_kind = ""
		pet.consumption_audio.stop()
		pet.sprite.rotation = pet.before_consuming_rotation
		pet.sprite.flip_h = pet.before_consuming_flip_h
	pet._update_animation()


func walk(delta):
	pet.win_pos.x += pet.direction.x * pet.speed * delta
	follow_support() # Walking off an exposed edge starts a normal fall.


func start_hop():
	hop_time = 0.0
	hop_start = pet.win_pos
	var choices = platforms.filter(func(p): return p.id != support or pet.surface != pet.Surface.WINDOW_TOP)
	hop_target = choices.pick_random().duplicate() if not choices.is_empty() else {}
	if hop_target.is_empty():
		return
	pet.surface = pet.Surface.FALLING
	support = ""
	pet.sprite.play("splat")


func advance_hop(delta):
	var current = {}
	for platform in platforms:
		if not hop_target.is_empty() and platform.id == hop_target.id:
			current = platform
	if current.is_empty():
		pet.sprite.rotation = 0.0
		pet.fall_speed = 0.0
		pet.horizontal_fall_speed = 0.0
		pet._update_animation()
		return true
	hop_time += delta
	var t = clampf(hop_time / hop_seconds, 0.0, 1.0)
	var destination = Vector2((current.left + current.right) * 0.5, current.y)
	var before = pet.win_pos
	pet.win_pos = hop_start.lerp(destination, t) - Vector2(0.0, sin(t * PI) * hop_height)
	# Permit a partial landing above the screen edge, but keep the flight arc
	# no higher than either endpoint so it cannot disappear on its way there.
	var minimum_y = minf(0.0, minf(hop_start.y, destination.y))
	pet.win_pos = pet.win_pos.clamp(Vector2(0.0, minimum_y), (pet.screen_size - pet.window_size).max(Vector2.ZERO))
	if pet.win_pos.distance_to(before) > 0.01:
		pet.sprite.rotation = (pet.win_pos - before).angle()
	if pet.win_pos.y < 0.0:
		# The visibility check uses upright artwork. Keep that orientation while
		# clipped so turning the splat sideways cannot hide the remaining strip.
		pet.sprite.rotation = 0.0
	pet._apply_window_position()
	if t >= 1.0:
		attach(current)
		pet.sprite.rotation = 0.0
		pet._update_animation()
		pet._apply_window_position()
		return true
	return false
