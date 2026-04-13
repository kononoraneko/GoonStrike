class_name AimComponent extends Node
 
@export var spine_bone_name: String
 
var aim_angle: float = 0.0
 
var _skeleton: Skeleton3D
var _spine_bone_idx: int = -1
var _spine_up: Transform3D
var _spine_center: Transform3D
var _spine_down: Transform3D
 
func setup(skeleton: Skeleton3D, marker_up: Marker3D, marker_center: Marker3D, marker_down: Marker3D) -> void:
	_skeleton = skeleton
	_spine_bone_idx = skeleton.find_bone(spine_bone_name)
	if _spine_bone_idx == -1:
		push_warning("AimComponent: bone '%s' not found" % spine_bone_name)
		return
	var inv := skeleton.global_transform.affine_inverse()
	_spine_up     = inv * marker_up.global_transform
	_spine_center = inv * marker_center.global_transform
	_spine_down   = inv * marker_down.global_transform
 
 
func update() -> void:
	if _skeleton == null or _spine_bone_idx == -1:
		return
	var t : float = clamp(aim_angle, -1.0, 1.0)
	var target: Transform3D
	if t >= 0.0:
		target = _spine_center.interpolate_with(_spine_up, t)
	else:
		target = _spine_center.interpolate_with(_spine_down, -t)
	_skeleton.set_bone_global_pose_override(_spine_bone_idx, target, 1.0, true)
