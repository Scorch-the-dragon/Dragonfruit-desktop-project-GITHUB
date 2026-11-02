# PET CARE MENU
# Values are 0-100: a FULL hunger bar means fed, a FULL thirst bar means hydrated.
# Stats last for this run of the game. They reset when you restart the pet.
extends Window

signal item_requested(kind)
signal event_requested(id)
signal option_changed(key, value)
signal prop_requested(kind)
signal remove_props_requested
var care_enabled = true
var options_view: VBoxContainer
var options_list: VBoxContainer
var options_status: Label
var care_toggle: CheckBox
var random_toggle: CheckBox
var volume_slider: HSlider
var volume_label: Label
var event_toggles = {}
var event_buttons = {}
var preferences
var care_view: VBoxContainer
var events_view: VBoxContainer
var spawn_view: VBoxContainer
var events_list: VBoxContainer

# Change these starting values, refill amounts, and drain rates to tune care.
var hunger = 75.0
var thirst = 75.0
var happiness = 75.0
var food_amount = 25.0
var drink_amount = 25.0
# Points lost per SECOND while the app is running (including with the menu shut).
# At these rates a full bar lasts roughly 33, 28, and 42 minutes respectively.
# Set a rate to 0.0 if you do not want that stat to decrease automatically.
var hunger_drain = 0.05
var thirst_drain = 0.06
var happiness_drain = 0.04
var bars = {}
var values = {}
var feedback: Label


func _init():
	# Start hidden before entering the scene tree, avoiding a window flash.
	visible = false


func _ready():
	name = "PetCareMenu"
	title = "Dragonfruit care"
	visible = false
	size = Vector2i(340, 480)
	unresizable = true
	always_on_top = true
	transient = true
	# Keep this window opaque even though the pet's own window is transparent.
	transparent = false
	transparent_bg = false
	close_requested.connect(hide)
	window_input.connect(_on_window_input)
	_build_controls()
	_refresh_stats()


