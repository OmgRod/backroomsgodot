extends Node3D

@export var player: CharacterBody3D
@export var chunk_scene: PackedScene = preload("res://assets/levels/0/chunks/base.tscn")
@export var pitfall_scene: PackedScene = preload("res://assets/levels/0/chunks/pitfall.tscn")
@export var floor_tile_scene: PackedScene = preload("res://assets/levels/0/meshes/tile_floor.tscn")
@export var wall_scene: PackedScene = preload("res://assets/levels/0/meshes/wall.tscn")
@export var manila_scene: PackedScene = preload("res://assets/levels/0/chunks/manila_room.tscn")
@export var flickering_wall_scene: PackedScene = preload("res://assets/levels/0/meshes/flickering_wall.tscn")

# Grid Configuration (2x2m CHUNKS)
const CHUNK_SIZE: float = 2.0         # 2x2m horizontal chunk
const RENDER_DISTANCE: int = 14       # Radius of loaded chunks
const LOD_0_DIST: int = 6             # Physics collision radius
const WALL_HEIGHT: float = 2.5        # Ceiling height
const BASE_LIGHT_ENERGY: float = 1.0

# Wall Thicknesses
const THIN_WALL: float = 0.25
const THICK_WALL: float = 0.8

# Sector & Special Structure Configuration
const SECTOR_SIZE_CHUNKS: int = 8
const MANILA_SALT: int = 7777
const PITFALL_SALT: int = 9999
const SHIFT_SALT: int = 12345

# Generation Parameters
var SEED: int = int(Time.get_unix_time_from_system())

var zone_noise: FastNoiseLite
var wall_layout_noise: FastNoiseLite

# State Tracking
var loaded_chunks: Dictionary = {}
var chunk_shift_versions: Dictionary = {} # Tracks peripheral shift seeds per chunk
var last_player_chunk: Vector2i = Vector2i(99999, 99999)

# Audio References
@onready var ambience_audio: AudioStreamPlayer = get_node_or_null("../Ambience") as AudioStreamPlayer
@onready var piano_audio: AudioStreamPlayer = get_node_or_null("../ManilaPiano") as AudioStreamPlayer

enum RegionalZone {
	NORMAL,
	BLACKOUT,
	PILLARS,
	FLICKER
}

func _ready() -> void:
	wall_layout_noise = FastNoiseLite.new()
	wall_layout_noise.seed = SEED + 300
	wall_layout_noise.frequency = 0.15

	zone_noise = FastNoiseLite.new()
	zone_noise.seed = SEED + 500
	zone_noise.frequency = 0.02

	_find_player()

	if is_instance_valid(player):
		update_chunks()
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

	var current_chunk := Vector2i(
			floori(player.global_position.x / CHUNK_SIZE),
			floori(player.global_position.z / CHUNK_SIZE)
	)

	if current_chunk != last_player_chunk:
		last_player_chunk = current_chunk
		_apply_peripheral_shift(current_chunk)
		update_chunks()

	_update_environmental_audio_and_lighting(current_chunk)

	if "is_frozen" in player and player.is_frozen:
		player.is_frozen = false

# ==========================================
# PERIPHERAL SHIFT SYSTEM
# ==========================================
func _apply_peripheral_shift(player_chunk: Vector2i) -> void:
	if not is_instance_valid(player) or not player.has_method("get_camera_forward"):
		return

	var cam_forward: Vector3 = player.get_camera_forward()
	cam_forward.y = 0
	cam_forward = cam_forward.normalized()

	var cam_pos: Vector3 = player.get_camera_position()

	var keys = loaded_chunks.keys()
	for coords in keys:
		var chunk_pos = Vector3(coords.x * CHUNK_SIZE, 0.0, coords.y * CHUNK_SIZE)
		var dir_to_chunk = (chunk_pos - cam_pos).normalized()
		dir_to_chunk.y = 0

		if cam_forward.dot(dir_to_chunk) < -0.35 and coords.distance_squared_to(player_chunk) > 16:
			if get_2d_hash(coords.x, coords.y, SHIFT_SALT + int(Time.get_ticks_msec() / 10000)) < 0.10:
				var current_v = chunk_shift_versions.get(coords, 0)
				chunk_shift_versions[coords] = current_v + 1
				despawn_chunk(coords)

