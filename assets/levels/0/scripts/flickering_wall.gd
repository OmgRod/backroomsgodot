extends Node3D

@export var level_1_scene: PackedScene = preload("res://assets/levels/1/level_1.tscn")

@onready var area: Area3D = $Area3D
var is_transitioning: bool = false
var meshes: Array = []

func _ready() -> void:
	if area:
		area.body_entered.connect(_on_body_entered)

	# Collect all mesh instances inside this wall
	meshes = find_children("*", "MeshInstance3D", true, false)

func _process(_delta: float) -> void:
	# Rapid visual flicker
	var should_show = randf() > 0.35
	for m in meshes:
		if m is MeshInstance3D:
			m.visible = should_show

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

	# Search up the tree for the root 'Game' node
	var game_node = get_tree().root.find_child("Game", true, false)
	if not game_node:
		game_node = get_tree().current_scene

	if game_node:
		# Locate current Level0 node
		var current_level = game_node.get_node_or_null("Level0")
		if not current_level:
			# Fallback: search for any existing level node
			for child in game_node.get_children():
				if "Level" in child.name:
					current_level = child
					break

		if current_level and level_1_scene:
			var parent = current_level.get_parent()
			var level_index = current_level.get_index()

			# Instantiate Level1
			var new_level = level_1_scene.instantiate()
			new_level.name = "Level1"

			# Remove Level0 and place Level1 in the exact same hierarchy index
			current_level.queue_free()
			parent.add_child(new_level)
			parent.move_child(new_level, level_index)

			# Reset player position to origin/spawn point
			if is_instance_valid(player):
				player.global_position = Vector3(1.0, 0.2, 1.0)
				player.velocity = Vector3.ZERO
		else:
			push_error("Could not complete noclip: Level0 or Level1 PackedScene missing!")

	# Brief pause before unfreezing player control
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(player) and "is_frozen" in player:
		player.is_frozen = false
