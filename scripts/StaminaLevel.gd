extends Label

func _process(_delta: float) -> void:
	# Look for global singleton directly from the tree root
	var global_node = get_node_or_null("/root/Global")
	if not global_node:
		text = "Stamina: --%"
		return

	var current_val = global_node.get("current_stamina")
	var max_val = global_node.get("max_stamina")

	if current_val == null or max_val == null or max_val <= 0.0:
		text = "Stamina: 0%"
		return

	var percent := roundi((current_val / max_val) * 100.0)
	text = "Stamina: %d%%" % percent