# ==========================================
# REGIONAL ZONE & AUDIO LOGIC
# ==========================================
func get_regional_zone(coords: Vector2i) -> RegionalZone:
	var sector_x = floori(float(coords.x) / SECTOR_SIZE_CHUNKS)
	var sector_z = floori(float(coords.y) / SECTOR_SIZE_CHUNKS)

	var rand_val = get_2d_hash(sector_x, sector_z)

	if rand_val < 0.08:
		return RegionalZone.BLACKOUT
	elif rand_val < 0.16:
		return RegionalZone.PILLARS
	elif rand_val < 0.22:
		return RegionalZone.FLICKER
	else:
		return RegionalZone.NORMAL

func _update_environmental_audio_and_lighting(player_chunk: Vector2i) -> void:
	var is_manila_zone = is_in_manila_6x6_zone(player_chunk)
	var zone_type = get_regional_zone(player_chunk)

	if is_manila_zone:
		if is_instance_valid(ambience_audio):
			ambience_audio.volume_db = lerpf(ambience_audio.volume_db, -80.0, 0.05)
		if is_instance_valid(piano_audio):
			if not piano_audio.playing: piano_audio.play()
			piano_audio.volume_db = lerpf(piano_audio.volume_db, 0.0, 0.05)
	elif zone_type == RegionalZone.BLACKOUT:
		if is_instance_valid(ambience_audio):
			ambience_audio.volume_db = lerpf(ambience_audio.volume_db, -80.0, 0.05)
		if is_instance_valid(piano_audio):
			piano_audio.volume_db = lerpf(piano_audio.volume_db, -80.0, 0.05)
	else:
		if is_instance_valid(ambience_audio):
			ambience_audio.volume_db = lerpf(ambience_audio.volume_db, 0.0, 0.05)
		if is_instance_valid(piano_audio):
			piano_audio.volume_db = lerpf(piano_audio.volume_db, -80.0, 0.05)

func update_chunks() -> void:
	var player_chunk := last_player_chunk
	var needed_chunks: Array[Vector2i] = []

	for x in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
		for z in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
			var chunk_coords = Vector2i(player_chunk.x + x, player_chunk.y + z)
			needed_chunks.append(chunk_coords)

	needed_chunks.sort_custom(func(a: Vector2i, b: Vector2i):
		var dist_a = a.distance_squared_to(player_chunk)
		var dist_b = b.distance_squared_to(player_chunk)
		return dist_a < dist_b
	)

	for coords in needed_chunks:
		var horizontal_dist = max(abs(coords.x - player_chunk.x), abs(coords.y - player_chunk.y))
		var enable_collision = horizontal_dist <= LOD_0_DIST

		if not loaded_chunks.has(coords):
			spawn_chunk(coords, enable_collision)
		else:
			update_chunk_collision_state(loaded_chunks[coords], enable_collision)

	var existing_coords = loaded_chunks.keys()
	for coords in existing_coords:
		if not coords in needed_chunks:
			despawn_chunk(coords)

# ==========================================
# PITFALL CHECKS
# ==========================================
func is_in_pitfall_zone(coords_2d: Vector2i) -> bool:
	var sector_x = floori(float(coords_2d.x) / SECTOR_SIZE_CHUNKS)
	var sector_z = floori(float(coords_2d.y) / SECTOR_SIZE_CHUNKS)

	return raw_pitfall_check(sector_x, sector_z) and is_within_pitfall_bounds(coords_2d, sector_x, sector_z)

func raw_pitfall_check(sector_x: int, sector_z: int) -> bool:
	var hash_val = get_2d_hash(sector_x, sector_z, PITFALL_SALT)
	return hash_val <= 0.001

func is_within_pitfall_bounds(coords_2d: Vector2i, sector_x: int, sector_z: int) -> bool:
	var pitfall_center_x = (sector_x * SECTOR_SIZE_CHUNKS) + 3
	var pitfall_center_z = (sector_z * SECTOR_SIZE_CHUNKS) + 3
	return abs(coords_2d.x - pitfall_center_x) <= 2 and abs(coords_2d.y - pitfall_center_z) <= 2

# ==========================================
# MANILA ROOM CHECKS
# ==========================================
func raw_manila_check(sector_x: int, sector_z: int) -> bool:
	if raw_pitfall_check(sector_x, sector_z):
		return false

	var hash_val = get_2d_hash(sector_x, sector_z, MANILA_SALT)
	return hash_val <= 0.1

