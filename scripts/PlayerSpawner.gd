## PlayerSpawner.gd
## Единственное место где инстанцируется OnlinePlayer.
## GameManager вызывает spawn/despawn — больше никто.

class_name PlayerSpawner extends Node3D

@export var player_scene: PackedScene
@export var spawn_points_root: NodePath
@export var fallback_spawn_step: float = 3.0
@export var fallback_spawn_height: float = 1.2

## id → OnlinePlayer
var _nodes: Dictionary = {}
var _spawn_counter: Dictionary = {}


func spawn(id: int, info: Dictionary) -> OnlinePlayer:
	if _nodes.has(id):
		push_warning("PlayerSpawner: player %d already spawned" % id)
		return _nodes[id]

	if player_scene == null:
		push_error("PlayerSpawner: player_scene is not set")
		return null

	var player: OnlinePlayer = player_scene.instantiate()
	player.name = str(id)
	player.player_info = info
	player.remote_player_id = id
	player.set_multiplayer_authority(id)

	add_child(player)
	player.global_transform = _pick_spawn_transform(id)
	_nodes[id] = player
	_spawn_counter[id] = int(_spawn_counter.get(id, 0)) + 1
	return player


func despawn(id: int) -> void:
	if not _nodes.has(id):
		return
	_nodes[id].queue_free()
	_nodes.erase(id)


func get_player(id: int) -> OnlinePlayer:
	return _nodes.get(id)


func get_all() -> Array:
	return _nodes.values()


func _pick_spawn_transform(id: int) -> Transform3D:
	var spawn_points := _get_spawn_points()
	if spawn_points.size() > 0:
		var index := int(_spawn_counter.get(id, 0)) % spawn_points.size()
		return spawn_points[index].global_transform

	var attempt := int(_spawn_counter.get(id, 0))
	var offset := Vector3((id % 4) * fallback_spawn_step, fallback_spawn_height, (attempt % 4) * fallback_spawn_step)
	return Transform3D(Basis.IDENTITY, global_position + offset)


func _get_spawn_points() -> Array[Node3D]:
	if spawn_points_root == NodePath():
		return []
	var root := get_node_or_null(spawn_points_root)
	if root == null:
		return []

	var points: Array[Node3D] = []
	for child in root.get_children():
		if child is Node3D:
			points.append(child)
	return points
