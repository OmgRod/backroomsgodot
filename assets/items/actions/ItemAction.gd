# res://items/actions/ItemAction.gd
class_name ItemAction
extends Resource

# Called when the player uses/consumes the item
func on_use(player: Node3D, item_data: ItemData) -> bool:
	return false # Return true if the item was consumed/used up

# Called when the player drops the item onto the ground
func on_drop(player: Node3D, item_data: ItemData) -> void:
	pass

# Called when the item is equipped/held
func on_equip(player: Node3D, item_data: ItemData) -> void:
	pass

# Called when unequipped/switched away
func on_unequip(player: Node3D, item_data: ItemData) -> void:
	pass
