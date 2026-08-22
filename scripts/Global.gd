extends Node

# --- Global Signals ---
signal health_changed(new_value: float, max_value: float)
signal stamina_changed(new_value: float, max_value: float)
signal sanity_changed(new_value: float, max_value: float)

signal player_died
signal sanity_depleted

# --- Health System ---
var max_health: float = 100.0
var current_health: float = 100.0:
	set(value):
		current_health = clamp(value, 0.0, max_health)
		health_changed.emit(current_health, max_health)
		if current_health <= 0.0 and not is_dead:
			trigger_death_sequence("exhaustion")

var is_dead: bool = false

# --- Stamina System ---
var max_stamina: float = 100.0
var current_stamina: float = 100.0:
	set(value):
		current_stamina = clamp(value, 0.0, max_stamina)
		stamina_changed.emit(current_stamina, max_stamina)

var min_stamina_to_sprint: float = 15.0
var is_exhausted: bool = false
var trauma_timer: float = 0.0

# --- Sanity System ---
var max_sanity: float = 100.0
var current_sanity: float = 100.0:
	set(value):
		current_sanity = clamp(value, 0.0, max_sanity)
		sanity_changed.emit(current_sanity, max_sanity)
		if current_sanity <= 0.0 and not is_dead:
			sanity_depleted.emit()
			trigger_death_sequence("sanity")

var base_sanity_drain: float = 0.2
var pitfall_attempts: int = 0

func _process(delta: float) -> void:
	if trauma_timer > 0.0:
		trauma_timer -= delta

	if not is_dead and current_sanity > 0.0:
		drain_sanity(base_sanity_drain * delta)

# --- Helper Functions ---
func take_damage(amount: float) -> void:
	if is_dead: return
	current_health -= amount

func heal(amount: float) -> void:
	if is_dead: return
	current_health += amount

func use_stamina(amount: float) -> bool:
	if is_exhausted or is_dead: return false
	if current_stamina > 0.0:
		current_stamina -= amount
		if current_stamina <= 0.0:
			current_stamina = 0.0
			is_exhausted = true
		return true
	return false

func regen_stamina(amount: float) -> void:
	if is_dead or trauma_timer > 0.0: return
	current_stamina += amount
	if is_exhausted and current_stamina >= min_stamina_to_sprint:
		is_exhausted = false

func apply_trauma_lock(duration: float) -> void:
	current_stamina = 0.0
	is_exhausted = true
	trauma_timer = duration

func drain_sanity(amount: float) -> void:
	current_sanity -= amount

func restore_sanity(amount: float) -> void:
	current_sanity += amount

# --- Atmospheric Death & Respawn Sequence ---
func trigger_death_sequence(_reason: String = "unknown") -> void:
	if is_dead:
		return

	is_dead = true
	player_died.emit()

	var player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	var chunk_manager = get_tree().root.find_child("ChunkManager", true, false)

	if is_instance_valid(player) and "is_frozen" in player:
		player.is_frozen = true

	var ambience = get_tree().root.find_child("Ambience", true, false) as AudioStreamPlayer
	if is_instance_valid(ambience):
		var tween = create_tween()
		tween.tween_property(ambience, "volume_db", -80.0, 1.5)

	await get_tree().create_timer(2.5).timeout

	# Mutate seed
	if is_instance_valid(chunk_manager) and "SEED" in chunk_manager:
		chunk_manager.SEED += randi_range(100, 9999)
		if chunk_manager.has_method("update_chunks"):
			chunk_manager.update_chunks()

	# Find a validated, open spawn location
	if is_instance_valid(player):
		var safe_pos: Vector3 = find_safe_spawn_point(player, chunk_manager)
		player.global_position = safe_pos
		player.velocity = Vector3.ZERO

	reset_player_stats()

	if is_instance_valid(ambience):
		ambience.volume_db = 0.0

	if is_instance_valid(player) and "is_frozen" in player:
		player.is_frozen = false

func find_safe_spawn_point(player: CharacterBody3D, chunk_manager: Node) -> Vector3:
	var base_origin = player.global_position

	if is_instance_valid(chunk_manager) and chunk_manager.has_method("is_chunk_walkable"):
		# Test up to 50 random chunk coordinates for open ground
		for i in range(50):
			var test_chunk_x = floori(base_origin.x / 2.0) + randi_range(-25, 25)
			var test_chunk_z = floori(base_origin.z / 2.0) + randi_range(-25, 25)
			var test_coords = Vector2i(test_chunk_x, test_chunk_z)

			if chunk_manager.is_chunk_walkable(test_coords):
				return Vector3((test_chunk_x * 2.0) + 1.0, 0.2, (test_chunk_z * 2.0) + 1.0)

	# Fallback if chunk manager lookup fails: default center of origin zone
	return Vector3(1.0, 0.2, 1.0)

# --- Pitfall Helper Functions ---
func check_pitfall_noclip() -> bool:
	pitfall_attempts += 1
	if pitfall_attempts >= 4:
		reset_pitfall_attempts()
		return true
	var chance: float = pitfall_attempts * 0.25
	var success: bool = randf() <= chance
	if success:
		reset_pitfall_attempts()
		return true
	return false

func reset_pitfall_attempts() -> void:
	pitfall_attempts = 0

func reset_player_stats() -> void:
	is_dead = false
	is_exhausted = false
	trauma_timer = 0.0
	current_health = max_health
	current_stamina = max_stamina
	current_sanity = max_sanity