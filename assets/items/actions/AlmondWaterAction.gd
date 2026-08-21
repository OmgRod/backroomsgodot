# res://items/actions/AlmondWaterAction.gd
class_name AlmondWaterAction
extends ItemAction

@export var sanity_restore: float = 30.0

func on_use(player: Node3D, item_data: ItemData) -> bool:
	if "current_sanity" in Global:
		Global.current_sanity = min(Global.max_sanity, Global.current_sanity + sanity_restore)
		print("Drank Almond Water. Sanity restored!")
		return true # Consumed on use
	return false