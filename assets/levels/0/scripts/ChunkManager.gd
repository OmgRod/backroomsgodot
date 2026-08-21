extends Node3D

@export var player: CharacterBody3D
@export var chunk_scene: PackedScene = preload("res://assets/levels/0/chunks/base.tscn")
@export var pitfall_scene: PackedScene = preload("res://assets/levels/0/chunks/pitfall.tscn")
@export var floor_tile_scene: PackedScene = preload("res://assets/levels/0/meshes/tile_floor.tscn")
@export var wall_scene: PackedScene = preload("res://assets/levels/0/meshes/wall.tscn")

# Grid Configuration (3D CHUNKS)
const CHUNK_SIZE: float = 2.0         # 2x2m horizontal base chunk size
const CHUNK_HEIGHT: float = 5.0       # 5m vertical chunk height (accommodates 2.5m drop)
const RENDER_DISTANCE: int = 14       # Radius of loaded chunks
const VERTICAL_RENDER_DISTANCE: int = 1 # Layers above/below to render
const LOD_0_DIST: int = 6             # Chunks within this radius calculate physics collision
const WALL_HEIGHT: float = 2.5        # Ceiling height

# Variable Wall Thicknesses
const THIN_WALL: float = 0.25         # Office partition drywall
const THICK_WALL: float = 0.8          # Heavy structural column/wall

# Sector Configuration
const SECTOR_SIZE_CHUNKS: int = 8

# Generation Parameters
var SEED: int = int(Time.get_unix_time_from_system())

var zone_noise: FastNoiseLite
var wall_layout_noise: FastNoiseLite

# State Tracking
var loaded_chunks: Dictionary = {}
var last_player_chunk: Vector3i = Vector3i(99999, 99999, 99999)

enum SectorType {
	CLASSIC_MIX,      # Organic Backrooms maze
	OFFICE_MAZE,      # Dense structured maze
	YELLOW_PILLARS,   # Grid of plus-shaped pillars
	WHITE_ROOMS,      # Open rooms with thick corner blocks
	HOT_HALLS,        # Long parallel hallway corridors
	PRISON_CELLS      # Tight grid cells/cubicles
}

func _ready() -> void:
	# High-frequency noise for wall placement variations
	wall_layout_noise = FastNoiseLite.new()
	wall_layout_noise.seed = SEED + 300
	wall_layout_noise.frequency = 0.15

	# Organic generation noise
	zone_noise = FastNoiseLite.new()
	zone_noise.seed = SEED + 500
	zone_noise.frequency = 0.02

	if not player:
		player = get_tree().get_first_node_in_group("player")
		if not player:
			player = get_parent().get_node_or_null("Player")

	update_chunks()

	if is_instance_valid(player) and "is_frozen" in player:
		player.is_frozen = false

func _process(_delta: float) -> void:
	if not player:
		return

	# Offset Y by half CHUNK_HEIGHT (2.5m) so entering a pitfall immediately updates the Y layer
	var current_chunk := Vector3i(
			floori(player.global_position.x / CHUNK_SIZE),
			floori((player.global_position.y + (CHUNK_HEIGHT * 0.5)) / CHUNK_HEIGHT),
			floori(player.global_position.z / CHUNK_SIZE)
	)

	if current_chunk != last_player_chunk:
		last_player_chunk = current_chunk
		update_chunks()

