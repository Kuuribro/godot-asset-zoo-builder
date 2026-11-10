# Creates / Adds to _zoo scenes for asset library views.
@tool
extends RefCounted

const SEARCH_ROOT := "res://"
const SUFFIX := "_zoo"

# variable needed so it stays as a single reference, not recreated every time
var _save_dialog: EditorFileDialog

## Collect every .tscn under res:// whose basename ends with "_zoo".
func open_picker(context_paths: PackedStringArray) -> void:
	var matches := _find_zoo_scenes()

	# Build the picker window. AcceptDialog = a single "Close" button, no yes/no.
	var dialog := AcceptDialog.new()
	dialog.title = "Zoo Scene Picker"
	dialog.ok_button_text = "Close"

	# Scrollable list of scene names. Each entry's full path lives in its metadata.
	var list := ItemList.new()

	if matches.is_empty():
		# Nothing found: show a single disabled placeholder row so the dialog isn't blank.
		list.add_item("(no .tscn files ending with \"_zoo\" found)")
		list.set_item_disabled(0, true)
	else:
		for p in matches:
			# p is a full path like "res://assets/zoo/lion_zoo.tscn".
			# Display only the short name; the full path goes into metadata + tooltip.
			var scene_name := p.get_file().get_basename()
			var idx := list.add_item(scene_name)
			# Store the full path on the item so later code can retrieve it via list.get_item_metadata(idx)
			list.set_item_metadata(idx, p)
			# Hovering the row shows the full res:// path (Option A behavior).
			list.set_item_tooltip(idx, p)

	# Create a container to stack the list and checkbox
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.add_child(vbox)

	# Attach the list to the container.
	vbox.add_child(list)

	
	# Stash the caller's right-clicked paths for the next step (scene creation).
	dialog.set_meta("context_paths", context_paths)

	# Size the dialog
	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size
	var widest := 0.0
	for p in matches:
		var w := font.get_string_size(p.get_file().get_basename(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if w > widest:
			widest = w
	
	var row_h : float = font.get_height(font_size) + 24
	var content_h : float = row_h * max(1, matches.size())
	var list_h : float = min(content_h, 600.0)   # <-- clamps to 600 max vertical 
	
	# Force the ItemList to have a minimum height so it doesn't get crushed by the dialog
	list.custom_minimum_size = Vector2(0, list_h)
	
	# Set the dialog minimum size. use slightly more vertical padding now for the checkbox and the button bar
	dialog.min_size = Vector2i(int(widest) + 48, int(list_h) + 100)

	# Mount the dialog into the editor's main window so it can actually appear.
	var parent_window := EditorInterface.get_base_control().get_window()
	parent_window.add_child(dialog)
	
	# Create the extra button before popup so it participates in the dialog's layout.
	var create_btn := dialog.add_button("Create new _zoo scene", false, "create_zoo")

	# Button path: "Create new" builds an unsaved scene with the carried assets.
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"create_zoo":
			var carried: PackedStringArray = dialog.get_meta("context_paths")
			_create_new_zoo(carried, dialog)
	)

	# List path: selecting an existing zoo row adds the carried assets into it.
	list.item_selected.connect(func(idx: int) -> void:
		var carried: PackedStringArray = dialog.get_meta("context_paths")
		var target_path: String = list.get_item_metadata(idx)
		# Await the function so the dialog stays alive until the scene swap is done
		await _add_to_existing_zoo(target_path, carried)
		dialog.hide()
		
	)
	# Free the dialog whenever it closes, so repeated right-clicks don't leak nodes.
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free()
	)
	
	dialog.popup_centered()

## Recursively scans res:// for .tscn files whose basename ends with "_zoo",
## and returns their full paths as a sorted PackedStringArray.
func _find_zoo_scenes() -> PackedStringArray:
	var out := PackedStringArray()
	_walk(SEARCH_ROOT, out)
	out.sort()
	return out

