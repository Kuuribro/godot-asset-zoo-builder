@tool
extends EditorPlugin

var _zoo_menu: EditorContextMenuPlugin

func _enter_tree() -> void:
	var ZooMenuScript = preload("res://addons/asset_zoo_creator/zoo_context_menu.gd")
	_zoo_menu = ZooMenuScript.new()
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, _zoo_menu)
	
	set_input_event_forwarding_always_enabled()

func _exit_tree() -> void:
	if is_instance_valid(_zoo_menu):
		remove_context_menu_plugin(_zoo_menu)

func _forward_3d_gui_input(_camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		var root := EditorInterface.get_edited_scene_root()
		
		# Check if the root node has the toggle_key property.
		if root and "label_toggle_key" in root:
			# Compare the pressed key to the user's chosen key.
			if event.keycode == root.label_toggle_key:
				if root.has_method("toggle_labels"):
					root.toggle_labels()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
				
	return EditorPlugin.AFTER_GUI_INPUT_PASS
