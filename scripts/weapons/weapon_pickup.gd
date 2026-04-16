class_name WeaponPickup extends RigidBody3D

## Лежащий на земле предмет — оружие.
## Корень RigidBody3D обеспечивает физику падения после дропа.
## Подбор — только по лучу прицела на сервере (см. GameManager.server_request_use_pickup).
## Сервер обрабатывает логику и рассылает всем клиентам команду скрыться.

@export var weapon_data: WeaponData
@export var auto_pickup_if_slot_empty: bool = true
@export var use_to_swap_if_slot_busy: bool = true
## Статичные пикапы на карте: не падают под гравитацией до подбора.
@export var spawn_frozen: bool = false

@onready var physics_shape: CollisionShape3D  = $PhysicsShape
@onready var interact_shape: CollisionShape3D = $Area3D/InteractShape
@onready var visual_root: Node3D              = $VisualRoot
@onready var label: Label3D                   = $Label3D

var is_picked_up:  bool        = false
var _game_manager: GameManager = null
## > 0 только у пикапов, заспавненных через GameManager (дроп); 0 — пикап из сцены уровня.
var network_pickup_id: int = 0
var weapon_data_path: String = ""
var ammo_in_mag: int = -1
var ammo_reserve: int = -1


func _ready() -> void:
	add_to_group("weapon_pickups")
	_game_manager = get_tree().get_first_node_in_group("game_manager") as GameManager

	if weapon_data and weapon_data_path.is_empty():
		weapon_data_path = weapon_data.resource_path

	if weapon_data and label:
		label.text = weapon_data.weapon_name

	if weapon_data:
		_refresh_world_visual(weapon_data)

	if spawn_frozen:
		freeze = true


func is_available() -> bool:
	return not is_picked_up


func get_pickup_data_path() -> String:
	if not weapon_data_path.is_empty():
		return weapon_data_path
	if weapon_data:
		return weapon_data.resource_path
	return ""


func get_pickup_ammo_state() -> Dictionary:
	var in_mag := ammo_in_mag
	var in_reserve := ammo_reserve
	var data := weapon_data
	if data == null:
		var data_path := get_pickup_data_path()
		if not data_path.is_empty():
			data = load(data_path) as WeaponData
	if data:
		if in_mag < 0:
			in_mag = max(data.magazine_size, 1)
		if in_reserve < 0:
			in_reserve = max(data.reserve_ammo, 0)
	return {
		"ammo_in_mag": max(in_mag, 0),
		"ammo_reserve": max(in_reserve, 0),
	}


func setup_world_pickup(data_path: String, in_mag: int, in_reserve: int) -> void:
	weapon_data_path = data_path
	ammo_in_mag = max(in_mag, 0)
	ammo_reserve = max(in_reserve, 0)
	var loaded_data := load(data_path) as WeaponData
	if loaded_data:
		weapon_data = loaded_data
		if label:
			label.text = loaded_data.weapon_name
		if loaded_data.pickup_physics_shape and physics_shape:
			physics_shape.shape = loaded_data.pickup_physics_shape
		_refresh_world_visual(loaded_data)


func _refresh_world_visual(data: WeaponData) -> void:
	if visual_root == null or data == null or data.weapon_scene == null:
		return
	while visual_root.get_child_count() > 0:
		var c := visual_root.get_child(0)
		visual_root.remove_child(c)
		c.free()
	var vis := data.weapon_scene.instantiate()
	if vis is Node:
		vis.set_script(null)
		var spr := vis.get_node_or_null("SpreadComponent")
		if spr:
			spr.queue_free()
		visual_root.add_child(vis)


func consume_on_server() -> void:
	if not multiplayer.is_server() or is_picked_up:
		return
	is_picked_up = true
	# RPC на дочернем узле ломается на клиентах (другой путь в дереве). Удаление по id — в GameManager.
	if network_pickup_id > 0 and _game_manager:
		_game_manager.rpc_remove_world_pickup.rpc(network_pickup_id)
	else:
		_hide_pickup.rpc()


## Только для пикапов из .tscn уровня (network_pickup_id == 0).
@rpc("authority", "reliable", "call_local")
func _hide_pickup() -> void:
	visible = false
	if interact_shape:
		interact_shape.disabled = true
	if physics_shape:
		physics_shape.disabled = true
