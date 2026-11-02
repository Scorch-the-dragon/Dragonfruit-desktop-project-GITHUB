# A native, read-only text-file viewer. File contents are plain text, never markup.
extends Window

var text_box: TextEdit
var delivery_complete = false
var background: ColorRect
var close_pending = false


func _init():
	visible = false


func _ready():
	size = Vector2i(420, 280)
	min_size = Vector2i(1, 1)
	transparent = false
	transparent_bg = false
	# Use normal stacking from the outset, so releasing the window never needs
	# to change native flags or recreate its rendering surface.
	always_on_top = false
	# Give both viewers an explicitly opaque canvas, independent of the desktop
	# pet's transparent root window (including behind PNG transparency).
	background = ColorRect.new()
	background.color = Color(0.12, 0.12, 0.14, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text_box = TextEdit.new()
	text_box.editable = false
	text_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(text_box)
	text_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	close_requested.connect(_close_window)
	window_input.connect(_on_window_input)


func begin_delivery():
	delivery_complete = false
	unfocusable = true
	# Enable drawing before the off-screen window is first shown, and retain it
	# throughout delivery and afterward even when the window has no focus.
	RenderingServer.viewport_set_update_mode(get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)


func _on_window_input(event):
	# Do not activate a delivered window automatically. Only an intentional
	# click inside it enables focus, so its title bar arrives in the inactive state.
	if delivery_complete and unfocusable and event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			unfocusable = false
			grab_focus()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_window()


func _close_window():
	hide()
	# Release text/image resources when closed. If still being delivered, keep
	# the object alive until the event has finished using its window reference.
	if delivery_complete:
		queue_free()
	else:
		close_pending = true


func set_note(filename, contents):
	title = filename
	text_box.text = contents
	text_box.scroll_vertical = 0
	text_box.set_caret_line(0)


func finish_delivery():
	# This is only an interaction-state change. Leave visibility, focus, size,
	# position, and native window flags untouched for a seamless release.
	delivery_complete = true
	if close_pending:
		queue_free()
		return
	background.queue_redraw()
	text_box.queue_redraw()