func update_chunks() -> void:
	var player_chunk := last_player_chunk
	var needed_chunks: Array[Vector3i] = []

	# Clamp vertical generation so we never generate chunks above layer 0
	for y in range(-VERTICAL_RENDER_DISTANCE, VERTICAL_RENDER_DISTANCE + 1):
		var target_y = player_chunk.y + y
		if target_y > 0:
			continue # Do not render layers above the surface layer (Y=0)

		for x in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
			for z in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
				var chunk_coords = Vector3i(player_chunk.x + x, target_y, player_chunk.z + z)
				needed_chunks.append(chunk_coords)

	needed_chunks.sort_custom(func(a: Vector3i, b: Vector3i):
		var dist_a = a.distance_squared_to(player_chunk)
		var dist_b = b.distance_squared_to(player_chunk)
		return dist_a < dist_b
	)

	for coords in needed_chunks:
		var horizontal_dist = max(abs(coords.x - player_chunk.x), abs(coords.z - player_chunk.z))
		var enable_collision = horizontal_dist <= LOD_0_DIST and (coords.y >= player_chunk.y - 1 and coords.y <= player_chunk.y + 1)

		if not loaded_chunks.has(coords):
			spawn_chunk(coords, enable_collision)
		else:
			update_chunk_collision_state(loaded_chunks[coords], enable_collision)

	var existing_coords = loaded_chunks.keys()
	for coords in existing_coords:
		if not coords in needed_chunks:
			despawn_chunk(coords)

# Checks if a 2D chunk coordinate falls inside a 5x5 pitfall hole
func is_in_pitfall_zone(coords_2d: Vector2i, layer_y: int) -> bool:
	if layer_y > 0:
		return false

	var sector_x = floori(float(coords_2d.x) / SECTOR_SIZE_CHUNKS)
	var sector_z = floori(float(coords_2d.y) / SECTOR_SIZE_CHUNKS)

	# If the layer above is a pitfall, do NOT generate another pitfall directly underneath it
	if layer_y < 0 and raw_pitfall_check(sector_x, layer_y + 1, sector_z):
		return false

	return raw_pitfall_check(sector_x, layer_y, sector_z) and is_within_pitfall_bounds(coords_2d, sector_x, sector_z)

func raw_pitfall_check(sector_x: int, layer_y: int, sector_z: int) -> bool:
	# Pitfalls cannot exist on layer_y > 0
	if layer_y > 0:
		return false
	var hash_val = get_3d_hash(sector_x, layer_y, sector_z, 9999)
	return hash_val <= 0.025 # ~2.5% chance per sector per layer

func is_within_pitfall_bounds(coords_2d: Vector2i, sector_x: int, sector_z: int) -> bool:
	var pitfall_center_x = (sector_x * SECTOR_SIZE_CHUNKS) + 3
	var pitfall_center_z = (sector_z * SECTOR_SIZE_CHUNKS) + 3
	return abs(coords_2d.x - pitfall_center_x) <= 2 and abs(coords_2d.y - pitfall_center_z) <= 2

func spawn_chunk(coords: Vector3i, enable_collision: bool) -> void:
	var coords_2d = Vector2i(coords.x, coords.z)
	var is_pitfall = is_in_pitfall_zone(coords_2d, coords.y)

	# Check if this chunk sits directly below a pitfall hole in the layer above
	var sector_x = floori(float(coords_2d.x) / SECTOR_SIZE_CHUNKS)
	var sector_z = floori(float(coords_2d.y) / SECTOR_SIZE_CHUNKS)
	var is_pitfall_drop_landing = raw_pitfall_check(sector_x, coords.y + 1, sector_z) and is_within_pitfall_bounds(coords_2d, sector_x, sector_z)

	var instance: Node3D

	if is_pitfall:
		# Pitfall opening on current layer
		instance = pitfall_scene.instantiate() as Node3D
	elif is_pitfall_drop_landing:
		# Landing directly underneath a pitfall from above: ONLY spawn floor_tile_scene
		instance = floor_tile_scene.instantiate() as Node3D
	else:
		# Standard backrooms chunk
		instance = chunk_scene.instantiate() as Node3D

	add_child(instance)

	var world_x = coords.x * CHUNK_SIZE
	var world_y = coords.y * CHUNK_HEIGHT
	var world_z = coords.z * CHUNK_SIZE
	instance.global_position = Vector3(world_x, world_y, world_z)

	# Only generate maze walls for standard chunks
	if not is_pitfall and not is_pitfall_drop_landing:
		generate_backrooms_geometry(instance, coords, enable_collision)

	loaded_chunks[coords] = instance

