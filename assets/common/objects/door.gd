extends Node3D

@export var open_angle: float = 90.0
@export var swing_speed: float = 0.5

@onready var panel: Node3D = $DoorPanel

var is_open: bool = false
var is_animating: bool = false

func interact() -> void:
	if is_animating:
		return

	is_animating = true
	is_open = !is_open

	var target_rot_y = deg_to_rad(open_angle) if is_open else 0.0

	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "rotation:y", target_rot_y, swing_speed)

	await tween.finished
	is_animating = false
