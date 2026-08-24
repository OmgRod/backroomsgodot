extends Node3D

@export var player: CharacterBody3D

# Room Module Prefabs (12x12m)
@export var hall_room_scene: PackedScene = preload("res://assets/levels/1/chunks/base.tscn")
@export var corridor_room_scene: PackedScene
@export var wall_scene: PackedScene = preload("res://assets/levels/1/meshes/wall.tscn")

# Sector Specific Landmarks / Props
@export var gothic_pillar_scene: PackedScene = preload("res://assets/levels/1/meshes/gothic_pillar.tscn")
@export var ouroboros_pipes_scene: PackedScene = preload("res://assets/levels/1/meshes/ouroboros_pipes.tscn")
@export var garden_foliage_scene: PackedScene = preload("res://assets/levels/1/meshes/garden_foliage.tscn")
@export var fabled_wood_wall_scene: PackedScene = preload("res://assets/levels/1/meshes/fabled_wood_wall.tscn")

# Lore-Accurate Settlement Landmarks (POIs)
@export var base_alpha_scene: PackedScene = preload("res://assets/levels/1/chunks/base_alpha.tscn")            # Aquila Sector (3x3)
@export var traders_keep_scene: PackedScene = preload("res://assets/levels/1/chunks/traders_keep.tscn")        # Gild Sector (3x3)
@export var hippocrates_1_scene: PackedScene = preload("res://assets/levels/1/chunks/hippocrates_1.tscn")      # Gothic Sector (3x3)
@export var cornucopia_scene: PackedScene = preload("res://assets/levels/1/chunks/cornucopia.tscn")            # Ouroboros Sector (3x3)
@export var registration_spot_scene: PackedScene = preload("res://assets/levels/1/chunks/registration_spot.tscn") # Garden Sector (2x2)
@export var toms_diner_scene: PackedScene = preload("res://assets/levels/1/chunks/toms_diner.tscn")            # Fabled Sector (3x3)

# Level 1 Specific Props (Supply Crates / Storage Loot)
@export var crate_prop_scene: PackedScene = preload("res://assets/levels/1/meshes/crate/crate.tscn")

# Environmental Mechanics
@export var enable_blackout_events: bool = true

# Grid Configuration (12x12m Room Chunks)
const ROOM_SIZE: float = 12.0
const MACRO_SIZE: int = 6             # Macro-Block Size (6x6 rooms = 72x72m)
const RENDER_DISTANCE: int = 4        # Room radius loaded around player
const LOD_0_DIST: int = 2             # Active collision radius
const WALL_HEIGHT: float = 4.0        # Level 1 Concrete Ceiling Height
const WALL_THICKNESS: float = 0.4     # Concrete Wall Thickness
const CORRIDOR_WIDTH: float = 4.0     # Procedural corridor width
const BASE_LIGHT_ENERGY: float = 1.2

const SHIFT_SALT: int = 77777

var SEED: int = int(Time.get_unix_time_from_system())

# Noise Generators for Layout and Sectors
var layout_noise: FastNoiseLite
var sector_noise: FastNoiseLite
var hallway_noise: FastNoiseLite

# State Tracking
var loaded_rooms: Dictionary = {}
var room_shift_versions: Dictionary = {}
var last_player_room: Vector2i = Vector2i(99999, 99999)

# Official Level 1 Sectors
enum SectorType {
	AQUILA,    # Concrete parking lot style (Base Alpha)
	GILD,      # Warehouse storage style (Trader's Keep & Crates)
	Gothic,    # Arched circular pillars (Hippocrates-1)
	OUROBOROS, # Construction zone & exposed pipes (Camp Cornucopia)
	GARDEN,    # Overgrown green mossy zone (Registration Spots)
	FABLED     # Antique wood & altered corridors (Tom's Diner)
}