## Recursively walks a directory tree, appending the full paths of any .tscn
## files whose basename ends with "_zoo" to the `out` array.
## Skips hidden files and directories (those starting with ".").
func _walk(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("_walk: Failed to open search root " + SEARCH_ROOT)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			_walk(full, out)
		else:
			if name.get_extension().to_lower() == "tscn" \
					and name.get_basename().to_lower().ends_with(SUFFIX):
				out.append(full)
		name = dir.get_next()
	dir.list_dir_end()

## Adds the carried assets as exhibits into an existing zoo scene, then saves it.
func _add_to_existing_zoo(target_path: String, asset_paths: PackedStringArray) -> void:
	EditorInterface.open_scene_from_path(target_path, false)

	await _await_editor_scene_swap()

	var host_root := EditorInterface.get_edited_scene_root()
	if host_root == null:
		push_error("_add_to_existing_zoo: failed to get root of " + target_path)
		return

	var created := _place_exhibits(host_root, asset_paths)
	_space_out_exhibits(host_root, created)

	# Due to an engine bug, scene cannot be saved automatically without causing crashes.
	print_rich("[color=green]Added %d objects. Please save your scene!" % [created.size()])


## Builds a new unsaved zoo scene containing the carried assets as exhibits.
func _create_new_zoo(asset_paths: PackedStringArray, source_dialog: AcceptDialog) -> void:
	# Hide the picker so it releases the exclusive window lock.
	source_dialog.hide()

	# Create the save dialog ONCE and keep it as a member so it is not re-added to the tree on every call.
	if _save_dialog == null:
		_save_dialog = EditorFileDialog.new()
		_save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		_save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_save_dialog.add_filter("*.tscn", "Scene")
		EditorInterface.get_base_control().get_window().add_child(_save_dialog)

	# Disconnect any previous callback so old references don't fire.
	for conn in _save_dialog.file_selected.get_connections():
		_save_dialog.file_selected.disconnect(conn.callable)

	# Intercept the save path selection first.
	_save_dialog.file_selected.connect(func(path: String) -> void:
		var host_root := _build_base_scene(path.get_file().get_basename())
		
		# Pack and save the blank scene to disk.
		var packed := PackedScene.new()
		var pack_result := packed.pack(host_root)
		if pack_result != OK:
			push_error("_create_new_zoo: pack failed with error " + str(pack_result))
			return
			
		var save_result := ResourceSaver.save(packed, path)
		if save_result != OK:
			push_error("_create_new_zoo: save failed with error " + str(save_result))
			return

		# Open the newly saved scene in the editor.
		EditorInterface.open_scene_from_path(path, false)
		
		await _await_editor_scene_swap()

		# Grab the live scene root from the editor.
		var live_root := EditorInterface.get_edited_scene_root()
		if live_root == null:
			push_error("_create_new_zoo: failed to get edited scene root after opening.")
			return

		# Populate it now that it is a proper "existing" editor scene.
		var created := _place_exhibits(live_root, asset_paths)
		_space_out_exhibits(live_root, created)

		# Save the populated scene.
		EditorInterface.save_scene()
		
		# Refresh the FileSystem so it shows up
		EditorInterface.get_resource_filesystem().scan()
		print("_create_new_zoo: built and saved " + path)
	)

	_save_dialog.popup_file_dialog()

## Builds a new scene and saves it to the project before adding anything to it.
func _build_base_scene(scene_name: String) -> Node3D:
		# Build the base root in memory.
		var host_root := Node3D.new()
		
		# Extract the filename without the .tscn extension to use as the root name.
		host_root.name = scene_name
		
		# Attach the runtime toggle script to the root.
		var script_dir = get_script().resource_path.get_base_dir()
		var root_script = load(script_dir.path_join("zoo_root.gd"))
		
		if root_script:
			host_root.set_script(root_script)

		# Add floor
		var floor_body := StaticBody3D.new()
		floor_body.name = "Floor"
		var floor_shape := CollisionShape3D.new()
		var floor_box := BoxShape3D.new()
		floor_box.size = Vector3(1000, 1, 1000)
		floor_shape.position.y = -0.5
		floor_shape.shape = floor_box
		floor_body.add_child(floor_shape)

		var floor_mesh := MeshInstance3D.new()
		var floor_mesh_box := BoxMesh.new()
		floor_mesh_box.size = Vector3(1000, 1, 1000)
		floor_mesh.mesh = floor_mesh_box
		floor_mesh.position.y = -0.5
		floor_body.add_child(floor_mesh)
				
		# create a material and set it to a darker grey
		var floor_mat := StandardMaterial3D.new()
		floor_mat.albedo_color = Color(0.0, 0.2, 0.2) # Dark grey
		floor_mesh.material_override = floor_mat

		host_root.add_child(floor_body)
		floor_body.owner = host_root
		floor_shape.owner = host_root
		floor_mesh.owner = host_root
		floor_body.set_meta("_edit_lock_", true)
			
		# Add a basic directional light
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		# Angle it 
		sun.rotation_degrees = Vector3(-45, -135, 0)
		sun.shadow_enabled = true
		
		host_root.add_child(sun)
		sun.owner = host_root
		
		return host_root

## Instantiates gallery_exhibit per asset, parents them under host_root, assigns the asset.
func _place_exhibits(host_root: Node, asset_paths: PackedStringArray) -> Array[Node]:
	var created: Array[Node] = []

	var container := _find_or_create_container(host_root)

	for p in asset_paths:
		# Skip anything that is not a .tscn file to prevent load() errors on folders or other assets.
		if p.get_extension().to_lower() != "tscn":
			push_warning("_place_exhibits: skipping non-tscn path " + p)
			continue

		var asset_packed := load(p) as PackedScene
		if asset_packed == null:
			push_warning("_place_exhibits: skipping failed PackedScene load " + p)
			continue

		# instantiate the asset here
		var node_to_add: Node = asset_packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)

		if node_to_add == null:
			push_error("_place_exhibits: instantiate failed for " + p)
			continue

		container.add_child(node_to_add)
		node_to_add.owner = host_root
			
		# Marker so _space_out_exhibits can distinguish placed exhibits from other children.
		node_to_add.add_to_group("zoo_objects", true)
		created.append(node_to_add)
		
		var aabb := _get_merged_aabb(node_to_add, node_to_add.global_transform)
		node_to_add.set_meta("zoo_aabb", aabb)
		
		# --- ADD 3D LABEL ---
		var label := Label3D.new()
		# Use the file name (or the node name if you prefer)
		label.text = p.get_file().get_basename()
		
		# Set to billboard so it always faces the camera
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		
		# Optional: Make it look nice
		label.pixel_size = 0.008 # Adjust this to make the text bigger/smaller
		label.modulate = Color(1, 1, 0.5) # Yellow text
		label.outline_size = 8 # Black outline for readability
		label.font_size = 64
		
		label.no_depth_test = true
		
		# put the label below the object
		var depth := -1.5 # Default fallback depth if AABB fails
		if aabb.size != Vector3.ZERO:
			# Place it below the lowest point (aabb.position.y), minus a little padding
			depth = aabb.position.y - 0.3 
			
		label.position = Vector3(0, depth, 0)
		
		# Add label as a child of the exhibit so it moves with it
		node_to_add.add_child(label)
		label.owner = host_root
		
		# Add to a specific group so we can find them later easily
		label.add_to_group("zoo_labels", true)

	return created