func update_chunk_collision_state(chunk_node: Node3D, enable_collision: bool) -> void:
	var col_shapes = chunk_node.find_children("*", "CollisionShape3D", true, false)
	for col in col_shapes:
		if col is CollisionShape3D:
			col.disabled = not enable_collision

func get_3d_hash(x: int, y: int, z: int, salt: int = 0) -> float:
	var h = x * 374761393 + y * 668265263 + z * 2147483647 + SEED + salt
	h = (h ^ (h >> 13)) * 1274126177
	return float(h & 0x7FFFFFFF) / float(0x7FFFFFFF)

func get_sector_type(coords: Vector3i) -> SectorType:
	var sector_x = floori(float(coords.x) / SECTOR_SIZE_CHUNKS)
	var sector_z = floori(float(coords.z) / SECTOR_SIZE_CHUNKS)

	var rand_val = get_3d_hash(sector_x, coords.y, sector_z)

	if rand_val < 0.50:
		return SectorType.CLASSIC_MIX
	elif rand_val < 0.70:
		return SectorType.OFFICE_MAZE
	elif rand_val < 0.78:
		return SectorType.YELLOW_PILLARS
	elif rand_val < 0.86:
		return SectorType.WHITE_ROOMS
	elif rand_val < 0.93:
		return SectorType.HOT_HALLS
	else:
		return SectorType.PRISON_CELLS

func generate_backrooms_geometry(chunk_node: Node3D, coords: Vector3i, enable_collision: bool) -> void:
	# Clear spawn area on start layer
	if coords.y == 0 and abs(coords.x) <= 1 and abs(coords.z) <= 1:
		return

	var local_x = posmod(coords.x, SECTOR_SIZE_CHUNKS)
	var local_z = posmod(coords.z, SECTOR_SIZE_CHUNKS)

	var sector_type = get_sector_type(coords)
	var layout_val = wall_layout_noise.get_noise_3d(float(coords.x), float(coords.y * 10), float(coords.z))

	match sector_type:
		SectorType.CLASSIC_MIX:
			var zone_val = zone_noise.get_noise_3d(float(coords.x), float(coords.y * 10), float(coords.z))
			if zone_val < -0.3:
				if local_x % 2 == 0 and local_z % 2 == 0:
					spawn_plus_shaped_pillar(chunk_node, enable_collision)
			elif zone_val >= -0.3 and zone_val < 0.2:
				if layout_val > 0.18:
					spawn_wall_segment(chunk_node, Vector3(0.0, 0.0, -1.0), Vector3(CHUNK_SIZE, WALL_HEIGHT, THIN_WALL), enable_collision)
					if layout_val > 0.35:
						spawn_wall_segment(chunk_node, Vector3(1.0, 0.0, 0.0), Vector3(THIN_WALL, WALL_HEIGHT, CHUNK_SIZE), enable_collision)
				elif layout_val < -0.22:
					spawn_wall_segment(chunk_node, Vector3(-1.0, 0.0, 0.0), Vector3(THIN_WALL, WALL_HEIGHT, CHUNK_SIZE), enable_collision)
			else:
				if layout_val > 0.15:
					spawn_wall_segment(chunk_node, Vector3(0.0, 0.0, -1.0), Vector3(CHUNK_SIZE, WALL_HEIGHT, THICK_WALL), enable_collision)
					if layout_val > 0.32:
						spawn_wall_segment(chunk_node, Vector3(1.0, 0.0, 0.0), Vector3(THICK_WALL, WALL_HEIGHT, CHUNK_SIZE), enable_collision)

		SectorType.OFFICE_MAZE:
			if layout_val > 0.18:
				spawn_wall_segment(chunk_node, Vector3(0.0, 0.0, -1.0), Vector3(CHUNK_SIZE, WALL_HEIGHT, THIN_WALL), enable_collision)
				if layout_val > 0.38:
					spawn_wall_segment(chunk_node, Vector3(1.0, 0.0, 0.0), Vector3(THIN_WALL, WALL_HEIGHT, CHUNK_SIZE), enable_collision)
			elif layout_val < -0.25:
				spawn_wall_segment(chunk_node, Vector3(-1.0, 0.0, 0.0), Vector3(THIN_WALL, WALL_HEIGHT, CHUNK_SIZE), enable_collision)

		SectorType.YELLOW_PILLARS:
			if local_x % 2 == 0 and local_z % 2 == 0:
				spawn_plus_shaped_pillar(chunk_node, enable_collision)

		SectorType.PRISON_CELLS:
			if local_x % 3 == 0 and local_z % 3 != 1:
				spawn_wall_segment(chunk_node, Vector3(-1.0, 0.0, 0.0), Vector3(THIN_WALL, WALL_HEIGHT, CHUNK_SIZE), enable_collision)
			if local_z % 3 == 0 and local_x % 3 != 1:
				spawn_wall_segment(chunk_node, Vector3(0.0, 0.0, -1.0), Vector3(CHUNK_SIZE, WALL_HEIGHT, THIN_WALL), enable_collision)

		SectorType.HOT_HALLS:
			if local_x % 2 == 0:
				spawn_wall_segment(chunk_node, Vector3(-1.0, 0.0, 0.0), Vector3(THIN_WALL, WALL_HEIGHT, CHUNK_SIZE), enable_collision)

		SectorType.WHITE_ROOMS:
			if (local_x % 4 == 0 or local_x % 4 == 1) and (local_z % 4 == 0 or local_z % 4 == 1):
				spawn_wall_segment(chunk_node, Vector3.ZERO, Vector3(CHUNK_SIZE, WALL_HEIGHT, CHUNK_SIZE), enable_collision)