func _ready() -> void:
	layout_noise = FastNoiseLite.new()
	layout_noise.seed = SEED + 300
	layout_noise.frequency = 0.10

	hallway_noise = FastNoiseLite.new()
	hallway_noise.seed = SEED + 450
	hallway_noise.frequency = 0.28 # Controls webbing of procedural corridor routes

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
# SECTOR CLASSIFICATION SYSTEM
# ==========================================
func get_sector_at(coords: Vector2i) -> SectorType:
	var val = sector_noise.get_noise_2d(float(coords.x), float(coords.y))
	if val < -0.35:
		return SectorType.GARDEN
	elif val < -0.18:
		return SectorType.Gothic
	elif val < 0.0:
		return SectorType.AQUILA
	elif val < 0.20:
		return SectorType.GILD
	elif val < 0.38:
		return SectorType.OUROBOROS
	else:
		return SectorType.FABLED

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
		if is_in_poi_zone(coords):
			continue

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

# ==========================================
# SECTOR-LOCKED LANDMARK / POI LOGIC
# ==========================================
func get_macro_poi_info(macro_x: int, macro_z: int) -> Dictionary:
	var hash_val = get_2d_hash(macro_x, macro_z, 7777)

	# FIXED: POIs now have an 85% chance to spawn instead of 22%, populating the world with actual landmarks!
	if hash_val > 0.85:
		return {"type": "", "size": 0}

	var sample_coords = Vector2i(macro_x * MACRO_SIZE + 2, macro_z * MACRO_SIZE + 2)
	var sector = get_sector_at(sample_coords)

	match sector:
		SectorType.AQUILA:
			if base_alpha_scene: return {"type": "base_alpha", "size": 3}
		SectorType.GILD:
			if traders_keep_scene: return {"type": "traders_keep", "size": 3}
		SectorType.Gothic:
			if hippocrates_1_scene: return {"type": "hippocrates_1", "size": 3}
		SectorType.OUROBOROS:
			if cornucopia_scene: return {"type": "cornucopia", "size": 3}
		SectorType.GARDEN:
			if registration_spot_scene: return {"type": "registration_spot", "size": 2}
		SectorType.FABLED:
			if toms_diner_scene: return {"type": "diner", "size": 3}

	return {"type": "", "size": 0}

func get_poi_data_for_room(coords_2d: Vector2i) -> Dictionary:
	var macro_x = floori(float(coords_2d.x) / float(MACRO_SIZE))
	var macro_z = floori(float(coords_2d.y) / float(MACRO_SIZE))

	for mx in range(macro_x - 1, macro_x + 1):
		for mz in range(macro_z - 1, macro_z + 1):
			var info = get_macro_poi_info(mx, mz)
			if info["type"] != "":
				var base_x = (mx * MACRO_SIZE) + 1
				var base_z = (mz * MACRO_SIZE) + 1
				var size = info["size"]

				if coords_2d.x >= base_x and coords_2d.x < base_x + size and \
						coords_2d.y >= base_z and coords_2d.y < base_z + size:
					return {
						"type": info["type"],
						"is_anchor": (coords_2d.x == base_x and coords_2d.y == base_z)
					}
	return {"type": "", "is_anchor": false}

func is_in_poi_zone(coords_2d: Vector2i) -> bool:
	return get_poi_data_for_room(coords_2d)["type"] != ""

func spawn_room(coords: Vector2i, enable_collision: bool) -> void:
	var sector = get_sector_at(coords)
	var poi_data = {"type": "", "is_anchor": false}
	if abs(coords.x) > 1 or abs(coords.y) > 1:
		poi_data = get_poi_data_for_room(coords)

	var instance: Node3D
	var is_corridor = false
	var is_poi_room = (poi_data["type"] != "")

	if is_poi_room:
		if poi_data["is_anchor"]:
			match poi_data["type"]:
				"base_alpha": instance = base_alpha_scene.instantiate()
				"traders_keep": instance = traders_keep_scene.instantiate()
				"hippocrates_1": instance = hippocrates_1_scene.instantiate()
				"cornucopia": instance = cornucopia_scene.instantiate()
				"registration_spot": instance = registration_spot_scene.instantiate()
				"diner": instance = toms_diner_scene.instantiate()
				_: instance = hall_room_scene.instantiate()
		else:
			instance = Node3D.new()
	else:
		is_corridor = abs(hallway_noise.get_noise_2d(float(coords.x), float(coords.y))) > 0.40
		if is_corridor and corridor_room_scene:
			instance = corridor_room_scene.instantiate()
		else:
			instance = hall_room_scene.instantiate() if hall_room_scene else Node3D.new()

	add_child(instance)

	var world_x = coords.x * ROOM_SIZE
	var world_z = coords.y * ROOM_SIZE
	instance.global_position = Vector3(world_x, 0.0, world_z)

	# FIXED: Only skip procedural *walls* if using a pre-made room/POI, but ALWAYS allow sector landmarks (pipes, foliage, etc.) to spawn!
	if not is_poi_room:
		if is_corridor and not corridor_room_scene:
			_generate_procedural_corridor(instance, coords, enable_collision)
		else:
			# This handles internal layout walls if needed, while letting landmarks spawn
			_generate_sector_geometry(instance, coords, enable_collision, sector)

	# Always allow supply crates and sector landmarks in standard non-POI rooms
	if poi_data["type"] == "":
		_try_spawn_supply_crates(instance, coords, sector)
		# Explicitly guarantee sector landmarks spawn in standard rooms
		_spawn_sector_landmarks(instance, coords, sector)

	_apply_sector_styling(instance, sector)
	_apply_room_lighting(instance, coords)
	update_room_collision_state(instance, enable_collision)
	loaded_rooms[coords] = instance

