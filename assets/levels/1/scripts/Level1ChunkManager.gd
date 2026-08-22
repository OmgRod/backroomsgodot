extends Node3D

@export var player: CharacterBody3D

# Room Module Prefabs (12x12m)
@export var hall_room_scene: PackedScene = preload("res://assets/levels/1/chunks/base.tscn")
@export var corridor_room_scene: PackedScene
@export var wall_scene: PackedScene = preload("res://assets/levels/1/meshes/wall.tscn")

# Handcrafted POI Anchors
@export var base_alpha_scene: PackedScene
@export var traders_keep_scene: PackedScene
@export var hippocrates_1_scene: PackedScene
@export var cornucopia_scene: PackedScene
@export var registration_spot_scene: PackedScene
@export var toms_diner_scene: PackedScene

# Props & Objects
@export var crate_prop_scene: PackedScene

# Environmental Mechanics
@export var enable_blackout_events: bool = true

# Grid & Layout Parameters
const ROOM_SIZE: float = 12.0          # 12x12m Room Module Size
const MACRO_SIZE: int = 6               # Macro-Block Size (6x6 rooms = 72x72m)
const RENDER_DISTANCE: int = 4          # Room radius (9x9 grid loaded)
const LOD_0_DIST: int = 2               # Active collision radius
const WALL_HEIGHT: float = 4.0          # Level 1 Ceiling Height
const WALL_THICKNESS: float = 0.4       # Concrete Wall Thickness
const DOOR_WIDTH: float = 2.4           # Exit Doorway Opening Width
const BASE_LIGHT_ENERGY: float = 1.2

# Salts
const BASE_ALPHA_SALT: int = 11111
const TRADERS_KEEP_SALT: int = 22222
const DINER_SALT: int = 66666
const SHIFT_SALT: int = 77777

var SEED: int = int(Time.get_unix_time_from_system())

# Noise Generators
var sector_noise: FastNoiseLite

# State Tracking
var loaded_rooms: Dictionary = {}
var room_shift_versions: Dictionary = {}
var last_player_room: Vector2i = Vector2i(99999, 99999)

enum SectorType {
	AQUILA,    # Standard Parking Structure
	GILD,      # Storage Warehouse
	GOTHIC,    # Curved Arches & Round Pillars
	OUROBOROS, # Construction & Scaffolding
	GARDEN,    # Overgrown Mossy Concrete
	FABLED     # Antique Wood & Neon Cables
}

enum MacroBlockType {
	SINGLE_RECT_HALL,  # One clean rectangular parking hall
	JOINED_RECT_HALL,  # L-shaped double rectangular hall
	POI_COMPOUND,      # Base Alpha / Diner / Outpost
	CORRIDOR_MAZE      # Tight side corridor network & rooms
}

func _ready() -> void:
	sector_noise = FastNoiseLite.new()
	sector_noise.seed = SEED + 202
	sector_noise.frequency = 0.015

	_find_player()

	if is_instance_valid(player):
		update_rooms()
		if "is_frozen" in player:
			player.is_frozen = false

	register_console_commands()

func _find_player() -> void:
	if is_instance_valid(player):
		return

	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if not player and get_parent():
		player = get_parent().get_node_or_null("Player") as CharacterBody3D
	if not player:
		player = get_tree().root.find_child("Player", true, false) as CharacterBody3D

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		_find_player()
		if not is_instance_valid(player):
			return

	var current_room := Vector2i(
			floori(player.global_position.x / ROOM_SIZE),
			floori(player.global_position.z / ROOM_SIZE)
	)

	if current_room != last_player_room:
		last_player_room = current_room
		_apply_peripheral_shift(current_room)
		update_rooms()

	if "is_frozen" in player and player.is_frozen:
		player.is_frozen = false

# ==========================================
# SECTOR CLASSIFICATION
# ==========================================
func get_sector_at(coords: Vector2i) -> SectorType:
	var val = sector_noise.get_noise_2d(float(coords.x), float(coords.y))
	if val < -0.35:
		return SectorType.GARDEN
	elif val < -0.18:
		return SectorType.GOTHIC
	elif val < 0.0:
		return SectorType.AQUILA
	elif val < 0.20:
		return SectorType.GILD
	elif val < 0.38:
		return SectorType.OUROBOROS
	else:
		return SectorType.FABLED

