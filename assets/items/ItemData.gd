# res://items/ItemData.gd
class_name ItemData
extends Resource

@export var id: StringName = &"item_id"
@export var name: String = "Item"
@export var icon: Texture2D
@export var pickup_mesh: PackedScene # 3D mesh spawned when dropped into the world

# Link custom event logic here
@export var action: ItemAction
