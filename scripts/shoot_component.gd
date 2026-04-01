extends Node3D

@export var camera:Camera3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func shoot():
	var origin = camera.global_transform.origin
	var direction = -camera.global_transform.basis.z
	
	rpc_id(1, "server_shoot", origin, direction)


@rpc("any_peer")
func server_shoot(origin: Vector3, direction: Vector3):
	if !multiplayer.is_server():
		return

	var space_state = get_world_3d().direct_space_state

	var query = PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * 1000
		)

	var result = space_state.intersect_ray(query)

	if result:
		var collider = result.collider

		if collider.has_method("apply_damage"):
			collider.apply_damage(10)

		rpc("sync_shot_effects", result.position)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
