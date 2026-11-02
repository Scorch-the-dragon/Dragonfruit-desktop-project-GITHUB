# Reuse the ball's native-window dragging, throwing, and floor physics.
extends "res://Code/BallProp.gd"

var kind = "green_paint"

func _ready():
	super._ready()
	title = "Green paint" if kind == "green_paint" else "Paint remover"
	picture.texture = preload("res://Sprites/Green paint.svg") if kind == "green_paint" else preload("res://Sprites/Remove paint.png")
	bounce = 0.0
	friction = 800.0
