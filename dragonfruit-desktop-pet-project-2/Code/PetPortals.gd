extends Node
var pet
var endpoints = {}
var glows = {}
var cooldown = 0.0
# Walkers need to leave the exit opening before it can accept them again.
# A timer alone expires while slow pets are still inside the portal.
var walking_exit = {}
var portal_length = 180.0
var placement_audio = {}
var placement_volume_db = -8.0 # Also respects the Options master volume.
var enter_audio: AudioStreamPlayer
var exit_audio: AudioStreamPlayer
var enter_sounds: Array[AudioStream] = []
var exit_sounds: Array[AudioStream] = []
var travel_volume_db = -8.0 # Uses the Options master volume, like placement.
const NORMALS = {"left": Vector2.RIGHT, "right": Vector2.LEFT, "top": Vector2.DOWN, "bottom": Vector2.UP}

func _ready():
	# Keep the players here: the thrown ball is freed as soon as it places a
	# portal, but its sound must finish. Separate players keep colors distinct.
	for color in ["blue", "orange"]:
		var player = AudioStreamPlayer.new()
		player.stream = load("res://Audio/%s-portal-placed-made-with-Voicemod.mp3" % color)
		player.volume_db = placement_volume_db
		player.max_polyphony = 4
		add_child(player)
		placement_audio[color] = player
	for index in range(1, 3):
		enter_sounds.append(load("res://Audio/portal_enter%d.wav" % index))
		exit_sounds.append(load("res://Audio/portal_exit%d.wav" % index))
	enter_audio = AudioStreamPlayer.new()
	exit_audio = AudioStreamPlayer.new()
	for player in [enter_audio, exit_audio]:
		player.volume_db = travel_volume_db
		add_child(player)

func clear_portals():
	for glow in glows.values():
		if is_instance_valid(glow): glow.queue_free()
	glows.clear()
	endpoints.clear()
	cooldown = 0.0
	walking_exit.clear()

func place_portal(color, edge, at, screen):
	# A newly placed portal is a new opening, not the old guarded exit.
	walking_exit.clear()
	var vertical = edge in ["left", "right"]
	var center = at
	var half = minf(portal_length * 0.5, (screen.size.y if vertical else screen.size.x) * 0.5)
	if vertical:
		center.x = screen.position.x if edge == "left" else screen.end.x
		center.y = clampf(at.y, screen.position.y + half, screen.end.y - half)
	else:
		center.y = screen.position.y if edge == "top" else screen.end.y
		center.x = clampf(at.x, screen.position.x + half, screen.end.x - half)
	endpoints[color] = {"edge": edge, "center": center, "screen": screen, "half": half}
	if glows.has(color) and is_instance_valid(glows[color]): glows[color].queue_free()
	var window = Window.new()
	window.visible = false
	window.borderless = true
	window.unresizable = true
	window.unfocusable = true
	window.mouse_passthrough = true
	window.always_on_top = true
	window.transparent = true
	window.transparent_bg = true
	window.size = Vector2i(24, int(half * 2)) if vertical else Vector2i(int(half * 2), 24)
	add_child(window)
	var art = preload("res://Code/PortalGlow.gd").new()
	art.color = Color(0.1, 0.6, 1.0) if color == "blue" else Color(1.0, 0.4, 0.05)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.position = Vector2i((center - Vector2(window.size) * 0.5).clamp(screen.position, screen.end - Vector2(window.size)))
	window.show()
	glows[color] = window
	placement_audio[color].play()

func _inside_walking_exit(position):
	if walking_exit.is_empty() or walking_exit.screen.position != pet.screen_origin:
		return false
	var vertical = walking_exit.edge in ["left", "right"]
	var limits = (pet.screen_size - pet.window_size).max(Vector2.ZERO)
	var boundary = 0.0 if walking_exit.edge in ["left", "top"] else (limits.x if vertical else limits.y)
	var axis = position.x if vertical else position.y
	var center = position + pet.window_size * 0.5 + pet.screen_origin
	var along = center.y - walking_exit.center.y if vertical else center.x - walking_exit.center.x
	return absf(axis - boundary) <= 8.0 and absf(along) <= walking_exit.half + 8.0