# Helper function cleaned up so it doesn't suppress sector landmarks
func is_prebound_or_premade(poi_data: Dictionary, is_corridor: bool) -> bool:
	if poi_data["type"] != "":
		return true
	if is_corridor and corridor_room_scene:
		return true
	return false

# ==========================================
# PROCEDURAL CORRIDOR GENERATOR & SIDE ROOMS
# ==========================================
func _generate_procedural_corridor(chunk_node: Node3D, coords: Vector2i, enable_collision: bool) -> void:
	if abs(coords.x) <= 1 and abs(coords.y) <= 1:
		return

	var half_w = CORRIDOR_WIDTH * 0.5
	spawn_wall_segment_custom(chunk_node, Vector3(-ROOM_SIZE * 0.5 + half_w, 0.0, 0.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, ROOM_SIZE), enable_collision)
	spawn_wall_segment_custom(chunk_node, Vector3(ROOM_SIZE * 0.5 - half_w, 0.0, 0.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, ROOM_SIZE), enable_collision)

	var room_hash = get_2d_hash(coords.x, coords.y, 444)
	if room_hash < 0.40:
		spawn_wall_segment_custom(chunk_node, Vector3(0.0, 0.0, -ROOM_SIZE * 0.5), Vector3(ROOM_SIZE, WALL_HEIGHT, WALL_THICKNESS), enable_collision)

# ==========================================
# SECTOR-SPECIFIC ARCHITECTURAL GEOMETRY
# ==========================================
func _generate_sector_geometry(chunk_node: Node3D, coords: Vector2i, enable_collision: bool, sector: SectorType) -> void:
	if abs(coords.x) <= 1 and abs(coords.y) <= 1:
		return

	var layout_val = layout_noise.get_noise_2d(float(coords.x), float(coords.y))

	# FIXED: Drastically lowered noise thresholds to force dense, claustrophobic maze generation (no more empty flatgrass maps!)
	if layout_val > 0.05:
		spawn_wall_segment(chunk_node, Vector3(0.0, 0.0, -ROOM_SIZE * 0.5), Vector3(ROOM_SIZE, WALL_HEIGHT, WALL_THICKNESS), enable_collision, sector)
		if layout_val > 0.20:
			spawn_wall_segment(chunk_node, Vector3(ROOM_SIZE * 0.5, 0.0, 0.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, ROOM_SIZE), enable_collision, sector)
	elif layout_val < -0.05:
		spawn_wall_segment(chunk_node, Vector3(-ROOM_SIZE * 0.5, 0.0, 0.0), Vector3(WALL_THICKNESS, WALL_HEIGHT, ROOM_SIZE), enable_collision, sector)
		if layout_val < -0.20:
			spawn_wall_segment(chunk_node, Vector3(0.0, 0.0, ROOM_SIZE * 0.5), Vector3(ROOM_SIZE, WALL_HEIGHT, WALL_THICKNESS), enable_collision, sector)

	_spawn_sector_landmarks(chunk_node, coords, sector)