## Calculates the space needed between exhibits so they do not overlap.
func _space_out_exhibits(host_root: Node, exhibits: Array[Node]) -> void:
	var gap := 0.5
	var max_per_row := 10
	var row_gap := 2.0 # Z-space gap between rows

	var container := _find_or_create_container(host_root)

	# Start the cursor at the rightmost edge of anything already inside the container, ignoring the exhibits we just added (they have not been positioned yet).
	var start_x := 0.0
	var start_z := 0.0
	var found_existing := false
	var furthest_z := -INF

	if container != null:
		for child in container.get_children():
			if child in exhibits:
				continue
			
			var existing_aabb := _get_merged_aabb(child, child.global_transform)
			var world_aabb: AABB = child.global_transform * existing_aabb
			
			found_existing = true
			furthest_z = max(furthest_z, world_aabb.end.z)
		
		# If there are already objects, we ignore their X positions entirely and start this new batch at X = 0, pushed back by row_gap.
		if found_existing:
			start_x = 0.0
			start_z = furthest_z + row_gap
			
	var current_x := start_x
	var current_z := start_z
	var row_count := 0
	var row_max_z := start_z

	for exhibit in exhibits:
		var aabb: AABB = exhibit.get_meta("zoo_aabb")
		var world_aabb: AABB = exhibit.global_transform * aabb
		
		# Move the exhibit to the current X and Z
		exhibit.global_position.x += current_x - world_aabb.position.x
		exhibit.global_position.z += current_z - world_aabb.position.z
		
		# Advance X for the next item in this row
		current_x += aabb.size.x + gap
		row_count += 1
		
		# Track the furthest Z edge in this row
		var world_end_z: float = world_aabb.end.z + (current_z - world_aabb.position.z)
		if world_end_z > row_max_z:
			row_max_z = world_end_z
			
		# If we hit the max per row, wrap to the next row
		if row_count >= max_per_row:
			current_x = start_x
			current_z = row_max_z + row_gap
			row_count = 0
			row_max_z = current_z

## Calculate object's Bounding Box for spacing assets out visually.
func _get_merged_aabb(node: Node, reference_transform: Transform3D) -> AABB:
	var merged := AABB()
	var first := true
	for child in node.get_children():
		if child is VisualInstance3D:
			# get_aabb() is local; multiply by the node's global transform to get world space, 
			# then invert the reference transform to express it relative to the exhibit root.
			var world_aabb: AABB = child.global_transform * child.get_aabb()
			var local_to_ref: AABB = reference_transform.affine_inverse() * world_aabb
			if first:
				merged = local_to_ref
				first = false
			else:
				merged = merged.merge(local_to_ref)
		# Recurse regardless, since visual instances can be nested
		var child_merged := _get_merged_aabb(child, reference_transform)
		if child_merged.size != Vector3.ZERO:
			if first:
				merged = child_merged
				first = false
			else:
				merged = merged.merge(child_merged)
	return merged
	
## Finds the zoo_objects container under host_root, or creates one.
## Matches by name group so scenes without the group still work.
func _find_or_create_container(host_root: Node) -> Node:
	for child in host_root.get_children():
		if child.name == "zoo_objects" or child.is_in_group("zoo_objects"):
			return child

	var container := Node3D.new()
	container.name = "zoo_objects"
	host_root.add_child(container)
	container.owner = host_root
	container.add_to_group("zoo_objects", true)
	return container

## Waits for the editor to finish swapping scenes.
## EditorInterface has no "scene opened" signal, so this is a workaround.
func _await_editor_scene_swap(frames: int = 4) -> void:
	for i in frames:
		await Engine.get_main_loop().process_frame
