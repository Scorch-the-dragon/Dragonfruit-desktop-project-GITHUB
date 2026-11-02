# Saved separately from the project, in Godot's per-user application folder.
# Add future options here, then expose them in PetCareMenu's Options page.
extends RefCounted

var path = "user://pet_preferences.cfg"
var care_enabled = true
var random_events_enabled = true
var disabled_events: Array[String] = []
var volume_percent = 100.0


func load_preferences():
	var config = ConfigFile.new()
	if config.load(path) != OK:
		return # Missing/corrupt preferences keep the safe default settings.
	var care = config.get_value("options", "care_enabled", true)
	var random_events = config.get_value("options", "random_events_enabled", true)
	var volume = config.get_value("options", "volume_percent", 100.0)
	care_enabled = care if care is bool else true
	random_events_enabled = random_events if random_events is bool else true
	if (volume is float or volume is int) and is_finite(float(volume)):
		volume_percent = clampf(float(volume), 0.0, 100.0)
	var disabled = config.get_value("options", "disabled_events", [])
	disabled_events.clear()
	if disabled is Array:
		for id in disabled:
			if id is String and not disabled_events.has(id):
				disabled_events.append(id)


func save_preferences():
	var config = ConfigFile.new()
	config.set_value("options", "care_enabled", care_enabled)
	config.set_value("options", "random_events_enabled", random_events_enabled)
	config.set_value("options", "disabled_events", disabled_events)
	config.set_value("options", "volume_percent", volume_percent)
	return config.save(path)


func apply_volume():
	# The Master bus controls ALL current and future audio, even while playing.
	var master = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(master, volume_percent <= 0.0)
	AudioServer.set_bus_volume_db(master, linear_to_db(maxf(volume_percent / 100.0, 0.0001)))