func _build_controls():
	var panel = PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var column = VBoxContainer.new()
	care_view = column
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var heading = Label.new()
	heading.text = "How is the boi doing?"
	heading.add_theme_font_size_override("font_size", 20)
	column.add_child(heading)
	var hint = Label.new()
	hint.text = "Full bars mean the boi is well cared for."
	hint.add_theme_font_size_override("font_size", 12)
	column.add_child(hint)
	_add_stat(column, "Hunger", "Feed", feed)
	_add_stat(column, "Thirst", "Drink", give_drink)
	_add_stat(column, "Happiness", "", Callable())
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.custom_minimum_size = Vector2(260, 32)
	feedback.text = "Rub the mouse over the boi for happiness."
	feedback.add_theme_font_size_override("font_size", 12)
	column.add_child(feedback)
	var shenanigans = Button.new()
	shenanigans.text = "Shenanigans"
	shenanigans.pressed.connect(func():
		care_view.hide()
		events_view.show())
	column.add_child(shenanigans)
	var options_button = Button.new()
	options_button.text = "Options"
	options_button.pressed.connect(func():
		care_view.hide()
		events_view.hide()
		options_view.show())
	column.add_child(options_button)
	var spawn_button = Button.new()
	spawn_button.text = "Spawn menu"
	spawn_button.pressed.connect(func():
		care_view.hide()
		spawn_view.show())
	column.add_child(spawn_button)
	var exit_row = HBoxContainer.new()
	column.add_child(exit_row)
	var close_button = Button.new()
	close_button.text = "Close menu"
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button.pressed.connect(hide)
	exit_row.add_child(close_button)
	var quit_button = Button.new()
	quit_button.text = "Quit pet"
	quit_button.tooltip_text = "Close the pet program and all of its windows."
	quit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Normal shutdown also runs _exit_tree(), which stops the window helper.
	quit_button.pressed.connect(func(): get_tree().quit())
	exit_row.add_child(quit_button)
	# A separate page keeps the list usable as more events are added.
	events_view = VBoxContainer.new()
	events_view.add_theme_constant_override("separation", 10)
	margin.add_child(events_view)
	events_view.hide()
	var title_label = Label.new()
	title_label.text = "Shenanigans"
	title_label.add_theme_font_size_override("font_size", 22)
	events_view.add_child(title_label)
	var scroll = ScrollContainer.new()
	_configure_page_scroll(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	events_view.add_child(scroll)
	events_list = VBoxContainer.new()
	events_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(events_list)
	var back = Button.new()
	back.text = "Back to care"
	back.pressed.connect(_show_care)
	events_view.add_child(back)
	_build_options(margin)
	_build_spawn_menu(margin)


func _build_spawn_menu(parent):
	spawn_view = VBoxContainer.new()
	spawn_view.add_theme_constant_override("separation", 8)
	parent.add_child(spawn_view)
	spawn_view.hide()
	var heading = Label.new()
	heading.text = "Spawn props"
	heading.add_theme_font_size_override("font_size", 22)
	spawn_view.add_child(heading)
	var scroll = ScrollContainer.new()
	_configure_page_scroll(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spawn_view.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for entry in [["ball", "Spawn ball"], ["green_paint", "Green paint"], ["paint_remover", "Paint remover"], ["anvil", "Anvil"], ["blue_portal", "Blue portal ball"], ["orange_portal", "Orange portal ball"]]:
		var button = Button.new()
		button.text = entry[1]
		button.pressed.connect(func(): prop_requested.emit(entry[0]))
		list.add_child(button)
	var remove_all = Button.new()
	remove_all.text = "Remove all props"
	remove_all.pressed.connect(func(): remove_props_requested.emit())
	spawn_view.add_child(remove_all)
	var back = Button.new()
	back.text = "Back to care"
	back.pressed.connect(_show_care)
	spawn_view.add_child(back)


func _show_care():
	spawn_view.hide()
	events_view.hide()
	options_view.hide()
	care_view.show()


# The catalog supplies both the random events and these buttons.
func set_events(catalog):
	event_buttons.clear()
	for child in events_list.get_children():
		events_list.remove_child(child)
		child.queue_free()
	for entry in catalog:
		var button = Button.new()
		button.text = entry.label
		button.clip_text = true
		button.tooltip_text = entry.description
		button.pressed.connect(func():
			_show_care()
			event_requested.emit(entry.id))
		events_list.add_child(button)
		event_buttons[entry.id] = button
		if preferences != null:
			button.disabled = preferences.disabled_events.has(entry.id)


func _add_stat(column, stat_name, button_text, action):
	var row = HBoxContainer.new()
	column.add_child(row)
	var label = Label.new()
	label.text = stat_name
	label.tooltip_text = {"Hunger": "Restores red color. All three stats affect movement speed.", "Thirst": "Restores blue color. All three stats affect movement speed.", "Happiness": "Restores green color. All three stats affect movement speed."}.get(stat_name, "")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value_label = Label.new()
	row.add_child(value_label)
	values[stat_name] = value_label
	if not button_text.is_empty():
		var button = Button.new()
		button.text = button_text
		button.custom_minimum_size.x = 65
		button.pressed.connect(action)
		row.add_child(button)
	var bar = ProgressBar.new()
	bar.custom_minimum_size.y = 14
	bar.show_percentage = false
	bar.max_value = 100.0
	column.add_child(bar)
	bars[stat_name] = bar


func _process(delta):
	_decay_stats(delta)
	if visible:
		_refresh_stats()


func _decay_stats(delta):
	if not care_enabled:
		hunger = 100.0
		thirst = 100.0
		happiness = 100.0
		return
	hunger = clampf(hunger - hunger_drain * delta, 0.0, 100.0)
	thirst = clampf(thirst - thirst_drain * delta, 0.0, 100.0)
	happiness = clampf(happiness - happiness_drain * delta, 0.0, 100.0)


# Buttons offer an item; stats refill only after the pet finishes consuming it.
func feed():
	item_requested.emit("food")


func give_drink():
	item_requested.emit("drink")


func finish_consuming(kind):
	if kind == "food":
		hunger = clampf(hunger + food_amount, 0.0, 100.0)
		_show_feedback("The boi has been fed.")
	elif kind == "drink":
		thirst = clampf(thirst + drink_amount, 0.0, 100.0)
		_show_feedback("The boi enjoyed the liquid.")


# Main.gd calls this only for mouse strokes over the pet, even with the menu shut.
func receive_pets(amount):
	happiness = clampf(happiness + maxf(0.0, amount), 0.0, 100.0)
	_show_feedback("The boi loves the pets.")


func _show_feedback(message):
	if feedback != null:
		feedback.text = message
	_refresh_stats()


func _refresh_stats():
	var stats = {"Hunger": hunger, "Thirst": thirst, "Happiness": happiness}
	for stat_name in bars:
		bars[stat_name].value = stats[stat_name]
		values[stat_name].text = "%d / 100" % roundi(stats[stat_name])


func open_near_pet():
	_refresh_stats()
	# Prefer beside the pet, then clamp onto the monitor's usable desktop so
	# the menu remains accessible at floor, ceiling, and wall corners.
	var screen = DisplayServer.window_get_current_screen()
	var usable = DisplayServer.screen_get_usable_rect(screen)
	var pet_position = DisplayServer.window_get_position()
	var pet_size = DisplayServer.window_get_size()
	var desired = pet_position + Vector2i(pet_size.x + 8, 0)
	if desired.x + size.x > usable.end.x:
		desired.x = pet_position.x - size.x - 8
	position = Vector2i(
		clampi(desired.x, usable.position.x, maxi(usable.position.x, usable.end.x - size.x)),
		clampi(desired.y, usable.position.y, maxi(usable.position.y, usable.end.y - size.y))
	)
	show()
	grab_focus()


func _on_window_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()


func _build_options(parent):
	options_view = VBoxContainer.new()
	options_view.add_theme_constant_override("separation", 8)
	parent.add_child(options_view)
	options_view.hide()
	var heading = Label.new()
	heading.text = "Options"
	heading.add_theme_font_size_override("font_size", 22)
	options_view.add_child(heading)
	var scroll = ScrollContainer.new()
	_configure_page_scroll(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options_view.add_child(scroll)
	options_list = VBoxContainer.new()
	options_list.add_theme_constant_override("separation", 8)
	options_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(options_list)
	care_toggle = CheckBox.new()
	care_toggle.text = "Care needs"
	care_toggle.tooltip_text = "Turn off to keep hunger, thirst and happiness full. Feeding and petting still work."
	care_toggle.toggled.connect(func(enabled): option_changed.emit("care_enabled", enabled))
	options_list.add_child(care_toggle)
	random_toggle = CheckBox.new()
	random_toggle.text = "Random events"
	random_toggle.tooltip_text = "Turn off automatic events. Enabled events can still be triggered from Shenanigans."
	random_toggle.toggled.connect(func(enabled): option_changed.emit("random_events_enabled", enabled))
	options_list.add_child(random_toggle)
	volume_label = Label.new()
	options_list.add_child(volume_label)
	volume_slider = HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 1
	# Let the mouse wheel scroll the page instead of accidentally changing volume.
	volume_slider.scrollable = false
	volume_slider.custom_minimum_size = Vector2(240, 24)
	volume_slider.tooltip_text = "Master volume for all pet sounds. 0% mutes everything."
	volume_slider.value_changed.connect(func(value): option_changed.emit("volume_percent", value))
	options_list.add_child(volume_slider)
	var events_heading = Label.new()
	events_heading.text = "Allowed events"
	options_list.add_child(events_heading)
	options_status = Label.new()
	options_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	options_status.custom_minimum_size = Vector2(260, 40)
	options_view.add_child(options_status)
	var back = Button.new()
	back.text = "Back to care"
	back.pressed.connect(_show_care)
	options_view.add_child(back)


func configure_options(saved_preferences, catalog):
	preferences = saved_preferences
	for toggle in event_toggles.values():
		options_list.remove_child(toggle)
		toggle.queue_free()
	event_toggles.clear()
	for entry in catalog:
		var toggle = CheckBox.new()
		toggle.text = entry.label
		toggle.clip_text = true
		toggle.tooltip_text = "Allow this event randomly and from Shenanigans. An event already running will finish."
		toggle.toggled.connect(func(enabled): option_changed.emit("event:" + entry.id, enabled))
		options_list.add_child(toggle)
		event_toggles[entry.id] = toggle
	refresh_options()


func refresh_options():
	care_toggle.set_pressed_no_signal(preferences.care_enabled)
	random_toggle.set_pressed_no_signal(preferences.random_events_enabled)
	volume_slider.set_value_no_signal(preferences.volume_percent)
	volume_label.text = "Volume: %d%%" % roundi(preferences.volume_percent)
	options_status.text = "Changes save automatically. Running events finish before being disabled."
	for id in event_toggles:
		var enabled = not preferences.disabled_events.has(id)
		event_toggles[id].set_pressed_no_signal(enabled)
		if event_buttons.has(id):
			event_buttons[id].disabled = not enabled


# Both pages scroll vertically as their lists grow. Headings and Back buttons
# live outside the scroll container so they remain visible. Keyboard focus also
# scrolls the list to bring the selected control into view.
func _configure_page_scroll(scroll: ScrollContainer):
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.custom_minimum_size.y = 100
