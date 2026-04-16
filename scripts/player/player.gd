class_name OnlinePlayer extends CharacterBody3D

## Тонкий оркестратор: инициализирует компоненты и роутит RPC.
## Никакой логики здесь нет — только делегирование.

signal sniper_scope_changed(active: bool)

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
@onready var game_manager: GameManager = get_tree().get_first_node_in_group("game_manager") as GameManager

# ── данные ────────────────────────────────────────────────────────────────

var player_info: Dictionary = {}
var remote_player_id: int = 0 # id владельца, устанавливается при спавне

## Позиция, к которой lerp-ают не-authority клиенты
var target_position: Vector3
var is_dead: bool = false

## Сервер: блок подбора предметов после выброса оружия (мс), чтобы не поднять сразу же.
var interact_cooldown_until_msec: int = 0

## Deathmatch: окно закупки после спавна (копия deadline для UI; сервер — источник для урона).
var dm_buy_grace_deadline_msec: int = 0
var dm_loadout_block_after_move: bool = false
var dm_moved_since_spawn: bool = false
var _dm_move_reported_server: bool = false

## ADS: 0 — нет прицела, 1..N — ступень зума (переключение ПКМ по кругу, как в CS).
var sniper_scope_stage: int = 0
var _default_camera_fov: float = 75.0

var is_sniper_scoped: bool:
	get:
		return sniper_scope_stage > 0


# ── жизненный цикл ────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("online_players")
	name_label.text = player_info.get("name", "Player")
	aim_component.setup(skeleton, marker_up, marker_center, marker_down)
	weapon_holder.weapon_changed.connect(_on_weapon_changed)
	health_component.reset_health()
	ServerConfig.apply_movement_to_player(self)
	set_alive_state()
	if camera:
		_default_camera_fov = camera.fov


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
	if not multiplayer.is_server() and is_multiplayer_authority() and not is_dead:
		_update_sniper_scope_and_fov(delta)
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
	if event.is_action_pressed("aim"):
		_cycle_sniper_scope_toggle()
	if event.is_action_pressed("drop_weapon") and game_manager:
		game_manager.server_request_drop_weapon.rpc_id(1, remote_player_id)
	if event.is_action_pressed("use") and game_manager:
		var aim := get_aim_ray()
		game_manager.server_request_use_pickup.rpc_id(1, remote_player_id, aim.origin, aim.direction)



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


func _update_sniper_scope_and_fov(delta: float) -> void:
	if camera == null or weapon_holder == null:
		return
	var w := weapon_holder.current_weapon
	var target_fov := _default_camera_fov
	if sniper_scope_stage > 0 and w != null and w.data != null and w.data.has_sniper_scope:
		target_fov = w.data.get_scope_fov_for_stage(sniper_scope_stage)
	camera.fov = lerpf(camera.fov, target_fov, 12.0 * delta)


func _cycle_sniper_scope_toggle() -> void:
	if _is_ui_input_blocked():
		return
	var w := weapon_holder.current_weapon
	if w == null or w.data == null or not w.data.has_sniper_scope:
		return
	var max_st: int = w.data.get_scope_stage_count()
	if max_st < 1:
		return
	var was_active := sniper_scope_stage > 0
	var next := sniper_scope_stage + 1
	if next > max_st:
		next = 0
	sniper_scope_stage = next
	var now_active := sniper_scope_stage > 0
	if was_active != now_active:
		sniper_scope_changed.emit(now_active)


func _is_ui_input_blocked() -> bool:
	if get_viewport().gui_get_focus_owner() != null:
		return true
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
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
	if sniper_scope_stage > 0:
		sniper_scope_stage = 0
		sniper_scope_changed.emit(false)
	if camera:
		camera.fov = _default_camera_fov
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


func reset_dm_loadout_tracking() -> void:
	dm_buy_grace_deadline_msec = 0
	dm_loadout_block_after_move = false
	dm_moved_since_spawn = false
	_dm_move_reported_server = false


## Вызывается только с сервера при первом заметном движении/прыжке после спавна (DM).
func dm_server_mark_movement_for_loadout() -> void:
	if not multiplayer.is_server() or _dm_move_reported_server:
		return
	var dm: DeathmatchMode = null
	if game_manager != null and game_manager.game_mode is DeathmatchMode:
		dm = game_manager.game_mode as DeathmatchMode
	if dm == null or dm.loadout_grace_sec <= 0.0:
		return
	_dm_move_reported_server = true
	dm_moved_since_spawn = true
	if multiplayer.has_multiplayer_peer():
		sync_dm_moved.rpc_id(remote_player_id)


func is_dm_spawn_protected_from_damage() -> bool:
	var gm := game_manager
	if gm == null or gm.game_mode == null:
		return false
	var dm := gm.game_mode as DeathmatchMode
	if dm == null:
		return false
	return dm.is_spawn_damage_protected(self)


# ── RPC (роутинг к компонентам) ───────────────────────────────────────────

@rpc("any_peer", "reliable")
func sync_dm_loadout_window(deadline_msec: int, block_after_move: bool) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	dm_buy_grace_deadline_msec = deadline_msec
	dm_loadout_block_after_move = block_after_move
	dm_moved_since_spawn = false


@rpc("any_peer", "reliable")
func sync_dm_moved() -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	dm_moved_since_spawn = true


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
	if sniper_scope_stage > 0:
		sniper_scope_stage = 0
		sniper_scope_changed.emit(false)
	if weapon:
		# Сообщаем аниматору, когда началась или закончилась перезарядка
		weapon.reload_state_changed.connect(func(reloading):
			var reload_duration := weapon.data.reload_time if reloading and weapon.data else -1.0
			animation.set_reloading(reloading, reload_duration)
		)
