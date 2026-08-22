extends Area3D

@export_file("*.tscn") var level_1_path: String = "res://assets/levels/1/level_1.tscn"

var has_triggered: bool = false

func _ready() -> void:
	# Programmatically connect the signal in case it isn't wired in the editor
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not has_triggered:
		has_triggered = true

		# Run the progressive bad-luck check from Global.gd
		var takes_to_level_1: bool = Global.check_pitfall_noclip()

		# Trigger screen glitch on player if camera function exists
		if body.has_method("set_vhs_glitch"):
			body.set_vhs_glitch(0.03)

		if takes_to_level_1:
			# SUCCESS: Glitch transition to Level 1
			await get_tree().create_timer(1.2).timeout
			get_tree().change_scene_to_file(level_1_path)
		# otherwise player goes down as usual
