extends Node3D

func _ready() -> void:
	set_random_camera()

func set_random_camera() -> void:
	var cameras: Array[Camera3D] = []
	
	# Find all child Camera3D nodes
	for child in get_children():
		if child is Camera3D:
			cameras.append(child)
			
	# Pick a random camera and make it current
	if cameras.size() > 0:
		var random_cam = cameras.pick_random()
		random_cam.make_current()
	else:
		push_warning("No Camera3D child nodes found under " + name)
