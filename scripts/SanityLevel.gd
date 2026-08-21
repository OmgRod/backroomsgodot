extends Label

func _ready() -> void:
	# Connect to Global stamina signal
	if Global.has_signal("stamina_changed"):
		Global.stamina_changed.connect(_on_stamina_changed)
		# Initialize display immediately
		_on_stamina_changed(Global.current_stamina, Global.max_stamina)
	else:
		text = "Stamina: --%"

func _on_stamina_changed(current_val: float, max_val: float) -> void:
	if max_val <= 0.0:
		text = "Stamina: 0%"
		return

	# Calculate percentage and convert to integer
	var percent := roundi((current_val / max_val) * 100.0)
	text = "Stamina: %d%%" % percent