func spawn_plus_shaped_pillar(parent_chunk: Node3D, enable_collision: bool) -> void:
	var stem_length = 1.2
	var thickness = 0.5

	spawn_wall_segment(parent_chunk, Vector3.ZERO, Vector3(stem_length, WALL_HEIGHT, thickness), enable_collision)
	spawn_wall_segment(parent_chunk, Vector3.ZERO, Vector3(thickness, WALL_HEIGHT, stem_length), enable_collision)

func spawn_wall_segment(parent_chunk: Node3D, local_offset: Vector3, dimensions: Vector3, enable_collision: bool) -> void:
	var wall_instance = wall_scene.instantiate() as Node3D
	parent_chunk.add_child(wall_instance)

	var pos_y = WALL_HEIGHT * 0.5
	wall_instance.position = Vector3(local_offset.x, pos_y, local_offset.z)

	var mesh_node = wall_instance.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not mesh_node and wall_instance is MeshInstance3D:
		mesh_node = wall_instance as MeshInstance3D

	if mesh_node and mesh_node.mesh is BoxMesh:
		mesh_node.mesh = mesh_node.mesh.duplicate() as BoxMesh
		(mesh_node.mesh as BoxMesh).size = dimensions
	else:
		wall_instance.scale = dimensions

	var col_shape = wall_instance.find_child("CollisionShape3D", true, false) as CollisionShape3D
	if col_shape:
		if not col_shape.shape or not (col_shape.shape is BoxShape3D):
			col_shape.shape = BoxShape3D.new()
		else:
			col_shape.shape = col_shape.shape.duplicate() as BoxShape3D

		(col_shape.shape as BoxShape3D).size = dimensions
		col_shape.disabled = not enable_collision

func despawn_chunk(coords: Vector3i) -> void:
	if loaded_chunks.has(coords):
		var instance = loaded_chunks[coords]
		loaded_chunks.erase(coords)
		if is_instance_valid(instance):
			instance.queue_free()