func is_in_manila_6x6_zone(coords_2d: Vector2i) -> bool:
	var sector_x = floori(float(coords_2d.x) / SECTOR_SIZE_CHUNKS)
	var sector_z = floori(float(coords_2d.y) / SECTOR_SIZE_CHUNKS)

	if not raw_manila_check(sector_x, sector_z):
		return false

	var outer_start_x = (sector_x * SECTOR_SIZE_CHUNKS) + 1
	var outer_start_z = (sector_z * SECTOR_SIZE_CHUNKS) + 1

	return coords_2d.x >= outer_start_x and coords_2d.x < outer_start_x + 6 \
			and coords_2d.y >= outer_start_z and coords_2d.y < outer_start_z + 6

func is_in_manila_inner_4x4_zone(coords_2d: Vector2i) -> bool:
	var sector_x = floori(float(coords_2d.x) / SECTOR_SIZE_CHUNKS)
	var sector_z = floori(float(coords_2d.y) / SECTOR_SIZE_CHUNKS)

	if not raw_manila_check(sector_x, sector_z):
		return false

	var inner_start_x = (sector_x * SECTOR_SIZE_CHUNKS) + 2
	var inner_start_z = (sector_z * SECTOR_SIZE_CHUNKS) + 2

	return coords_2d.x >= inner_start_x and coords_2d.x < inner_start_x + 4 \
			and coords_2d.y >= inner_start_z and coords_2d.y < inner_start_z + 4

func is_manila_anchor_chunk(coords_2d: Vector2i) -> bool:
	var sector_x = floori(float(coords_2d.x) / SECTOR_SIZE_CHUNKS)
	var sector_z = floori(float(coords_2d.y) / SECTOR_SIZE_CHUNKS)

	if not raw_manila_check(sector_x, sector_z):
		return false

	var inner_start_x = (sector_x * SECTOR_SIZE_CHUNKS) + 2
	var inner_start_z = (sector_z * SECTOR_SIZE_CHUNKS) + 2

	return coords_2d.x == inner_start_x and coords_2d.y == inner_start_z

# Check if this chunk lies on the perimeter ring surrounding the 6x6 Manila area
func is_manila_flicker_wall_chunk(coords_2d: Vector2i) -> bool:
	var sector_x = floori(float(coords_2d.x) / SECTOR_SIZE_CHUNKS)
	var sector_z = floori(float(coords_2d.y) / SECTOR_SIZE_CHUNKS)

	if not raw_manila_check(sector_x, sector_z):
		return false

	# Outer 6x6 starts at +1, +1. This puts the exit wall at chunk +0, +3 (just outside the 6x6 wall boundary)
	var perimeter_wall_x = (sector_x * SECTOR_SIZE_CHUNKS) + 0
	var perimeter_wall_z = (sector_z * SECTOR_SIZE_CHUNKS) + 3

	return coords_2d.x == perimeter_wall_x and coords_2d.y == perimeter_wall_z

# ==========================================
# CHUNK SPAWNING & DISPATCH
# ==========================================
func spawn_chunk(coords: Vector2i, enable_collision: bool) -> void:
	var is_pitfall = is_in_pitfall_zone(coords)
	var is_manila_6x6 = is_in_manila_6x6_zone(coords)
	var is_manila_inner = is_in_manila_inner_4x4_zone(coords)
	var is_manila_anchor = is_manila_anchor_chunk(coords)
	var is_manila_flicker_wall = is_manila_flicker_wall_chunk(coords)

	var instance: Node3D

	if is_pitfall:
		instance = pitfall_scene.instantiate() as Node3D
	elif is_manila_inner:
		if is_manila_anchor:
			instance = manila_scene.instantiate() as Node3D
		else:
			instance = Node3D.new() # Reserve space
	else:
		instance = chunk_scene.instantiate() as Node3D

	add_child(instance)

	var world_x = coords.x * CHUNK_SIZE
	var world_z = coords.y * CHUNK_SIZE
	instance.global_position = Vector3(world_x, 0.0, world_z)

	if is_manila_flicker_wall:
		# Always spawn a flickering wall right outside the Manila Room
		spawn_wall_segment(instance, Vector3(0.0, 0.0, -1.0), Vector3(CHUNK_SIZE, WALL_HEIGHT, THICK_WALL), enable_collision, true)
	elif not is_pitfall and not is_manila_6x6:
		generate_backrooms_geometry(instance, coords, enable_collision)

	_apply_zone_lighting(instance, coords)

	loaded_chunks[coords] = instance