func try_travel(previous, airborne):
	if not walking_exit.is_empty():
		# Use the start of this step: crossing out must not count as entering
		# again through the swept walking-contact check below.
		if _inside_walking_exit(previous):
			return false
		walking_exit.clear()
	if cooldown > 0 or endpoints.size() != 2: return false
	var limits = (pet.screen_size - pet.window_size).max(Vector2.ZERO)
	for color in endpoints:
		var entry = endpoints[color]
		if entry.screen.position != pet.screen_origin: continue
		var vertical = entry.edge in ["left", "right"]
		var boundary = 0.0 if entry.edge in ["left", "top"] else (limits.x if vertical else limits.y)
		var old_axis = previous.x if vertical else previous.y
		var new_axis = pet.win_pos.x if vertical else pet.win_pos.y
		var crossed = new_axis <= boundary if entry.edge in ["left", "top"] else new_axis >= boundary
		if not crossed: continue
		var fraction = clampf((boundary - old_axis) / (new_axis - old_axis), 0, 1) if not is_equal_approx(old_axis, new_axis) else 1.0
		var contact = previous.lerp(pet.win_pos, fraction) + pet.window_size * 0.5 + pet.screen_origin
		var offset = contact.y - entry.center.y if vertical else contact.x - entry.center.x
		# Sweep along the portal too, so walking/climbing through it works.
		var old_offset = previous.y + pet.window_size.y * 0.5 + pet.screen_origin.y - entry.center.y if vertical else previous.x + pet.window_size.x * 0.5 + pet.screen_origin.x - entry.center.x
		if absf(offset) > entry.half and (airborne or minf(offset, old_offset) > entry.half or maxf(offset, old_offset) < -entry.half): continue
		var exit_portal = endpoints["orange" if color == "blue" else "blue"]
		var normal = NORMALS[entry.edge]
		var out_normal = NORMALS[exit_portal.edge]
		var tangent = Vector2(-normal.y, normal.x)
		var out_tangent = Vector2(-out_normal.y, out_normal.x)
		var velocity = Vector2(pet.horizontal_fall_speed, pet.fall_speed) if airborne else pet.direction * pet.speed
		if airborne and velocity.dot(normal) >= 0: continue
		# All entry checks passed. Separate players let the entry sound finish
		# while the exit sound plays; teleportation itself is instantaneous.
		enter_audio.stream = enter_sounds.pick_random()
		enter_audio.play()
		var out_velocity = out_normal * -velocity.dot(normal) + out_tangent * velocity.dot(tangent)
		pet.screen_origin = exit_portal.screen.position
		pet.screen_size = exit_portal.screen.size
		limits = (pet.screen_size - pet.window_size).max(Vector2.ZERO)
		pet.win_pos = (exit_portal.center - pet.screen_origin - pet.window_size * 0.5).clamp(Vector2.ZERO, limits)
		pet.is_idling = false
		pet.landing_splat_remaining = 0.0
		if airborne:
			pet.win_pos += out_normal * 4.0
			pet.horizontal_fall_speed = out_velocity.x
			pet.fall_speed = out_velocity.y
			pet.surface = pet.Surface.FALLING
		else:
			pet.surface = {"left": pet.Surface.LEFT_WALL, "right": pet.Surface.RIGHT_WALL, "top": pet.Surface.CEILING, "bottom": pet.Surface.FLOOR}[exit_portal.edge]
			pet.direction = out_tangent * (-1.0 if velocity.dot(tangent) < 0 else 1.0)
			walking_exit = exit_portal.duplicate()
		cooldown = 0.35
		pet._update_animation()
		exit_audio.stream = exit_sounds.pick_random()
		exit_audio.play()
		return true
	return false
