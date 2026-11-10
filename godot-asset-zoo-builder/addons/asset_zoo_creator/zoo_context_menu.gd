@tool
extends EditorContextMenuPlugin

const ZooCreator := preload("res://addons/asset_zoo_creator/zoo_creator.gd")

func _popup_menu(paths: PackedStringArray) -> void:
	add_context_menu_item("Add to Asset Zoo", _on_zoo_create)

func _on_zoo_create(paths: PackedStringArray) -> void:
	var creator := ZooCreator.new()
	creator.open_picker(paths)
