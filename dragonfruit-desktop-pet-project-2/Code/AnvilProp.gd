# Heavy draggable prop. Reuses the ball's throwing and desktop boundaries.
extends "res://Code/BallProp.gd"

var props
var landing_audio: AudioStreamPlayer
# Volume in decibels; the Options master slider also controls this sound.
var landing_volume_db = -8.0

func _ready():
	super._ready()
	title = "Pet anvil"
	picture.texture = preload("res://Sprites/anvil.png")
	gravity = 1500.0
	bounce = 0.0
	friction = 1200.0
	landing_audio = AudioStreamPlayer.new()
	landing_audio.stream = load("res://Audio/anvil-made-with-Voicemod.mp3")
	add_child(landing_audio)

func advance_motion(delta):
	var previous = ball_position
	super.advance_motion(delta)
	var floor_y = maxf(screen_rect.position.y, screen_rect.end.y - size.y)
	# Play only when crossing onto the floor. Gravity also runs while resting,
	# so checking downward velocity alone would restart the sound every frame.
	if previous.y < floor_y and ball_position.y >= floor_y and landing_audio != null:
		landing_audio.volume_db = landing_volume_db
		landing_audio.play()
	if props != null:
		props.check_anvil_hit(self, previous)
