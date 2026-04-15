class_name WeaponPickup extends Area3D

## Лежащий на земле предмет — оружие или патроны.
## Спавнится в мире, ожидает перекрытия с OnlinePlayer.
## Сервер обрабатывает подбор и рассылает всем клиентам команду скрыться.

@export var weapon_data: WeaponData

@onready var mesh:          MeshInstance3D       = $Mesh
@onready var label:         Label3D              = $Label3D
@onready var interact_area: CollisionShape3D     = $CollisionShape3D

var is_picked_up:  bool        = false
var _game_manager: GameManager = null


func _ready() -> void:
	# Кэшируем при старте — не ищем в дереве при каждом подборе
	_game_manager = get_tree().get_first_node_in_group("game_manager") as GameManager

	if weapon_data and label:
		label.text = weapon_data.weapon_name

	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server() or is_picked_up:
		return
	if body is not OnlinePlayer:
		return
	var player := body as OnlinePlayer
	is_picked_up = true
	if _game_manager:
		_game_manager.rpc_equip_weapon_data.rpc(player.remote_player_id, weapon_data.resource_path)
	_hide_pickup.rpc()


## "authority" — скрыть пикап может только сервер, не произвольный клиент.
@rpc("authority", "reliable", "call_local")
func _hide_pickup() -> void:
	visible = false
	interact_area.disabled = true