func _apply_zone_lighting(chunk_instance: Node3D, coords: Vector2i) -> void:
	var light_node = chunk_instance.get_node_or_null("Base/Ceiling/MeshInstance3D/OmniLight3D") as OmniLight3D
	if not light_node:
		light_node = chunk_instance.find_child("*OmniLight3D*", true, false) as OmniLight3D

	if light_node:
		var zone = get_regional_zone(coords)
		match zone:
			RegionalZone.BLACKOUT:
				light_node.visible = false
				light_node.light_energy = 0.0
			RegionalZone.FLICKER:
				light_node.visible = true
				light_node.light_energy = BASE_LIGHT_ENERGY * (0.3 + randf() * 0.7)
			RegionalZone.NORMAL, RegionalZone.PILLARS, _:
				light_node.visible = true
				light_node.light_energy = BASE_LIGHT_ENERGY

func update_chunk_collision_state(chunk_node: Node3D, enable_collision: bool) -> void:
	var col_shapes = chunk_node.find_children("*", "CollisionShape3D", true, false)
	for col in col_shapes:
		if col is CollisionShape3D:
			col.disabled = not enable_collision

func get_2d_hash(x: int, z: int, salt: int = 0) -> float:
	var shift_v = chunk_shift_versions.get(Vector2i(x, z), 0)
	var h = x * 374761393 + z * 2147483647 + SEED + salt + (shift_v * 982451653)
	h = (h ^ (h >> 13)) * 1274126177
	return float(h & 0x7FFFFFFF) / float(0x7FFFFFFF)

# ==========================================
# MONOTONOUS GEOMETRY GENERATOR
# ==========================================
func generate_backrooms_geometry(chunk_node: Node3D, coords: Vector2i, enable_collision: bool) -> void:
	if abs(coords.x) <= 1 and abs(coords.y) <= 1:
		return

	var zone = get_regional_zone(coords)
	var local_x = posmod(coords.x, SECTOR_SIZE_CHUNKS)
	var local_z = posmod(coords.y, SECTOR_SIZE_CHUNKS)

	if zone == RegionalZone.PILLARS:
		if local_x % 2 == 0 and local_z % 2 == 0:
			spawn_wall_segment(chunk_node, Vector3.ZERO, Vector3(0.8, WALL_HEIGHT, 0.8), enable_collision)
		return

	var layout_val = wall_layout_noise.get_noise_2d(float(coords.x), float(coords.y))

	if layout_val > 0.22:
		var is_flicker = (zone == RegionalZone.FLICKER and randf() < 0.05)
		spawn_wall_segment(chunk_node, Vector3(0.0, 0.0, -1.0), Vector3(CHUNK_SIZE, WALL_HEIGHT, THIN_WALL), enable_collision, is_flicker)
		if layout_val > 0.42:
			spawn_wall_segment(chunk_node, Vector3(1.0, 0.0, 0.0), Vector3(THIN_WALL, WALL_HEIGHT, CHUNK_SIZE), enable_collision)
	elif layout_val < -0.28:
		spawn_wall_segment(chunk_node, Vector3(-1.0, 0.0, 0.0), Vector3(THIN_WALL, WALL_HEIGHT, CHUNK_SIZE), enable_collision)

func spawn_wall_segment(parent_chunk: Node3D, local_offset: Vector3, dimensions: Vector3, enable_collision: bool, force_flicker: bool = false) -> void:
	var wall_instance: Node3D
	if force_flicker and flickering_wall_scene:
		wall_instance = flickering_wall_scene.instantiate() as Node3D
	else:
		wall_instance = wall_scene.instantiate() as Node3D

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

func despawn_chunk(coords: Vector2i) -> void:
	if loaded_chunks.has(coords):
		var instance = loaded_chunks[coords]
		loaded_chunks.erase(coords)
		if is_instance_valid(instance):
			instance.queue_free()

func _exit_tree() -> void:
	if Engine.has_singleton("Console") or get_tree().root.has_node("Console"):
		var console_node = get_node_or_null("/root/Console")
		if console_node and console_node.has_method("remove_command"):
			console_node.remove_command("locate")

# ==========================================
# CONSOLE COMMAND SYSTEM
# ==========================================
func register_console_commands() -> void:
	var console_node = get_node_or_null("/root/Console")
	if console_node:
		console_node.add_command("locate", _cmd_locate, 1)
		var locate_targets = ["pitfalls", "pitfall", "player", "manila", "manilaroom"]
		console_node.add_command_autocomplete_list("locate", locate_targets)

