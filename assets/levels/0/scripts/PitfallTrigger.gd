extends Area3D

@export_file("*.tscn") var level_1_path: String = "res://assets/levels/1/level_1.tscn"

func _ready() -> void:
	var col_shape = find_child("CollisionShape3D", true, false) as CollisionShape3D
	if not col_shape:
		col_shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(3.8, 6.0, 3.8)
		col_shape.shape = box
		col_shape.position = Vector3(0.0, -2.0, 0.0)
		add_child(col_shape)

	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not Global.is_dead:
		var takes_to_level_1: bool = Global.check_pitfall_noclip()

		if body.has_method("set_vhs_glitch"):
			body.set_vhs_glitch(0.03)

		if takes_to_level_1:
			await get_tree().create_timer(1.2).timeout
			get_tree().change_scene_to_file(level_1_path)
		else:
			if Global.has_method("trigger_death_sequence"):
				Global.trigger_death_sequence("pitfall")
