extends AudioStreamPlayer3D

func _ready() -> void:
	# Connect the 'finished' signal to this node's _on_finished function
	finished.connect(_on_finished)

func _on_finished() -> void:
	# Replay this player
	play()