# ==========================================
# MACRO-GRID RECTANGULAR LAYOUT ENGINE
# ==========================================
func get_chunk_layout_info(coords: Vector2i) -> Dictionary:
	# Keep origin chunk safe and open for player spawn
	if abs(coords.x) <= 1 and abs(coords.y) <= 1:
		return {
			"is_hall": true,
			"is_poi": false,
			"poi_type": "",
			"scene_type": "hall",
			"north_wall": false,
			"south_wall": false,
			"east_wall": false,
			"west_wall": false,
			"north_door": false,
			"south_door": false,
			"east_door": false,
			"west_door": false
		}

	# Calculate Macro-Block Coordinates (6x6 room grid = 72x72m)
	var macro_x = floori(float(coords.x) / float(MACRO_SIZE))
	var macro_z = floori(float(coords.y) / float(MACRO_SIZE))
	var macro_pos = Vector2i(macro_x, macro_z)

	var local_x = posmod(coords.x, MACRO_SIZE)
	var local_z = posmod(coords.y, MACRO_SIZE)

	var macro_hash = get_2d_hash(macro_pos.x, macro_pos.y, 99999)

	# Determine Macro-Block Structure
	var block_type = MacroBlockType.SINGLE_RECT_HALL
	if macro_hash < 0.08:
		block_type = MacroBlockType.POI_COMPOUND
	elif macro_hash < 0.45:
		block_type = MacroBlockType.JOINED_RECT_HALL
	elif macro_hash < 0.80:
		block_type = MacroBlockType.SINGLE_RECT_HALL
	else:
		block_type = MacroBlockType.CORRIDOR_MAZE

	# Define Even Rectangular Bounds within the 6x6 Macro Block
	var rect_1 = Rect2i(1, 1, 4, 4) # Standard 4x4 hall (48x48m)
	var rect_2 = Rect2i(1, 1, 0, 0) # Optional joined rectangle for L-shape

	if block_type == MacroBlockType.JOINED_RECT_HALL:
		rect_1 = Rect2i(1, 1, 4, 3)
		rect_2 = Rect2i(3, 4, 2, 2) # Attached joined rectangle
	elif block_type == MacroBlockType.POI_COMPOUND:
		rect_1 = Rect2i(1, 1, 3, 3)

	var local_p = Vector2i(local_x, local_z)
	var in_rect_1 = rect_1.has_point(local_p)
	var in_rect_2 = rect_2.has_point(local_p)
	var is_hall = in_rect_1 or in_rect_2

	if block_type == MacroBlockType.CORRIDOR_MAZE:
		is_hall = false

	# Wall Boundary Checking for Even Rectangles
	var n_wall = false
	var s_wall = false
	var e_wall = false
	var w_wall = false

	var n_door = false
	var s_door = false
	var e_door = false
	var w_door = false

	if is_hall:
		var half_r1_x = floori(float(rect_1.size.x) * 0.5)
		var half_r1_z = floori(float(rect_1.size.y) * 0.5)

		# Check North edge
		if not rect_1.has_point(local_p + Vector2i(0, -1)) and not rect_2.has_point(local_p + Vector2i(0, -1)):
			n_wall = true
			if local_x == rect_1.position.x + half_r1_x:
				n_door = true # Center doorway exit to side corridors

		# Check South edge
		if not rect_1.has_point(local_p + Vector2i(0, 1)) and not rect_2.has_point(local_p + Vector2i(0, 1)):
			s_wall = true
			if local_x == rect_1.position.x + half_r1_x:
				s_door = true

		# Check West edge
		if not rect_1.has_point(local_p + Vector2i(-1, 0)) and not rect_2.has_point(local_p + Vector2i(-1, 0)):
			w_wall = true
			if local_z == rect_1.position.y + half_r1_z:
				w_door = true

		# Check East edge
		if not rect_1.has_point(local_p + Vector2i(1, 0)) and not rect_2.has_point(local_p + Vector2i(1, 0)):
			e_wall = true
			if local_z == rect_1.position.y + half_r1_z:
				e_door = true

	# Check Major POI Spawns inside POI Macro Compounds
	var poi_type = ""
	if block_type == MacroBlockType.POI_COMPOUND and local_x == 2 and local_z == 2:
		var poi_hash = get_2d_hash(macro_pos.x, macro_pos.y, 888)
		if poi_hash < 0.30:
			poi_type = "base_alpha"
		elif poi_hash < 0.60:
			poi_type = "traders_keep"
		else:
			poi_type = "diner"

	return {
		"is_hall": is_hall,
		"poi_type": poi_type,
		"north_wall": n_wall,
		"south_wall": s_wall,
		"east_wall": e_wall,
		"west_wall": w_wall,
		"north_door": n_door,
		"south_door": s_door,
		"east_door": e_door,
		"west_door": w_door
	}

