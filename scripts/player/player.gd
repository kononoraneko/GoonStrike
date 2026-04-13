class_name OnlinePlayer extends CharacterBody3D

## Тонкий оркестратор: инициализирует компоненты и роутит RPC.
## Никакой логики здесь нет — только делегирование.

# ── дочерние компоненты (настроить в сцене) ──────────────────────────────

@onready var movement: MovementComponent = $MovementComponent
@onready var network: NetworkComponent = $NetworkComponent
@onready var health_component: HealthComponent = $HealthComponent
@onready var animation: AnimationComponent = $AnimationComponent
@onready var aim_component: AimComponent = $AimComponent
@onready var weapon_holder: WeaponHolder = $WeaponHolder

@onready var camera: Camera3D = $Camera3D
@onready var name_label: Label3D = $Label3D
@onready var skeleton: Skeleton3D = $Model/GeneralSkeleton
@onready var collision: CollisionShape3D = $CollisionShape3D

@onready var marker_up: Marker3D = $Model/GeneralSkeleton/pose_up
@onready var marker_center: Marker3D = $Model/GeneralSkeleton/pose_center
@onready var marker_down: Marker3D = $Model/GeneralSkeleton/pose_down

# ── данные ────────────────────────────────────────────────────────────────

var player_info: Dictionary = {}
var remote_player_id: int = 0 # id владельца, устанавливается при спавне

## Позиция, к которой lerp-ают не-authority клиенты
var target_position: Vector3
var is_dead: bool = false


# ── жизненный цикл ────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("online_players")
	name_label.text = player_info.get("name", "Player")
	aim_component.setup(skeleton, marker_up, marker_center, marker_down)
	weapon_holder.weapon_changed.connect(_on_weapon_changed)
	health_component.reset_health()
	ChatNetwork.apply_shared_movement_to_player(self)
	set_alive_state()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if multiplayer.is_server():
		if not is_multiplayer_authority():
			network.process_server_queue()
	else:
		if is_multiplayer_authority():
			var cmd: Dictionary = movement.build_command(network.tick)
			if _is_ui_input_blocked():
				cmd = _build_idle_command(network.tick)
			network.send_and_apply(cmd)
			animation.update(movement.input_dir)
		else:
			global_transform.origin = global_transform.origin.lerp(target_position, 10.0 * delta)
			velocity = Vector3.ZERO
			animation.update(movement.input_dir)

	if multiplayer.is_server() or is_multiplayer_authority():
		movement.apply_gravity(delta)
	aim_component.update()


func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if not is_multiplayer_authority() or multiplayer.is_server():
		return
	if _is_ui_input_blocked():
		return

	if event is InputEventMouseMotion:
		movement.handle_mouse_motion(event)
		aim_component.aim_angle = movement.rotation_x / 1.5

	if event.is_action_pressed("shoot"):
		weapon_holder.start_shooting()
	elif event.is_action_released("shoot"):
		weapon_holder.stop_shooting()
		
	if event.is_action_pressed("reload"):
		weapon_holder.try_reload()



func get_shoot_direction() -> Vector3:
	var vp := get_viewport()
	var center := vp.get_visible_rect().size / 2.0
	return camera.project_ray_normal(center)


func get_aim_ray() -> Dictionary:
	var vp := get_viewport()
	var center := vp.get_visible_rect().size / 2.0
	# Для 1-го и 3-го лица математика прицеливания всегда идёт от камеры.
	# Если добавите камеру 3-го лица (SpringArm), этот код продолжит работать идеально.
	return {
		"origin": camera.project_ray_origin(center),
		"direction": camera.project_ray_normal(center)
	}


func _is_ui_input_blocked() -> bool:
	if get_viewport().gui_get_focus_owner() != null:
		return true
	for child in get_tree().root.get_children():
		if child.scene_file_path == ScenePaths.PAUSE_MENU:
			return true
	return false


func _build_idle_command(tick: int) -> Dictionary:
	movement.input_dir = Vector2.ZERO
	return {
		"tick": tick,
		"dir": Vector3.ZERO,
		"raw_dir": Vector2.ZERO,
		"aim": aim_component.aim_angle,
		"rot": rotation,
		"jump": false,
	}

func set_dead_state() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	if collision:
		collision.disabled = true
	visible = false


func set_alive_state() -> void:
	is_dead = false
	velocity = Vector3.ZERO
	if collision:
		collision.disabled = false
	_update_visibility()


func _update_visibility() -> void:
	if is_dead:
		visible = false
		return

	if is_multiplayer_authority():
		if multiplayer.is_server():
			visible = false
			return
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif remote_player_id == 1 and not is_multiplayer_authority():
		visible = false
	else:
		visible = true
	
	if $ModelLegs:
		$ModelLegs.visible = is_multiplayer_authority()
	if $Camera3D/ModelHands:
		$Camera3D/ModelHands.visible = is_multiplayer_authority()
	if $Model:
		$Model.visible = !is_multiplayer_authority()


# ── RPC (роутинг к компонентам) ───────────────────────────────────────────

@rpc("any_peer", "unreliable", "call_local")
func process_server_input(cmd: Dictionary) -> void:
	if not multiplayer.is_server() or is_dead:
		return
	network.enqueue(cmd)


@rpc("any_peer", "call_local")
func client_correct_state(server_pos: Vector3, server_velocity: Vector3, _server_tick: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	global_transform.origin = server_pos
	velocity = server_velocity


@rpc("any_peer")
func update_remote_state(pos: Vector3, cmd: Dictionary) -> void:
	if not is_multiplayer_authority():
		target_position = pos
		rotation = cmd.get("rot", rotation)
		movement.input_dir = cmd.get("raw_dir", Vector2.ZERO)
		aim_component.aim_angle = cmd.get("aim", 0.0)


@rpc("any_peer", "reliable", "call_local")
func rpc_play_hit_animation() -> void:
	if not multiplayer.is_server() or is_multiplayer_authority():
		animation.play_hit()


func _on_weapon_changed(weapon: Weapon):
	if weapon:
		# Сообщаем аниматору, когда началась или закончилась перезарядка
		weapon.reload_state_changed.connect(func(reloading):
			var reload_duration := weapon.data.reload_time if reloading and weapon.data else -1.0
			animation.set_reloading(reloading, reload_duration)
		)
