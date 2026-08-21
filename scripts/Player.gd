extends CharacterBody3D

# Movement & Inertia Settings
const WALK_SPEED = 3.2
const SPRINT_SPEED = 4.8
const CROUCH_SPEED = 1.8

const ACCELERATION = 6.0
const DECELERATION = 8.0
const AIR_CONTROL = 2.0
const MOUSE_SENSITIVITY = 0.0025
const TOUCH_SENSITIVITY = 0.003
const JUMP_VELOCITY = 3.0

# Crouching Settings
const STAND_HEAD_HEIGHT = 1.6
const CROUCH_HEAD_HEIGHT = 0.8
const STAND_CAPSULE_HEIGHT = 2.0
const CROUCH_CAPSULE_HEIGHT = 1.0
const CROUCH_LERP_SPEED = 10.0

# Dynamic FOV Configuration
const BASE_FOV = 75.0
const MAX_FOV = 95.0          # Hard upper cap so high speeds don't flip the camera
const FOV_SPEED_SCALE = 0.5    # Controls how strongly speed affects FOV expansion
const FOV_LERP_SPEED = 6.0

# Tuned Stamina Rates (Units per second)
const STAMINA_DRAIN_RATE = 10.0   # Lasts 10 full seconds of continuous sprinting (down from 25)
const STAMINA_WALK_REGEN = 12.0   # Regenerates faster while walking (up from 8)
const STAMINA_IDLE_REGEN = 25.0   # Quickly recovers when standing still (up from 20)

# Dynamic Footstep Cadence
const BASE_STEP_INTERVAL = 0.36
const SPRINT_STEP_INTERVAL = 0.22
const CROUCH_STEP_INTERVAL = 0.55
var step_timer: float = 0.0

# State
var is_sprinting: bool = false
var is_crouching: bool = false
var is_frozen: bool = true # Frozen on startup to prevent falling through void before chunks generate

# Mobile Touch Look Tracking
var touch_look_finger_id: int = -1

# Nodes
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var footstep_audio: AudioStreamPlayer3D = $Head/FootstepAudio
@onready var floor_detector: RayCast3D = $FloorDetector
@onready var ceiling_detector: RayCast3D = $CeilingDetector
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	if not OS.has_feature("mobile") and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	camera.fov = BASE_FOV

	# Duplicate collision shape resource so crouching doesn't mutate shared engine shapes
	if collision_shape and collision_shape.shape:
		collision_shape.shape = collision_shape.shape.duplicate()

func _unhandled_input(event: InputEvent) -> void:
	if is_frozen:
		return

	# Desktop: Re-capture mouse on left click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not DisplayServer.is_touchscreen_available():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return

	# Desktop: Release mouse focus on ESC
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	# Desktop Mouse Looking
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_camera(event.relative * MOUSE_SENSITIVITY)

	# Mobile Touch Looking (Dragging right side of screen)
	handle_mobile_touch_look(event)

	if event.is_action_pressed("crouch"):
		toggle_crouch()

func handle_mobile_touch_look(event: InputEvent) -> void:
	# Ignore on non-touch devices
	if not DisplayServer.is_touchscreen_available() and not OS.has_feature("mobile"):
		return

	var viewport_size = get_viewport().get_visible_rect().size

	if event is InputEventScreenTouch:
		# Finger pressed down on the right half of the screen
		if event.pressed and event.position.x > viewport_size.x * 0.4:
			if touch_look_finger_id == -1:
				touch_look_finger_id = event.index
		# Finger released
		elif not event.pressed and event.index == touch_look_finger_id:
			touch_look_finger_id = -1

	elif event is InputEventScreenDrag and event.index == touch_look_finger_id:
		rotate_camera(event.relative * TOUCH_SENSITIVITY)