func _cmd_locate(target_name: String) -> void:
	var console_node = get_node_or_null("/root/Console")
	if not console_node:
		return

	target_name = target_name.to_lower().strip_edges()

	match target_name:
		"pitfalls", "pitfall":
			_locate_nearest_pitfall(console_node)
		"manila", "manilaroom":
			_locate_nearest_manila(console_node)
		"player":
			if is_instance_valid(player):
				var pos = player.global_position
				console_node.print_line("Player location: (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z])
			else:
				console_node.print_line("Error: Player node not found.")
		_:
			console_node.print_line("Unknown locate target: '%s'. Options: pitfalls, manila, player" % target_name)

func _locate_nearest_pitfall(console_node: Node) -> void:
	var start_pos = player.global_position if is_instance_valid(player) else global_position

	var current_sector_x = floori((start_pos.x / CHUNK_SIZE) / float(SECTOR_SIZE_CHUNKS))
	var current_sector_z = floori((start_pos.z / CHUNK_SIZE) / float(SECTOR_SIZE_CHUNKS))

	var nearest_pitfall_pos := Vector3.ZERO
	var shortest_dist_sq := INF
	var search_radius := 40

	for sx in range(current_sector_x - search_radius, current_sector_x + search_radius + 1):
		for sz in range(current_sector_z - search_radius, current_sector_z + search_radius + 1):
			if raw_pitfall_check(sx, sz):
				var center_chunk_x = (sx * SECTOR_SIZE_CHUNKS) + 3.5
				var center_chunk_z = (sz * SECTOR_SIZE_CHUNKS) + 3.5

				var pitfall_world_pos = Vector3(
						center_chunk_x * CHUNK_SIZE,
						0.0,
						center_chunk_z * CHUNK_SIZE
				)

				var dist_sq = start_pos.distance_squared_to(pitfall_world_pos)
				if dist_sq < shortest_dist_sq:
					shortest_dist_sq = dist_sq
					nearest_pitfall_pos = pitfall_world_pos

	if shortest_dist_sq != INF:
		var distance = sqrt(shortest_dist_sq)
		console_node.print_line(
				"Nearest pitfall found at: (X: %.1f, Y: 0.0, Z: %.1f) [~%.1fm away]" % [
					nearest_pitfall_pos.x,
					nearest_pitfall_pos.z,
					distance
				]
		)
	else:
		console_node.print_line("No pitfalls found within search range.")

func _locate_nearest_manila(console_node: Node) -> void:
	var start_pos = player.global_position if is_instance_valid(player) else global_position

	var current_sector_x = floori((start_pos.x / CHUNK_SIZE) / float(SECTOR_SIZE_CHUNKS))
	var current_sector_z = floori((start_pos.z / CHUNK_SIZE) / float(SECTOR_SIZE_CHUNKS))

	var nearest_manila_pos := Vector3.ZERO
	var shortest_dist_sq := INF
	var search_radius := 150

	for sx in range(current_sector_x - search_radius, current_sector_x + search_radius + 1):
		for sz in range(current_sector_z - search_radius, current_sector_z + search_radius + 1):
			if raw_manila_check(sx, sz):
				var center_chunk_x = (sx * SECTOR_SIZE_CHUNKS) + 4.0
				var center_chunk_z = (sz * SECTOR_SIZE_CHUNKS) + 4.0

				var manila_world_pos = Vector3(
						center_chunk_x * CHUNK_SIZE,
						0.0,
						center_chunk_z * CHUNK_SIZE
				)

				var dist_sq = start_pos.distance_squared_to(manila_world_pos)
				if dist_sq < shortest_dist_sq:
					shortest_dist_sq = dist_sq
					nearest_manila_pos = manila_world_pos

	if shortest_dist_sq != INF:
		var distance = sqrt(shortest_dist_sq)
		console_node.print_line(
				"Nearest Manila Room found at: (X: %.1f, Y: 0.0, Z: %.1f) [~%.1fm away]" % [
					nearest_manila_pos.x,
					nearest_manila_pos.z,
					distance
				]
		)
	else:
		console_node.print_line("No Manila Room found within search range.")

# ==========================================
# WALKABILITY VALIDATION FOR RESPAWN
# ==========================================
func is_chunk_walkable(coords: Vector2i) -> bool:
	if abs(coords.x) <= 1 and abs(coords.y) <= 1:
		return true

	if is_in_pitfall_zone(coords) or is_in_manila_6x6_zone(coords):
		return false

	var zone = get_regional_zone(coords)
	if zone == RegionalZone.PILLARS:
		return false

	var layout_val = wall_layout_noise.get_noise_2d(float(coords.x), float(coords.y))
	if layout_val > 0.22 or layout_val < -0.28:
		return false

	return true
