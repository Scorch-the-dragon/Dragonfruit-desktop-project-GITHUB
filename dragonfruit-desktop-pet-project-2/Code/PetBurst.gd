# Frames extracted from explosion-deltarune.gif at its original 100ms timing.
extends Node2D

var progress = 0.0
var duration = 1.7
var sheet: Texture2D = preload("res://Sprites/explosion-deltarune-sheet.png")


func _ready():
	# Keep the small pixel-art GIF crisp when enlarged.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw():
	var frame = clampi(int(progress * 17), 0, 16)
	var source = Rect2(Vector2((frame % 5) * 48, (frame / 5) * 48), Vector2(48, 48))
	# Fit the whole GIF in the pet's transparent window without stretching it.
	var side = minf(minf(get_viewport_rect().size.x, get_viewport_rect().size.y), 190.0)
	var draw_size = Vector2(side, side)
	draw_texture_rect_region(sheet, Rect2(-draw_size * 0.5, draw_size), source)
