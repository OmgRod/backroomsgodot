extends Node

const SAVE_DIR: String = "user://saves/"

var current_slot_name: String = "save_slot_1"

var save_data: Dictionary = {
	"save_name": "New Save",
	"timestamp": 0,
	"player_position": {"x": 0.0, "y": 0.0, "z": 0.0},
	"current_level_seed": 0,
	"current_level_id": "level_0",
	"collected_items": [],
	"player_health": 100.0,
	"player_stamina": 100.0,
	"inventory_items": []
}

func _ready() -> void:
	# Ensure the saves folder exists on launch
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)

# Get full file path for a given slot name
func get_slot_path(slot_name: String) -> String:
	return SAVE_DIR + slot_name + ".json"

# Save to a specific slot (or current_slot_name by default)
func save_game(slot_name: String = current_slot_name, save_title: String = "Save File", player: CharacterBody3D = null, level_seed: int = 0, level_id: String = "level_0") -> void:
	current_slot_name = slot_name

	if is_instance_valid(player):
		save_data["player_position"] = {
			"x": player.global_position.x,
			"y": player.global_position.y,
			"z": player.global_position.z
		}
		if "current_health" in Global:
			save_data["player_health"] = Global.current_health
		if "current_stamina" in Global:
			save_data["player_stamina"] = Global.current_stamina

	save_data["save_name"] = save_title
	save_data["timestamp"] = Time.get_unix_time_from_system()
	save_data["current_level_seed"] = level_seed
	save_data["current_level_id"] = level_id

	var path = get_slot_path(slot_name)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(save_data, "\t")
		file.store_string(json_string)
		file.close()
		print("Successfully saved to: ", path)

# Load a specific slot by name
func load_game(slot_name: String = current_slot_name) -> bool:
	var path = get_slot_path(slot_name)
	if not FileAccess.file_exists(path):
		print("Save slot does not exist: ", path)
		return false

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return false

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_text) == OK:
		save_data = json.data
		current_slot_name = slot_name
		print("Successfully loaded slot: ", slot_name)
		return true
	return false

# Scans user://saves/ and returns metadata for ALL save files (for UI selection)
func get_all_save_slots() -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	var dir = DirAccess.open(SAVE_DIR)

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				var slot_id = file_name.trim_suffix(".json")
				var file_path = SAVE_DIR + file_name

				# Peak into the JSON file to read title/timestamp
				var file = FileAccess.open(file_path, FileAccess.READ)
				if file:
					var json = JSON.new()
					if json.parse(file.get_as_text()) == OK:
						var data = json.data
						saves.append({
							"slot_id": slot_id,
							"title": data.get("save_name", slot_id),
							"timestamp": data.get("timestamp", 0),
							"level_id": data.get("current_level_id", "level_0")
						})
					file.close()
			file_name = dir.get_next()

	# Sort saves by newest timestamp first
	saves.sort_custom(func(a, b): return a["timestamp"] > b["timestamp"])
	return saves

# Delete a save slot
func delete_save_slot(slot_name: String) -> void:
	var path = get_slot_path(slot_name)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		print("Deleted save slot: ", slot_name)