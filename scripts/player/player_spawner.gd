## PlayerSpawner.gd
## Единственное место где инстанцируется OnlinePlayer.
## GameManager вызывает spawn/despawn — больше никто.

class_name PlayerSpawner extends Node3D

## Слушающий хост (peer 1): поднимаем тело над сценой — вид от первого лица, коллизии на спавне.
const SERVER_HOST_PAWN_Y_LIFT := 10.0

@export var player_scene: PackedScene
@export var spawn_points_root: NodePath
@export var team_alpha_spawn_root: NodePath
@export var team_bravo_spawn_root: NodePath
@export var fallback_spawn_step: float = 3.0
@export var fallback_spawn_height: float = 1.2

## id → OnlinePlayer
var _nodes: Dictionary = {}
var _spawn_counter: Dictionary = {}
var _mode_id: String = GameModeCatalog.ID_DM


func apply_mode_from_lobby(mode_id: String) -> void:
	_mode_id = mode_id


func spawn(id: int, info: Dictionary) -> OnlinePlayer:
	if _nodes.has(id):
		push_warning("PlayerSpawner: player %d already spawned" % id)
		return _nodes[id]

	var scene := _resolve_player_scene(info)
	if scene == null:
		push_error("PlayerSpawner: no valid player scene for player %d" % id)
		return null

	var player: OnlinePlayer = scene.instantiate()
	player.name = str(id)
	player.player_info = info
	player.remote_player_id = id
	player.set_multiplayer_authority(id)

	add_child(player)
	player.global_transform = _pick_spawn_transform(id)
	if GameModeCatalog.is_team_mode(_mode_id):
		call_deferred("_deferred_team_spawn_fixup", id, player)
	if multiplayer.is_server() and id == 1:
		player.global_position.y += SERVER_HOST_PAWN_Y_LIFT
	_nodes[id] = player
	_spawn_counter[id] = int(_spawn_counter.get(id, 0)) + 1
	return player


func _resolve_player_scene(info: Dictionary) -> PackedScene:
	var character_id := String(info.get("character_id", "")).strip_edges().to_lower()
	if not character_id.is_empty():
		var cosmetic_scene := CosmeticsRegistry.get_character_scene(character_id)
		if cosmetic_scene != null:
			return cosmetic_scene
	return player_scene


## Новый раунд / респавн: существующий павн переносится на актуальную точку команды (счётчик попыток растёт — другая точка внутри списка).
func reapply_spawn_transform(id: int) -> void:
	if not _nodes.has(id):
		return
	var player: OnlinePlayer = _nodes[id]
	if not is_instance_valid(player):
		return
	_spawn_counter[id] = int(_spawn_counter.get(id, 0)) + 1
	player.global_transform = _pick_spawn_transform(id)
	if GameModeCatalog.is_team_mode(_mode_id):
		call_deferred("_deferred_team_spawn_fixup", id, player)
	if multiplayer.is_server() and id == 1:
		player.global_position.y += SERVER_HOST_PAWN_Y_LIFT


func _deferred_team_spawn_fixup(id: int, player: OnlinePlayer) -> void:
	if not is_instance_valid(player):
		return
	var gm := get_parent() as GameManager
	if gm == null or gm.game_mode is not TeamGameMode:
		return
	var tm := gm.game_mode as TeamGameMode
	var team := tm.get_team(id)
	if team == TeamGameMode.Team.NONE:
		return
	player.global_transform = _pick_team_spawn_transform(id, team)


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
	if GameModeCatalog.is_team_mode(_mode_id):
		var gm := get_parent() as GameManager
		if gm and gm.game_mode is TeamGameMode:
			var team := (gm.game_mode as TeamGameMode).get_team(id)
			if team != TeamGameMode.Team.NONE:
				return _pick_team_spawn_transform(id, team)
	return _pick_dm_spawn_transform(id)


func _pick_dm_spawn_transform(id: int) -> Transform3D:
	var pts := _collect_points_under(spawn_points_root)
	if pts.size() > 0:
		var attempt := int(_spawn_counter.get(id, 0))
		var idx := (id * 793 + attempt * 17 + 13) % pts.size()
		return pts[idx].global_transform
	return _fallback_transform(id)


func _pick_team_spawn_transform(id: int, team: int) -> Transform3D:
	var path: NodePath = team_alpha_spawn_root if team == TeamGameMode.Team.ALPHA else team_bravo_spawn_root
	if team == TeamGameMode.Team.NONE or path == NodePath():
		return _pick_dm_spawn_transform(id)
	var pts := _collect_points_under(path)
	if pts.size() > 0:
		var attempt := int(_spawn_counter.get(id, 0))
		var idx := (id * 541 + attempt * 23 + int(team) * 7) % pts.size()
		return pts[idx].global_transform
	return _fallback_transform(id)


func _fallback_transform(id: int) -> Transform3D:
	var attempt := int(_spawn_counter.get(id, 0))
	var offset := Vector3((id % 4) * fallback_spawn_step, fallback_spawn_height, (attempt % 4) * fallback_spawn_step)
	return Transform3D(Basis.IDENTITY, global_position + offset)


func _collect_points_under(root_path: NodePath) -> Array[Node3D]:
	if root_path == NodePath():
		return []
	var root := get_node_or_null(root_path)
	if root == null:
		return []
	var points: Array[Node3D] = []
	for child in root.get_children():
		if child is Node3D:
			points.append(child)
	return points
