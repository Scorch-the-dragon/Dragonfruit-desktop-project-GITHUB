# Gentle click feedback. Baked volume curves drive a spring, using audio time.
extends Node

const PROFILES = preload("res://Audio/SqueakProfiles.gd").DATA
const SOUNDS = [preload("res://Audio/soft-squeak-made-with-Voicemod.mp3"), preload("res://Audio/squeaky-made-with-Voicemod.mp3"), preload("res://Audio/squeaky-toy-made-with-Voicemod.mp3")]
var pet
var player: AudioStreamPlayer
var active = false
var elapsed = 0.0
var profile = {}
var normal_scale = Vector2.ONE
var compression = 0.0
var spring_speed = 0.0
var held_animation: StringName
var held_frame = 0
var held_progress = 0.0

func _ready():
	player = AudioStreamPlayer.new()
	player.volume_db = -5.0 # Also respects the Options master volume slider.
	add_child(player)

func start():
	if active:
		cancel()
	pet._end_petting()
	pet.is_idling = false
	normal_scale = pet.sprite.scale
	held_animation = pet.sprite.animation
	held_frame = pet.sprite.frame
	held_progress = pet.sprite.frame_progress
	_hold_frame()
	var index = randi_range(0, SOUNDS.size() - 1)
	player.stream = SOUNDS[index]
	profile = PROFILES[player.stream.resource_path.get_file()]
	elapsed = 0.0
	compression = 0.12
	spring_speed = 0.0
	active = true
	player.play()
	_apply_shape()

func advance(delta):
	if not active:
		return false
	elapsed += delta
	if elapsed >= profile.length + 0.45:
		cancel()
		return false
	var audio_time = profile.length
	if player.playing:
		audio_time = maxf(0.0, player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())
	var level = 0.0
	var sample = audio_time / profile.step
	var index = int(sample)
	if index < profile.envelope.size():
		level = lerpf(profile.envelope[index], profile.envelope[mini(index + 1, profile.envelope.size() - 1)], sample - index)
	var remaining = minf(delta, 0.1)
	while remaining > 0:
		var step = minf(remaining, 1.0 / 120.0)
		remaining -= step
		spring_speed += ((level * 0.3 - compression) * 260.0 - spring_speed * 15.0) * step
		compression += spring_speed * step
	_apply_shape()
	if pet.surface == pet.Surface.FALLING:
		pet._advance_motion(delta, (pet.screen_size - pet.window_size).max(Vector2.ZERO))
		pet._apply_window_position()
	# Landing may choose an idle animation. Keep the captured frame until the
	# squish ends, while allowing gravity and the scale bounce to continue.
	_hold_frame()
	return true

func _hold_frame():
	pet.sprite.animation = held_animation
	pet.sprite.set_frame_and_progress(held_frame, held_progress)
	pet.sprite.pause()

func _apply_shape():
	var amount = clampf(compression, -0.15, 0.4)
	var factor = Vector2(1.0 + amount * 0.5, 1.0 - amount)
	if pet.surface in [pet.Surface.LEFT_WALL, pet.Surface.RIGHT_WALL]:
		factor = Vector2(factor.y, factor.x)
	pet.sprite.scale = normal_scale * factor

func cancel():
	if not active:
		return
	active = false
	player.stop()
	pet.sprite.scale = normal_scale
	pet._update_animation()
