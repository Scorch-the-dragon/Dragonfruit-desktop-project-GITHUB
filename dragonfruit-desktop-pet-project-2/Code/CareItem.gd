# A separate desktop window lets the item be dragged from the menu to the pet.
# Replace the two SVG images to customize the food and drink appearance.
extends Window

signal dropped(kind, desktop_position)
var kind = "food"
var dragging = false
var drag_offset = Vector2i.ZERO
var picture: TextureRect


func _init():
	visible = false


func _ready():
	size = Vector2i(64, 64)
	borderless = true
	unresizable = true
	always_on_top = true
	transparent = true
	transparent_bg = true
	picture = TextureRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window_input.connect(_on_input)
	close_requested.connect(cancel)


func offer(item_kind, at_position):
	kind = item_kind
	dragging = false
	picture.texture = load("res://Sprites/food_item.png" if kind == "food" else "res://Sprites/drink_item.svg")
	position = at_position
	show()


func _on_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			drag_offset = DisplayServer.mouse_get_position() - position
		elif dragging:
			_drop()


func _process(_delta):
	if dragging:
		position = DisplayServer.mouse_get_position() - drag_offset
		# Poll as well, so releases outside the item window are caught.
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_drop()


func _drop():
	dragging = false
	dropped.emit(kind, DisplayServer.mouse_get_position())
	# A missed drop leaves the item available to grab and try again.


func cancel():
	dragging = false
	hide()