# ==========================================
# THE MESH PROTECTOR (CUSTOM WALL HANDLER)
# ==========================================
func spawn_wall_segment(parent_chunk: Node3D, local_offset: Vector3, dimensions: Vector3, enable_collision: bool, sector: SectorType) -> void:
	var wall_instance: Node3D
	var is_custom_mesh = false

	# 1. Spawn the correct scene based on sector
	if sector == SectorType.FABLED and fabled_wood_wall_scene:
		wall_instance = fabled_wood_wall_scene.instantiate() as Node3D
		is_custom_mesh = true
	elif wall_scene:
		wall_instance = wall_scene.instantiate() as Node3D
	else:
		wall_instance = Node3D.new()

	parent_chunk.add_child(wall_instance)

	# 2. If it's a custom mesh (like the Fabled Wood Wall), keep Y at 0.0 so it sits on the floor correctly!
	if is_custom_mesh:
		wall_instance.position = Vector3(local_offset.x, 0.0, local_offset.z)

		# Rotate 90 degrees if it is placed on the Z-axis (Side walls)
		if dimensions.z > dimensions.x:
			wall_instance.rotation.y = PI / 2.0

		# Update the hidden collision bounds so the player bumps into it properly
		var custom_col = wall_instance.find_child("*CollisionShape3D*", true, false) as CollisionShape3D
		if custom_col and custom_col.shape is BoxShape3D:
			custom_col.shape.size = dimensions
			custom_col.disabled = not enable_collision

		return # EXIT EARLY so procedural concrete logic doesn't touch it

	# 3. Standard Procedural Concrete Wall Generation (Only these use the half-height offset)
	wall_instance.position = Vector3(local_offset.x, WALL_HEIGHT * 0.5, local_offset.z)

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

func spawn_wall_segment_custom(parent_chunk: Node3D, local_offset: Vector3, dimensions: Vector3, enable_collision: bool) -> void:
	spawn_wall_segment(parent_chunk, local_offset, dimensions, enable_collision, SectorType.AQUILA)

func _spawn_sector_landmarks(chunk_node: Node3D, coords: Vector2i, sector: SectorType) -> void:
	var hash_val = get_2d_hash(coords.x, coords.y, 555)

	match sector:
		SectorType.Gothic:
			# FIXED: Spawns a perfectly tiled continuous 6-meter grid of pillars across the ENTIRE sector.
			if gothic_pillar_scene:
				var pillar_offsets = [
					Vector3(-3.0, 0.0, -3.0),
					Vector3(3.0, 0.0, -3.0),
					Vector3(-3.0, 0.0, 3.0),
					Vector3(3.0, 0.0, 3.0)
				]
				for offset in pillar_offsets:
					var pillar = gothic_pillar_scene.instantiate() as Node3D
					chunk_node.add_child(pillar)
					pillar.position = offset
		SectorType.OUROBOROS:
			if hash_val < 0.35 and ouroboros_pipes_scene: # Better spawn rate
				var pipes = ouroboros_pipes_scene.instantiate() as Node3D
				chunk_node.add_child(pipes)
				pipes.position = Vector3(0.0, 0.0, 0.0) # Y used to be: WALL_HEIGHT * 0.8
		SectorType.GARDEN:
			if hash_val < 0.40 and garden_foliage_scene: # Better spawn rate
				var foliage = garden_foliage_scene.instantiate() as Node3D
				chunk_node.add_child(foliage)
				foliage.position = Vector3((randf() - 0.5) * 6.0, 0.0, (randf() - 0.5) * 6.0)
		_:
			pass

# ==========================================
# SECTOR STYLING & TIDY CORNER CRATES
# ==========================================
func _apply_sector_styling(room_node: Node3D, sector: SectorType) -> void:
	match sector:
		SectorType.AQUILA: room_node.set_meta("sector_name", "Aquila")
		SectorType.GILD: room_node.set_meta("sector_name", "Gild")
		SectorType.Gothic: room_node.set_meta("sector_name", "Gothic")
		SectorType.OUROBOROS: room_node.set_meta("sector_name", "Ouroboros")
		SectorType.GARDEN: room_node.set_meta("sector_name", "Garden")
		SectorType.FABLED: room_node.set_meta("sector_name", "Fabled")

