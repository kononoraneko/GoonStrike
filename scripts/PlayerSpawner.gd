## PlayerSpawner.gd
## Единственное место где инстанцируется OnlinePlayer.
## GameManager вызывает spawn/despawn — больше никто.
 
class_name PlayerSpawner extends Node3D
 
@export var player_scene: PackedScene
 
## id → OnlinePlayer
var _nodes: Dictionary = {}
 
 
func spawn(id: int, info: Dictionary) -> OnlinePlayer:
	if _nodes.has(id):
		push_warning("PlayerSpawner: player %d already spawned" % id)
		return _nodes[id]
 
	if player_scene == null:
		push_error("PlayerSpawner: player_scene is not set")
		return null
 
	var player: OnlinePlayer = player_scene.instantiate()
	player.name              = str(id)
	player.player_info       = info
	player.remote_player_id  = id
	player.set_multiplayer_authority(id)
 
	add_child(player)
	_nodes[id] = player
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