# ==========================================
# PERIPHERAL SHIFT SYSTEM
# ==========================================
func _apply_peripheral_shift(player_room: Vector2i) -> void:
	if not is_instance_valid(player) or not player.has_method("get_camera_forward"):
		return

	var cam_forward: Vector3 = player.get_camera_forward()
	cam_forward.y = 0
	cam_forward = cam_forward.normalized()

	var cam_pos: Vector3 = player.get_camera_position()

	var keys = loaded_rooms.keys()
	for coords in keys:
		var room_center = Vector3(coords.x * ROOM_SIZE + (ROOM_SIZE * 0.5), 0.0, coords.y * ROOM_SIZE + (ROOM_SIZE * 0.5))
		var dir_to_room = (room_center - cam_pos).normalized()
		dir_to_room.y = 0

		if cam_forward.dot(dir_to_room) < -0.4 and coords.distance_squared_to(player_room) > 4:
			if get_2d_hash(coords.x, coords.y, SHIFT_SALT + int(Time.get_ticks_msec() / 12000)) < 0.12:
				var current_v = room_shift_versions.get(coords, 0)
				room_shift_versions[coords] = current_v + 1
				despawn_room(coords)

# ==========================================
# ROOM LIFECYCLE & SPAWNING
# ==========================================
func update_rooms() -> void:
	var player_room := last_player_room
	var needed_rooms: Array[Vector2i] = []

	for x in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
		for z in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
			needed_rooms.append(Vector2i(player_room.x + x, player_room.y + z))

	needed_rooms.sort_custom(func(a: Vector2i, b: Vector2i):
		return a.distance_squared_to(player_room) < b.distance_squared_to(player_room)
	)

	for coords in needed_rooms:
		var horizontal_dist = max(abs(coords.x - player_room.x), abs(coords.y - player_room.y))
		var enable_collision = horizontal_dist <= LOD_0_DIST

		if not loaded_rooms.has(coords):
			spawn_room(coords, enable_collision)
		else:
			update_room_collision_state(loaded_rooms[coords], enable_collision)

	var existing_coords = loaded_rooms.keys()
	for coords in existing_coords:
		if not coords in needed_rooms:
			despawn_room(coords)

func spawn_room(coords: Vector2i, enable_collision: bool) -> void:
	var layout = get_chunk_layout_info(coords)
	var sector = get_sector_at(coords)
	var instance: Node3D

	var poi_type: String = layout.get("poi_type", "")

	# 1. POI Rooms
	if poi_type != "":
		match poi_type:
			"base_alpha":
				instance = base_alpha_scene.instantiate() if base_alpha_scene else hall_room_scene.instantiate()
			"traders_keep":
				instance = traders_keep_scene.instantiate() if traders_keep_scene else hall_room_scene.instantiate()
			"diner":
				instance = toms_diner_scene.instantiate() if toms_diner_scene else hall_room_scene.instantiate()
	# 2. Open Parking Halls
	elif layout.get("is_hall", false):
		if hall_room_scene:
			instance = hall_room_scene.instantiate()
		else:
			push_error("Hall Room Scene is missing on ChunkManager Inspector!")
			return
	# 3. Side Corridors
	else:
		if corridor_room_scene:
			instance = corridor_room_scene.instantiate()
		elif hall_room_scene:
			instance = hall_room_scene.instantiate()

	if not instance:
		return

	add_child(instance)

	var world_x = coords.x * ROOM_SIZE
	var world_z = coords.y * ROOM_SIZE
	instance.global_position = Vector3(world_x, 0.0, world_z)

	# Build perimeter concrete walls around the rectangular halls
	if layout.get("is_hall", false) and poi_type == "":
		_construct_hall_boundary_walls(instance, layout, enable_collision)

	_apply_sector_styling(instance, sector)
	_try_spawn_crate_props(instance, coords, sector)
	_apply_room_lighting(instance, coords)

	update_room_collision_state(instance, enable_collision)
	loaded_rooms[coords] = instance

