extends MeshInstance3D

@export var level_1_scene: PackedScene = preload("res://assets/levels/1/level_1.tscn")

@onready var area_3d: Area3D = $Area3D if has_node("Area3D") else find_child("Area3D", true, false) as Area3D

var active_material: StandardMaterial3D
var flicker_timer: float = 0.0
var next_flicker_interval: float = 0.0
var is_transitioning: bool = false

func _ready() -> void:
	if area_3d:
		area_3d.body_entered.connect(_on_body_entered)
	else:
		push_warning("FlickeringWall: Child Area3D node not found!")

	# Make the material unique to this specific wall instance so it doesn't share state globally
	if material_override:
		active_material = material_override.duplicate() as StandardMaterial3D
		material_override = active_material
	elif mesh and mesh.material:
		active_material = mesh.material.duplicate() as StandardMaterial3D
		mesh.material = active_material

	_reset_flicker_timer()

func _process(delta: float) -> void:
	flicker_timer += delta
	if flicker_timer >= next_flicker_interval:
		_reset_flicker_timer()
		
		# Toggle visibility and alpha variation for a classic Backrooms glitch effect
		# (Adjusted threshold slightly to be safer and less blindingly rapid)
		var should_be_visible = randf() > 0.15
		visible = should_be_visible
		
		if active_material and should_be_visible:
			active_material.albedo_color.a = randf_range(0.4, 1.0)

func _reset_flicker_timer() -> void:
	flicker_timer = 0.0
	# Slightly wider interval bounds keep it erratic yet smooth on the eyes
	next_flicker_interval = randf_range(0.08, 0.25)

func _on_body_entered(body: Node3D) -> void:
	if is_transitioning:
		return

	if body.is_in_group("player") or body is CharacterBody3D:
		is_transitioning = true
		noclip_transition_to_level_1()

func noclip_transition_to_level_1() -> void:
	var player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if is_instance_valid(player) and "is_frozen" in player:
		player.is_frozen = true

	var game_node = get_tree().root.find_child("Game", true, false)
	if not game_node:
		game_node = get_tree().current_scene

	if game_node:
		var current_level = game_node.get_node_or_null("Level0")
		if not current_level:
			for child in game_node.get_children():
				if "Level" in child.name:
					current_level = child
					break

		if current_level and level_1_scene:
			var parent = current_level.get_parent()
			var level_index = current_level.get_index()

			var new_level = level_1_scene.instantiate()
			new_level.name = "Level1"

			current_level.queue_free()
			parent.add_child(new_level)
			parent.move_child(new_level, level_index)

			if is_instance_valid(player):
				player.global_position = Vector3(1.0, 0.2, 1.0)
				player.velocity = Vector3.ZERO
		else:
			push_error("Could not complete noclip: Level0 or Level1 PackedScene missing!")

	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(player) and "is_frozen" in player:
		player.is_frozen = false
