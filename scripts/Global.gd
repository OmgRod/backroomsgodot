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
			is_dead = true
			player_died.emit()

var is_dead: bool = false

# --- Stamina System ---
var max_stamina: float = 100.0
var current_stamina: float = 100.0:
	set(value):
		current_stamina = clamp(value, 0.0, max_stamina)
		stamina_changed.emit(current_stamina, max_stamina)

var min_stamina_to_sprint: float = 15.0
var is_exhausted: bool = false
var trauma_timer: float = 0.0 # Applied on fall damage to delay stamina regen

# --- Sanity System ---
var max_sanity: float = 100.0
var current_sanity: float = 100.0:
	set(value):
		current_sanity = clamp(value, 0.0, max_sanity)
		sanity_changed.emit(current_sanity, max_sanity)
		if current_sanity <= 0.0:
			sanity_depleted.emit()

# Ambient sanity drain rate per second
var base_sanity_drain: float = 0.5

# --- Pitfall Progression System ---
var pitfall_attempts: int = 0

func _process(delta: float) -> void:
	# Tick down fall damage trauma delay
	if trauma_timer > 0.0:
		trauma_timer -= delta

	# Slowly drain sanity passively while exploring
	if not is_dead and current_sanity > 0.0:
		drain_sanity(base_sanity_drain * delta)

# --- Health Helper Functions ---
func take_damage(amount: float) -> void:
	if is_dead:
		return
	current_health -= amount

func heal(amount: float) -> void:
	if is_dead:
		return
	current_health += amount

# --- Stamina Helper Functions ---
func use_stamina(amount: float) -> bool:
	if is_exhausted or is_dead:
		return false

	if current_stamina > 0.0:
		current_stamina -= amount
		if current_stamina <= 0.0:
			current_stamina = 0.0
			is_exhausted = true # Force exhaustion lock until recovered
		return true
	return false

func regen_stamina(amount: float) -> void:
	if is_dead or trauma_timer > 0.0:
		return # Block regeneration while trauma timer is active or player is dead

	current_stamina += amount

	if is_exhausted and current_stamina >= min_stamina_to_sprint:
		is_exhausted = false

func apply_trauma_lock(duration: float) -> void:
	# Zero out stamina and apply a recovery lock (e.g., on fall damage)
	current_stamina = 0.0
	is_exhausted = true
	trauma_timer = duration

# --- Sanity Helper Functions ---
func drain_sanity(amount: float) -> void:
	current_sanity -= amount

func restore_sanity(amount: float) -> void:
	current_sanity += amount

# --- Pitfall Helper Functions ---
## Evaluates whether falling into a pitfall transitions to Level 1.
## Starts at 25% and increases by 25% for each failed fall (25% -> 50% -> 75% -> 100%).
## Resets back to 0 on success.
func check_pitfall_noclip() -> bool:
	pitfall_attempts += 1

	# Guaranteed success on the 4th attempt
	if pitfall_attempts >= 4:
		reset_pitfall_attempts()
		return true

	var chance: float = pitfall_attempts * 0.25
	var success: bool = randf() <= chance

	if success:
		print("Pitfall transition success!")
		reset_pitfall_attempts()
		return true
	else:
		print("Pitfall transition failed! Attempt: %d (Chance was %d%%)" % [pitfall_attempts, int(chance * 100)])
		return false

func reset_pitfall_attempts() -> void:
	pitfall_attempts = 0

# --- System Reset ---
func reset_player_stats() -> void:
	is_dead = false
	is_exhausted = false
	trauma_timer = 0.0
	current_health = max_health
	current_stamina = max_stamina
	current_sanity = max_sanity
	reset_pitfall_attempts()