# ==========================================
# RECTANGULAR HALL BOUNDARY WALL BUILDER
# ==========================================
func _construct_hall_boundary_walls(chunk_node: Node3D, layout: Dictionary, enable_collision: bool) -> void:
	var wall_h = WALL_HEIGHT * 0.5
	var half_s = ROOM_SIZE * 0.5

	# Corner Pillar Sealer to prevent leaks
	if layout.get("north_wall", false) or layout.get("west_wall", false) or layout.get("south_wall", false) or layout.get("east_wall", false):
		spawn_wall_box(chunk_node, Vector3(0, wall_h, 0), Vector3(1.0, WALL_HEIGHT, 1.0), enable_collision)
		spawn_wall_box(chunk_node, Vector3(ROOM_SIZE, wall_h, 0), Vector3(1.0, WALL_HEIGHT, 1.0), enable_collision)
		spawn_wall_box(chunk_node, Vector3(0, wall_h, ROOM_SIZE), Vector3(1.0, WALL_HEIGHT, 1.0), enable_collision)
		spawn_wall_box(chunk_node, Vector3(ROOM_SIZE, wall_h, ROOM_SIZE), Vector3(1.0, WALL_HEIGHT, 1.0), enable_collision)

	# North Wall
	if layout.get("north_wall", false):
		_build_wall_face(chunk_node, Vector3(half_s, wall_h, 0.0), Vector3(ROOM_SIZE, WALL_HEIGHT, WALL_THICKNESS), layout.get("north_door", false), true, enable_collision)

	# South Wall
	if layout.get("south_wall", false):
		_build_wall_face(chunk_node, Vector3(half_s, wall_h, ROOM_SIZE), Vector3(ROOM_SIZE, WALL_HEIGHT, WALL_THICKNESS), layout.get("south_door", false), true, enable_collision)

	# West Wall
	if layout.get("west_wall", false):
		_build_wall_face(chunk_node, Vector3(0.0, wall_h, half_s), Vector3(WALL_THICKNESS, WALL_HEIGHT, ROOM_SIZE), layout.get("west_door", false), false, enable_collision)

	# East Wall
	if layout.get("east_wall", false):
		_build_wall_face(chunk_node, Vector3(ROOM_SIZE, wall_h, half_s), Vector3(WALL_THICKNESS, WALL_HEIGHT, ROOM_SIZE), layout.get("east_door", false), false, enable_collision)

func _build_wall_face(chunk_node: Node3D, pos: Vector3, size: Vector3, is_doorway: bool, is_horizontal: bool, enable_collision: bool) -> void:
	if not is_doorway:
		spawn_wall_box(chunk_node, pos, size, enable_collision)
	else:
		# Wall with doorway exit cutout
		var side_w = (ROOM_SIZE - DOOR_WIDTH) * 0.5
		var header_h = 1.2
		var header_y = WALL_HEIGHT - (header_h * 0.5)

		if is_horizontal:
			var p1 = pos + Vector3(-ROOM_SIZE * 0.5 + side_w * 0.5, 0, 0)
			var p2 = pos + Vector3(ROOM_SIZE * 0.5 - side_w * 0.5, 0, 0)
			var p_head = Vector3(pos.x, header_y, pos.z)

			spawn_wall_box(chunk_node, p1, Vector3(side_w, WALL_HEIGHT, WALL_THICKNESS), enable_collision)
			spawn_wall_box(chunk_node, p2, Vector3(side_w, WALL_HEIGHT, WALL_THICKNESS), enable_collision)
			spawn_wall_box(chunk_node, p_head, Vector3(DOOR_WIDTH, header_h, WALL_THICKNESS), enable_collision)
		else:
			var p1 = pos + Vector3(0, 0, -ROOM_SIZE * 0.5 + side_w * 0.5)
			var p2 = pos + Vector3(0, 0, ROOM_SIZE * 0.5 - side_w * 0.5)
			var p_head = Vector3(pos.x, header_y, pos.z)

			spawn_wall_box(chunk_node, p1, Vector3(WALL_THICKNESS, WALL_HEIGHT, side_w), enable_collision)
			spawn_wall_box(chunk_node, p2, Vector3(WALL_THICKNESS, WALL_HEIGHT, side_w), enable_collision)
			spawn_wall_box(chunk_node, p_head, Vector3(WALL_THICKNESS, header_h, DOOR_WIDTH), enable_collision)

