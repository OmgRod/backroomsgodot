extends CanvasLayer

@onready var shader_rect: ColorRect = $EffectRect # Adjust path to your full-screen ColorRect node

func _ready() -> void:
	register_console_commands()

func _exit_tree() -> void:
	var console_node = get_node_or_null("/root/Console")
	if console_node and console_node.has_method("remove_command"):
		console_node.remove_command("shader")

func register_console_commands() -> void:
	var console_node = get_node_or_null("/root/Console")
	if console_node:
		console_node.add_command("shader", _cmd_toggle_shader, 0) # 0 arguments required

func _cmd_toggle_shader() -> void:
	var console_node = get_node_or_null("/root/Console")
	
	# Option A: Toggle the CanvasLayer visibility directly
	visible = !visible
	
	# Option B: Or toggle just the ColorRect node inside the layer
	# if shader_rect:
	# 	shader_rect.visible = !shader_rect.visible

	var state_str = "ENABLED" if visible else "DISABLED"
	if console_node:
		console_node.print_line("VHS/CRT Shader toggled: %s" % state_str)
