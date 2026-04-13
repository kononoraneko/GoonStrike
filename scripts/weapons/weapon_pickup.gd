class_name WeaponPickup extends Area3D

## Лежащий на земле предмет — оружие или патроны.
## Спавнится в мире, ожидает перекрытия с OnlinePlayer.
## Сервер обрабатывает подбор и рассылает всем клиентам команду скрыться.

@export var weapon_data: WeaponData   # какое оружие спавнит при подборе

@onready var mesh: MeshInstance3D = $Mesh
@onready var label: Label3D = $Label3D
@onready var interact_area: CollisionShape3D = $CollisionShape3D

var is_picked_up := false

func _ready() -> void:
	if weapon_data and label:
		label.text = weapon_data.weapon_name
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	# Только сервер принимает решение о подборе
	if not multiplayer.is_server():
		return
	if is_picked_up:
		return
	if body is not OnlinePlayer:
		return

	var player := body as OnlinePlayer
	is_picked_up = true

	var gm := get_tree().get_first_node_in_group("game_manager") as GameManager
	if gm:
		gm.rpc_equip_weapon_data.rpc(player.remote_player_id, weapon_data.resource_path)
	rpc("_hide_pickup")


@rpc("any_peer", "reliable", "call_local")
func _hide_pickup() -> void:
	visible = false
	interact_area.disabled = true
