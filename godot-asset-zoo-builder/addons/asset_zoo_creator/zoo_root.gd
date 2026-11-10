@tool
extends Node3D

@export_group("Label Settings")

## Adjust font size.
@export var label_font_size: int = 64:
	set(value):
		label_font_size = maxi(value, 1)
		update_labels()

## Adjust this if desired font size becomes blurry. 
@export var label_pixel_size: float = 0.008:
	set(value):
		label_pixel_size = maxf(value, 0.0001)
		update_labels()
		
## Adjust label color.
@export var label_color: Color = Color(1, 1, 0.5):
	set(value):
		label_color = value
		update_labels()
		
@export var label_toggle_key: Key = KEY_X

## Toggles the visibility of all labels in the scene in-game.
func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
		
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == label_toggle_key:
			toggle_labels()

## Toggles the visibility of all labels in the scene in-editor.
func toggle_labels() -> void:
	var labels = get_tree().get_nodes_in_group("zoo_labels")
	if labels.size() > 0:
		var new_vis = !labels[0].visible
		for lbl in labels:
			if is_instance_valid(lbl):
				lbl.visible = new_vis

func update_labels() -> void:
	# Only run in the editor so changes propagate live when tweaking the slider.
	if not Engine.is_editor_hint():
		return
		
	var labels = get_tree().get_nodes_in_group("zoo_labels")
	for lbl in labels:
		if lbl is Label3D:
			lbl.font_size = label_font_size
			lbl.pixel_size = label_pixel_size
			lbl.modulate = label_color