func _try_spawn_supply_crates(room_node: Node3D, coords: Vector2i, sector: SectorType) -> void:
	if not crate_prop_scene:
		return

	# Lore Accurate: Gild sector spawns massive amounts of crates for the Trader's Keep.
	var crate_chance = 0.55 if sector == SectorType.GILD else 0.20
	if get_2d_hash(coords.x, coords.y, 8888) < crate_chance:
		var corner_offset = ROOM_SIZE * 0.35
		var x_sign = 1.0 if get_2d_hash(coords.x, coords.y, 111) > 0.5 else -1.0
		var z_sign = 1.0 if get_2d_hash(coords.x, coords.y, 222) > 0.5 else -1.0

		var crate = crate_prop_scene.instantiate() as Node3D
		room_node.add_child(crate)
		crate.position = Vector3(x_sign * corner_offset, 0.0, z_sign * corner_offset)

# ==========================================
# LIGHTING & BLACKOUT EVENTS (THE "FLICKERING")
# ==========================================
func _apply_room_lighting(room_node: Node3D, coords: Vector2i) -> void:
	var lights = room_node.find_children("*", "Light3D", true, false)

	# Lore Accurate: The "Flickering" where lights switch off and the dark entities lurk.
	var is_blackout = enable_blackout_events and (get_2d_hash(coords.x, coords.y, 777) < 0.08)
	var is_flicker = enable_blackout_events and not is_blackout and (get_2d_hash(coords.x, coords.y, 999) < 0.15)

	for light in lights:
		if light is Light3D:
			if is_blackout:
				light.light_energy = 0.0
				light.visible = false
			elif is_flicker:
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

func is_room_walkable(coords: Vector2i) -> bool:
	if abs(coords.x) <= 1 and abs(coords.y) <= 1:
		return true
	if is_in_poi_zone(coords):
		return false

	var layout_val = layout_noise.get_noise_2d(float(coords.x), float(coords.y))
	# Must match the new tight layout maze geometry ranges
	if layout_val > 0.05 or layout_val < -0.05:
		return false

	return true

# ==========================================
# CONSOLE COMMAND SYSTEM
# ==========================================
func register_console_commands() -> void:
	var console_node = get_node_or_null("/root/Console")
	if console_node:
		console_node.add_command("locate", _cmd_locate, 1)
		var locate_targets = ["player", "base_alpha", "traders_keep", "hippocrates_1", "cornucopia", "registration_spot", "diner"]
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
		"base_alpha": _locate_nearest_poi_type(console_node, "base_alpha", "Base Alpha")
		"traders_keep": _locate_nearest_poi_type(console_node, "traders_keep", "Trader's Keep")
		"hippocrates_1": _locate_nearest_poi_type(console_node, "hippocrates_1", "Hippocrates-1")
		"cornucopia": _locate_nearest_poi_type(console_node, "cornucopia", "Camp Cornucopia")
		"registration_spot": _locate_nearest_poi_type(console_node, "registration_spot", "Registration Spot")
		"diner": _locate_nearest_poi_type(console_node, "diner", "Tom's Diner")
		_: console_node.print_line("Unknown target. Options: player, base_alpha, traders_keep, hippocrates_1, cornucopia, registration_spot, diner")

func _locate_nearest_poi_type(console_node: Node, target_type: String, poi_name: String) -> void:
	var start_pos = player.global_position if is_instance_valid(player) else global_position
	var current_macro_x = floori((start_pos.x / ROOM_SIZE) / float(MACRO_SIZE))
	var current_macro_z = floori((start_pos.z / ROOM_SIZE) / float(MACRO_SIZE))

	var nearest_pos := Vector3.ZERO
	var shortest_dist_sq := INF
	var search_radius := 40

	for mx in range(current_macro_x - search_radius, current_macro_x + search_radius + 1):
		for mz in range(current_macro_z - search_radius, current_macro_z + search_radius + 1):
			var info = get_macro_poi_info(mx, mz)
			if info["type"] == target_type:
				var anchor_chunk_x = (mx * MACRO_SIZE) + 1
				var anchor_chunk_z = (mz * MACRO_SIZE) + 1

				var poi_world_pos = Vector3(
						anchor_chunk_x * ROOM_SIZE,
						0.0,
						anchor_chunk_z * ROOM_SIZE
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