func rotate_camera(relative_delta: Vector2) -> void:
	head.rotate_y(-relative_delta.x)
	camera.rotate_x(-relative_delta.y)
	camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _physics_process(delta: float) -> void:
	# Halt movement & gravity until ChunkManager finishes initial floor spawn
	if is_frozen:
		velocity = Vector3.ZERO
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump
	if Input.is_action_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = JUMP_VELOCITY

	# Fetch input direction (Works seamlessly with physical keys OR Virtual Joystick / TouchScreenButtons)
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (head.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Process stamina and calculate current target speed
	var current_target_speed = handle_stamina_and_speed(delta, direction)

	# Movement interpolation
	var accel_rate = ACCELERATION if is_on_floor() else AIR_CONTROL
	if direction:
		var target_velocity = direction * current_target_speed
		velocity.x = lerp(velocity.x, target_velocity.x, accel_rate * delta)
		velocity.z = lerp(velocity.z, target_velocity.z, accel_rate * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELERATION * delta)
		velocity.z = lerp(velocity.z, 0.0, DECELERATION * delta)

	move_and_slide()
	handle_crouch_transform(delta)
	handle_footsteps(delta)
	handle_camera_fov(delta)

func toggle_crouch() -> void:
	if is_crouching:
		if not ceiling_detector.is_colliding():
			is_crouching = false
	else:
		is_crouching = true

func handle_stamina_and_speed(delta: float, direction: Vector3) -> float:
	var wants_to_sprint = Input.is_action_pressed("sprint") and direction != Vector3.ZERO and is_on_floor()

	if is_crouching:
		is_sprinting = false
		Global.regen_stamina(STAMINA_WALK_REGEN * delta)
		return CROUCH_SPEED

	if wants_to_sprint and not Global.is_exhausted:
		var drained = Global.use_stamina(STAMINA_DRAIN_RATE * delta)
		if drained:
			is_sprinting = true
			return SPRINT_SPEED

	# Fallback to walking/idle if sprint failed or isn't requested
	is_sprinting = false
	if direction == Vector3.ZERO:
		Global.regen_stamina(STAMINA_IDLE_REGEN * delta)
	else:
		Global.regen_stamina(STAMINA_WALK_REGEN * delta)

	return WALK_SPEED

func handle_crouch_transform(delta: float) -> void:
	var target_head_y = CROUCH_HEAD_HEIGHT if is_crouching else STAND_HEAD_HEIGHT
	head.position.y = lerp(head.position.y, target_head_y, CROUCH_LERP_SPEED * delta)

	var capsule = collision_shape.shape as CapsuleShape3D
	if capsule:
		var target_height = CROUCH_CAPSULE_HEIGHT if is_crouching else STAND_CAPSULE_HEIGHT
		capsule.height = lerp(capsule.height, target_height, CROUCH_LERP_SPEED * delta)

		var target_col_y = target_height * 0.5
		collision_shape.position.y = lerp(collision_shape.position.y, target_col_y, CROUCH_LERP_SPEED * delta)

func handle_camera_fov(delta: float) -> void:
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()

	# Calculate how much faster or slower we are moving relative to base WALK_SPEED
	# At WALK_SPEED (3.2), speed_factor is 0.0 -> target_fov = BASE_FOV
	# At SPRINT_SPEED (4.8), speed_factor is +0.5 -> target_fov grows
	# At CROUCH_SPEED (1.8), speed_factor is negative -> target_fov shrinks slightly
	var speed_factor = (horizontal_speed - WALK_SPEED) / WALK_SPEED

	var target_fov = BASE_FOV + (speed_factor * BASE_FOV * FOV_SPEED_SCALE)
	target_fov = clamp(target_fov, BASE_FOV - 5.0, MAX_FOV)

	camera.fov = lerp(camera.fov, target_fov, FOV_LERP_SPEED * delta)

func handle_footsteps(delta: float) -> void:
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()

	if is_on_floor() and horizontal_speed > 0.4:
		var max_expected_speed = WALK_SPEED
		var min_interval = BASE_STEP_INTERVAL

		if is_sprinting:
			max_expected_speed = SPRINT_SPEED
			min_interval = SPRINT_STEP_INTERVAL
		elif is_crouching:
			max_expected_speed = CROUCH_SPEED
			min_interval = CROUCH_STEP_INTERVAL

		var speed_ratio = clamp(horizontal_speed / max_expected_speed, 0.2, 1.0)
		var current_interval = lerp(BASE_STEP_INTERVAL, min_interval, speed_ratio)

		step_timer += delta
		if step_timer >= current_interval:
			step_timer = 0.0
			check_and_play_surface_sound()
	else:
		step_timer = BASE_STEP_INTERVAL * 0.85

func check_and_play_surface_sound() -> void:
	if not is_instance_valid(floor_detector) or not floor_detector.is_colliding():
		return

	var collider = floor_detector.get_collider()
	if not collider:
		return

	var mat_type = ""
	if collider.has_meta("material_type"):
		mat_type = collider.get_meta("material_type")
	elif collider.get_parent() and collider.get_parent().has_meta("material_type"):
		mat_type = collider.get_parent().get_meta("material_type")

	if mat_type == "carpet":
		if is_instance_valid(footstep_audio):
			footstep_audio.play()
