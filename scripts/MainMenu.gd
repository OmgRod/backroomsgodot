extends Control

# Update these paths to match your project structure
@export_file("*.tscn") var start_level_path: String = "res://game.tscn"

@onready var start_button: Button = $Container/ButtonContainer/StartButton
@onready var options_button: Button = $Container/ButtonContainer/OptionsButton
@onready var exit_button: Button = $Container/ButtonContainer/ExitButton

func _ready() -> void:
	# Connect button signals programmatically
	start_button.pressed.connect(_on_start_button_pressed)
	if options_button:
		options_button.pressed.connect(_on_options_button_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)

func _on_start_button_pressed() -> void:
	# Change directly to the game level
	if FileAccess.file_exists(start_level_path):
		get_tree().change_scene_to_file(start_level_path)
	else:
		push_error("Start level scene path does not exist: " + start_level_path)

func _on_options_button_pressed() -> void:
	# Open options menu or popup here
	print("Options pressed")

func _on_exit_button_pressed() -> void:
	# Gracefully quit the application
	get_tree().quit()