func spawn_wall_box(parent_chunk: Node3D, local_pos: Vector3, dimensions: Vector3, enable_collision: bool) -> void:
	var wall_instance: Node3D

	if wall_scene:
		wall_instance = wall_scene.instantiate() as Node3D
	else:
		wall_instance = Node3D.new()

	parent_chunk.add_child(wall_instance)
	wall_instance.position = local_pos

	# Mesh Setup
	var mesh_node = wall_instance.find_child("*MeshInstance3D*", true, false) as MeshInstance3D
	if not mesh_node and wall_instance is MeshInstance3D:
		mesh_node = wall_instance as MeshInstance3D

	if not mesh_node:
		mesh_node = MeshInstance3D.new()
		wall_instance.add_child(mesh_node)

	var box_mesh: BoxMesh
	if mesh_node.mesh is BoxMesh:
		box_mesh = mesh_node.mesh.duplicate() as BoxMesh
	else:
		box_mesh = BoxMesh.new()

	box_mesh.size = dimensions
	mesh_node.mesh = box_mesh

	# Collision Setup
	var col_shape = wall_instance.find_child("*CollisionShape3D*", true, false) as CollisionShape3D
	if not col_shape:
		var static_body = wall_instance if wall_instance is StaticBody3D else wall_instance.find_child("*StaticBody3D*", true, false) as StaticBody3D
		if not static_body:
			static_body = StaticBody3D.new()
			wall_instance.add_child(static_body)
		col_shape = CollisionShape3D.new()
		static_body.add_child(col_shape)

	var box_shape: BoxShape3D
	if col_shape.shape is BoxShape3D:
		box_shape = col_shape.shape.duplicate() as BoxShape3D
	else:
		box_shape = BoxShape3D.new()

	box_shape.size = dimensions
	col_shape.shape = box_shape
	col_shape.disabled = not enable_collision

# ==========================================
# SECTOR STYLING & PROPS
# ==========================================
func _apply_sector_styling(room_node: Node3D, sector: SectorType) -> void:
	match sector:
		SectorType.AQUILA:
			room_node.set_meta("sector_name", "Aquila")
		SectorType.GILD:
			room_node.set_meta("sector_name", "Gild")
		SectorType.GOTHIC:
			room_node.set_meta("sector_name", "Gothic")
		SectorType.OUROBOROS:
			room_node.set_meta("sector_name", "Ouroboros")
		SectorType.GARDEN:
			room_node.set_meta("sector_name", "Garden")
		SectorType.FABLED:
			room_node.set_meta("sector_name", "Fabled")

func _try_spawn_crate_props(room_node: Node3D, coords: Vector2i, sector: SectorType) -> void:
	if not crate_prop_scene:
		return

	var crate_chance = 0.65 if sector == SectorType.GILD else 0.20
	if get_2d_hash(coords.x, coords.y, 8888) < crate_chance:
		var crate = crate_prop_scene.instantiate() as Node3D
		room_node.add_child(crate)
		crate.position = Vector3(
				(randf() - 0.5) * (ROOM_SIZE - 2.0),
				0.4,
				(randf() - 0.5) * (ROOM_SIZE - 2.0)
		)

func _apply_room_lighting(room_node: Node3D, coords: Vector2i) -> void:
	var lights = room_node.find_children("*", "Light3D", true, false)
	var is_blackout = enable_blackout_events and (get_2d_hash(coords.x, coords.y, 777) < 0.10)
	var is_flicker_room = enable_blackout_events and not is_blackout and (get_2d_hash(coords.x, coords.y, 999) < 0.20)

	for light in lights:
		if light is Light3D:
			if is_blackout:
				light.light_energy = 0.0
				light.visible = false
			elif is_flicker_room:
				light.visible = true
				light.light_energy = BASE_LIGHT_ENERGY * (0.1 + randf() * 0.6)
			else:
				light.visible = true
				light.light_energy = BASE_LIGHT_ENERGY

