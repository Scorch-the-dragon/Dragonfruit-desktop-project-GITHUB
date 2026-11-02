# Reuse the note event's departure, retrieval, and dragging animation.
extends "res://Code/NoteDelivery.gd"

var images_folder = ""
var supported_extensions = ["png", "jpg", "jpeg", "webp", "bmp"]
var max_image_bytes = 32 * 1024 * 1024
var max_texture_side = 4096


func setup(pet_node):
	super.setup(pet_node)
	images_folder = "res://PetImages" if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("PetImages")


func _create_delivery_window():
	return preload("res://Code/PetImageWindow.gd").new()


func _prepare_content():
	var selected = read_random_image()
	note_window.set_image(selected.filename, selected.texture, selected.message)


func read_random_image():
	var candidates: Array[String] = []
	var directory = DirAccess.open(images_folder)
	if directory != null:
		for filename in directory.get_files():
			if filename.get_extension().to_lower() in supported_extensions:
				candidates.append(filename)
	candidates.shuffle()
	for filename in candidates:
		var path = images_folder.path_join(filename)
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > max_image_bytes:
			continue
		file.close()
		# Load the actual image file rather than an imported resource, so files
		# added while the app is running (or beside an exported game) work too.
		var image = Image.new()
		if image.load(path) != OK or image.is_empty():
			continue
		var largest_side = maxi(image.get_width(), image.get_height())
		if largest_side > max_texture_side:
			var factor = float(max_texture_side) / largest_side
			image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)))
		return {"filename": filename, "texture": ImageTexture.create_from_image(image), "message": ""}
	return {"filename": "No images yet", "texture": null,
		"message": "Add PNG, JPG, JPEG, WebP or BMP images to:\n" + ProjectSettings.globalize_path(images_folder) + "\n\nThen choose Bring an image again. Unreadable files and files over 32 MiB are skipped."}
