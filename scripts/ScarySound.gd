extends AudioStreamPlayer3D

@export var chunk_manager: Node3D
@export var player: CharacterBody3D

## Array of sound effects to randomly pick from
@export var sound_effects: Array[AudioStream] = []

## Minimum and maximum wait times in seconds
@export var min_wait_time: float = 30.0
@export var max_wait_time: float = 300.0

func _ready() -> void:
	autoplay = false
	_find_references()
	schedule_next_sound()

func _find_references() -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		if not player and get_parent():
			player = get_parent().get_node_or_null("Player") as CharacterBody3D

	if not is_instance_valid(chunk_manager):
		chunk_manager = get_node_or_null("../ChunkManager") as Node3D

func schedule_next_sound() -> void:
	var wait_time: float = randf_range(min_wait_time, max_wait_time)
	await get_tree().create_timer(wait_time).timeout
	play_random_sound()

func play_random_sound() -> void:
	_find_references()

	if is_instance_valid(chunk_manager) and is_instance_valid(player):
		var player_chunk = Vector2i(
				floori(player.global_position.x / chunk_manager.CHUNK_SIZE),
				floori(player.global_position.z / chunk_manager.CHUNK_SIZE)
		)

		# DO NOT play whispers inside the Manila Room
		if chunk_manager.is_in_manila_6x6_zone(player_chunk):
			schedule_next_sound()
			return

		# Move audio player node to a random 3D spot around the player
		var random_offset = Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
		global_position = player.global_position + random_offset

	# Pick and play sound
	if sound_effects.size() > 0:
		stream = sound_effects.pick_random()
		play()
		await finished
	elif stream != null:
		play()
		await finished

	# Loop back for next trigger
	schedule_next_sound()