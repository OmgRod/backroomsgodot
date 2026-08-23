extends Node3D

@export var open_angle: float = 90.0
@export var swing_speed: float = 0.5

@onready var panel: Node3D = $DoorPanel
@onready var audio_player: AudioStreamPlayer3D = $Audio as AudioStreamPlayer3D

# Preload sound streams
var sfx_open: AudioStream = preload("res://assets/sounds/doorOpen.mp3")
var sfx_close: AudioStream = preload("res://assets/sounds/doorClose.mp3")

var is_open: bool = false
var is_animating: bool = false

func interact() -> void:
	if is_animating:
		return

	is_animating = true
	is_open = !is_open

	# Play appropriate open/close sound effect
	_play_door_sound()

	var target_rot_y = deg_to_rad(open_angle) if is_open else 0.0

	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "rotation:y", target_rot_y, swing_speed)

	await tween.finished
	is_animating = false

func _play_door_sound() -> void:
	if is_instance_valid(audio_player):
		audio_player.stream = sfx_open if is_open else sfx_close
		audio_player.play()
