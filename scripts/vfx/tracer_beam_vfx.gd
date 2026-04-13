## Короткий луч выстрела: тонкий цилиндр + аддитивный шейдер.
class_name TracerBeamVfx extends RefCounted

const _BEAM_SHADER: Shader = preload("res://assets/shaders/tracer_beam.gdshader")

static func spawn(parent: Node, from: Vector3, to: Vector3, life_sec: float = 0.085, color: Color = Color(1.0, 0.52, 0.12, 1.0)) -> void:
	var diff := to - from
	var dist := diff.length()
	if dist < 0.02:
		return
	var mid := from + diff * 0.5
	var y := diff / dist
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 1e-8:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()

	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = 0.014
	cyl.top_radius = 0.01
	cyl.height = dist
	cyl.radial_segments = 6
	cyl.rings = 1
	mesh_inst.mesh = cyl

	var mat := ShaderMaterial.new()
	mat.shader = _BEAM_SHADER
	mat.set_shader_parameter("core_color", color)
	mat.set_shader_parameter("fade", 1.0)
	mesh_inst.material_override = mat

	parent.add_child(mesh_inst)
	mesh_inst.global_transform = Transform3D(Basis(x, y, z), mid)

	var tw := mesh_inst.create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("fade", v), 1.0, 0.0, life_sec).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(mesh_inst.queue_free)