func update_room_collision_state(room_node: Node3D, enable_collision: bool) -> void:
	var col_shapes = room_node.find_children("*", "CollisionShape3D", true, false)
	for col in col_shapes:
		if col is CollisionShape3D:
			col.disabled = not enable_collision

func despawn_room(coords: Vector2i) -> void:
	if loaded_rooms.has(coords):
		var instance = loaded_rooms[coords]
		loaded_rooms.erase(coords)
		if is_instance_valid(instance):
			instance.queue_free()

func get_2d_hash(x: int, z: int, salt: int = 0) -> float:
	var shift_v = room_shift_versions.get(Vector2i(x, z), 0)
	var h = x * 374761393 + z * 2147483647 + SEED + salt + (shift_v * 982451653)
	h = (h ^ (h >> 13)) * 1274126177
	return float(h & 0x7FFFFFFF) / float(0x7FFFFFFF)

# ==========================================
# WALKABILITY VALIDATION FOR RESPAWN/SPAWN
# ==========================================
func is_room_walkable(_coords: Vector2i) -> bool:
	return true

# ==========================================
# CONSOLE COMMAND SYSTEM
# ==========================================
func register_console_commands() -> void:
	var console_node = get_node_or_null("/root/Console")
	if console_node:
		console_node.add_command("locate", _cmd_locate, 1)
		var locate_targets = ["player", "base_alpha", "traders_keep", "diner"]
		console_node.add_command_autocomplete_list("locate", locate_targets)

func _cmd_locate(target_name: String) -> void:
	var console_node = get_node_or_null("/root/Console")
	if not console_node:
		return

	target_name = target_name.to_lower().strip_edges()

	match target_name:
		"player":
			if is_instance_valid(player):
				var pos = player.global_position
				console_node.print_line("Player location: (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z])
			else:
				console_node.print_line("Error: Player node not found.")
		"base_alpha":
			_locate_nearest_poi(console_node, BASE_ALPHA_SALT, "Base Alpha")
		"traders_keep":
			_locate_nearest_poi(console_node, TRADERS_KEEP_SALT, "Trader's Keep")
		"diner":
			_locate_nearest_poi(console_node, DINER_SALT, "Tom's Diner")
		_:
			console_node.print_line("Unknown target. Options: player, base_alpha, traders_keep, diner")

func _locate_nearest_poi(console_node: Node, poi_salt: int, poi_name: String) -> void:
	var start_pos = player.global_position if is_instance_valid(player) else global_position

	var current_room_x = floori(start_pos.x / ROOM_SIZE)
	var current_room_z = floori(start_pos.z / ROOM_SIZE)

	var nearest_pos := Vector3.ZERO
	var shortest_dist_sq := INF
	var search_radius := 100

	for rx in range(current_room_x - search_radius, current_room_x + search_radius + 1):
		for rz in range(current_room_z - search_radius, current_room_z + search_radius + 1):
			if get_2d_hash(rx, rz, poi_salt) < 0.002:
				var poi_world_pos = Vector3(
						(rx * ROOM_SIZE) + (ROOM_SIZE * 0.5),
						0.0,
						(rz * ROOM_SIZE) + (ROOM_SIZE * 0.5)
				)

				var dist_sq = start_pos.distance_squared_to(poi_world_pos)
				if dist_sq < shortest_dist_sq:
					shortest_dist_sq = dist_sq
					nearest_pos = poi_world_pos

	if shortest_dist_sq != INF:
		var distance = sqrt(shortest_dist_sq)
		console_node.print_line(
				"Nearest %s found at: (X: %.1f, Y: 0.0, Z: %.1f) [~%.1fm away]" % [
					poi_name,
					nearest_pos.x,
					nearest_pos.z,
					distance
				]
		)
	else:
		console_node.print_line("No %s found within search range." % poi_name)

func _exit_tree() -> void:
	if Engine.has_singleton("Console") or get_tree().root.has_node("Console"):
		var console_node = get_node_or_null("/root/Console")
		if console_node and console_node.has_method("remove_command"):
			console_node.remove_command("locate")
