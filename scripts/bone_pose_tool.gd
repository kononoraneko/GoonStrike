@tool
extends Skeleton3D

@export var bone_name: String = "mixamorig_Spine1"

@export_group("Marker Positions")
@export var marker_up: Marker3D
@export var marker_center: Marker3D
@export var marker_down: Marker3D

@export_group("Actions")
@export var capture_current_pose_to_markers: bool = false:
	set(val):
		if val and Engine.is_editor_hint():
			capture_current_pose_to_markers = false
			_capture_current_pose_to_markers()
@export var apply_marker_center_to_bone: bool = false:
	set(val):
		if val and Engine.is_editor_hint():
			apply_marker_center_to_bone = false
			_apply_marker_to_bone(marker_center)
@export var apply_marker_up_to_bone: bool = false:
	set(val):
		if val and Engine.is_editor_hint():
			apply_marker_up_to_bone = false
			_apply_marker_to_bone(marker_up)
@export var apply_marker_down_to_bone: bool = false:
	set(val):
		if val and Engine.is_editor_hint():
			apply_marker_down_to_bone = false
			_apply_marker_to_bone(marker_down)

@export_group("Preview")
@export var preview_angle: float = 0.0:
	set(val):
		preview_angle = val
		if Engine.is_editor_hint():
			_preview_angle(val)

var bone_idx: int = -1

func _ready():
	if Engine.is_editor_hint():
		_setup()

func _setup():
	bone_idx = find_bone(bone_name)
	if bone_idx == -1:
		print("BonePoseEditor: bone '%s' not found" % bone_name)
		return
	
	# Создаём маркеры, если их нет
	if not marker_up:
		marker_up = _create_marker("pose_up")
	if not marker_center:
		marker_center = _create_marker("pose_center")
	if not marker_down:
		marker_down = _create_marker("pose_down")
	
	# Инициализируем маркеры текущей позой кости
	var current = get_bone_global_pose(bone_idx)
	marker_up.transform = current
	marker_center.transform = current
	marker_down.transform = current

func _create_marker(name: String) -> Marker3D:
	var marker = Marker3D.new()
	marker.name = name
	add_child(marker)
	marker.owner = get_tree().edited_scene_root
	return marker

func _capture_current_pose_to_markers():
	if bone_idx == -1:
		return
	var current = get_bone_global_pose(bone_idx)
	marker_up.transform = current
	marker_center.transform = current
	marker_down.transform = current
	print("Captured current bone pose to all markers")

func _apply_marker_to_bone(marker: Marker3D):
	if bone_idx == -1 or not marker:
		return
	set_bone_global_pose_override(bone_idx, marker.transform, 1.0, true)
	print("Applied marker '%s' to bone" % marker.name)

func _preview_angle(angle: float):
	if bone_idx == -1:
		return
	var t = clamp(angle, -1.0, 1.0)
	var target: Transform3D
	if t >= 0:
		target = marker_center.transform.interpolate_with(marker_up.transform, t)
	else:
		target = marker_center.transform.interpolate_with(marker_down.transform, -t)
	set_bone_global_pose_override(bone_idx, target, 1.0, true)
