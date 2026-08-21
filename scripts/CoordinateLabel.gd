extends Label

var player: Node3D

func _ready() -> void:
	# 1. Try finding Player by relative path from the Game root scene
	player = get_node_or_null("/root/Game/Level0/Player")
	
	# 2. Fallback: Search by "player" group if the path differs
	if not player:
		player = get_tree().get_first_node_in_group("player") as Node3D

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		text = "--, --, --"
		return

	# Fetch position rounded to nearest meter
	var pos := player.global_position
	var x := roundi(pos.x)
	var y := roundi(pos.y)
	var z := roundi(pos.z)

	# Update label display
	text = "%d, %d, %d" % [x, y, z]
