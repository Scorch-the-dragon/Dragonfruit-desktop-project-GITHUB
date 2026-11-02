# Image viewer with the same desktop controls as the note window.
extends "res://Code/PetNoteWindow.gd"

var picture: TextureRect


func _ready():
	super._ready()
	picture = TextureRect.new()
	# Large images must not force the window to grow; resize to fit without cropping.
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_image(filename, texture, message = ""):
	title = filename
	picture.texture = texture
	picture.visible = texture != null
	text_box.visible = texture == null
	if texture == null:
		set_note(filename, message)


func finish_delivery():
	super.finish_delivery()
	picture.queue_redraw()
