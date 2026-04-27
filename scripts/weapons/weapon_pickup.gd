class_name WeaponPickup extends RigidBody3D

## Лежащий на земле предмет — оружие.
## Корень RigidBody3D обеспечивает физику падения после дропа.
## Подбор: луч + use (свап) или зона — только если основной слот пуст (server_request_proximity_pickup).

@export var weapon_data: WeaponData
@export var auto_pickup_if_slot_empty: bool = true
@export var use_to_swap_if_slot_busy: bool = true
## Статичные пикапы на карте: не падают под гравитацией до подбора.
@export var spawn_frozen: bool = false

@onready var physics_shape: CollisionShape3D = $PhysicsShape
@onready var visual_root: Node3D             = $VisualRoot
@onready var label: Label3D                  = $Label3D
var pickup_area: Area3D

var is_picked_up:  bool        = false
var _game_manager: GameManager = null
## > 0 только у пикапов, заспавненных через GameManager (дроп); 0 — пикап из сцены уровня.
var network_pickup_id: int = 0
var weapon_data_path: String = ""
var ammo_in_mag: int = -1
var ammo_reserve: int = -1
var skin_item_key: String = ""
var original_owner_peer_id: int = 0
var original_owner_name: String = ""


func _ready() -> void:
	add_to_group("weapon_pickups")
	_game_manager = get_tree().get_first_node_in_group("game_manager") as GameManager

	if weapon_data and weapon_data_path.is_empty():
		weapon_data_path = weapon_data.resource_path

	if weapon_data and label:
		_update_label()

	if weapon_data:
		_refresh_world_visual(weapon_data)

	if spawn_frozen:
		freeze = true

	pickup_area = get_node_or_null("PickupArea") as Area3D
	if pickup_area:
		pickup_area.body_entered.connect(_on_pickup_proximity_body_entered)


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


func setup_world_pickup(data_path: String, in_mag: int, in_reserve: int, p_skin_item_key: String = "", p_owner_peer_id: int = 0, p_owner_name: String = "") -> void:
	weapon_data_path = data_path
	ammo_in_mag = max(in_mag, 0)
	ammo_reserve = max(in_reserve, 0)
	skin_item_key = p_skin_item_key.strip_edges()
	original_owner_peer_id = max(p_owner_peer_id, 0)
	original_owner_name = p_owner_name.strip_edges()
	var loaded_data := load(data_path) as WeaponData
	if loaded_data:
		weapon_data = loaded_data
		_update_label()
		if loaded_data.pickup_physics_shape and physics_shape:
			physics_shape.shape = loaded_data.pickup_physics_shape
		_refresh_world_visual(loaded_data)


func _on_pickup_proximity_body_entered(body: Node) -> void:
	if is_picked_up or _game_manager == null:
		return
	if body is not OnlinePlayer:
		return
	var pl := body as OnlinePlayer
	if not pl.is_multiplayer_authority():
		return
	if pl.weapon_holder.has_primary_weapon():
		return
	_game_manager.server_request_proximity_pickup.rpc_id(
		1,
		pl.remote_player_id,
		network_pickup_id,
		global_position,
		get_pickup_data_path()
	)


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
		_apply_skin_to_visual(data, vis)


func _apply_skin_to_visual(data: WeaponData, visual: Node) -> void:
	if skin_item_key.is_empty() or data == null:
		return
	var weapon_key := data.weapon_name.strip_edges().to_lower()
	var skin := CosmeticsRegistry.get_weapon_skin_for_weapon(skin_item_key, weapon_key)
	if skin == null:
		return
	var material: Material = skin.material_override
	if material == null and skin.albedo_tint != Color.WHITE:
		var generated := StandardMaterial3D.new()
		generated.albedo_color = skin.albedo_tint
		material = generated
	if material != null:
		_apply_material_recursive(visual, material)


func _apply_material_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_apply_material_recursive(child, material)


func _update_label() -> void:
	if label == null or weapon_data == null:
		return
	var text := weapon_data.weapon_name
	if not skin_item_key.is_empty():
		var skin := CosmeticsRegistry.get_weapon_skin_for_weapon(skin_item_key, weapon_data.weapon_name.strip_edges().to_lower())
		if skin != null and not skin.display_name.is_empty():
			text += " | %s" % skin.display_name
	if not original_owner_name.is_empty():
		text += "\nOwner: %s" % original_owner_name
	label.text = text


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
	if physics_shape:
		physics_shape.disabled = true
	var area := get_node_or_null("PickupArea") as Area3D
	if area:
		area.monitoring = false
