extends AudioStreamPlayer3D

## Array of sound effects to randomly pick from
@export var sound_effects: Array[AudioStream] = []

## Minimum and maximum wait times in seconds
@export var min_wait_time: float = 30.0
@export var max_wait_time: float = 300.0

func _ready() -> void:
	# Ensure the player isn't set to loop automatically
	autoplay = false

	# Start the ambient sound loop
	schedule_next_sound()

func schedule_next_sound() -> void:
	# Pick a random delay between min and max wait times
	var wait_time: float = randf_range(min_wait_time, max_wait_time)

	# Create a one-shot timer using scene tree timer
	await get_tree().create_timer(wait_time).timeout

	play_random_sound()

func play_random_sound() -> void:
	# Check if we have sound streams assigned
	if sound_effects.size() > 0:
		# Pick a random sound from the array
		stream = sound_effects.pick_random()
		play()

		# Wait for the sound to finish playing before scheduling the next timer
		await finished
	elif stream != null:
		# If no array is set, fallback to whatever single stream is pre-set on this node
		play()
		await finished

	# Loop back to schedule the next sound
	schedule_next_sound()