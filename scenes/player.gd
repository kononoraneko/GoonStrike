class_name OnlinePlayer extends CharacterBody3D

## Тонкий оркестратор: инициализирует компоненты и роутит RPC.
## Никакой логики здесь нет — только делегирование.

# ── дочерние компоненты (настроить в сцене) ──────────────────────────────

@onready var movement:       MovementComponent  = $MovementComponent
@onready var network:        NetworkComponent   = $NetworkComponent
@onready var health_component: HealthComponent  = $HealthComponent
@onready var animation:      AnimationComponent = $AnimationComponent
@onready var aim_component:  AimComponent       = $AimComponent
@onready var weapon_holder:  WeaponHolder       = $WeaponHolder

@onready var camera:         Camera3D           = $Camera3D
@onready var name_label:     Label3D            = $Label3D
@onready var skeleton:       Skeleton3D         = $model/GeneralSkeleton

@onready var marker_up:     Marker3D = $model/GeneralSkeleton/pose_up
@onready var marker_center: Marker3D = $model/GeneralSkeleton/pose_center
@onready var marker_down:   Marker3D = $model/GeneralSkeleton/pose_down

# ── данные ────────────────────────────────────────────────────────────────

var player_info: Dictionary = {}
var remote_player_id: int = 0   # id владельца, устанавливается при спавне

## Позиция, к которой lerp-ают не-authority клиенты
var target_position: Vector3


# ── жизненный цикл ────────────────────────────────────────────────────────

func _ready() -> void:
	name_label.text = player_info.get("name", "Player")
	aim_component.setup(skeleton, marker_up, marker_center, marker_down)
	
	if is_multiplayer_authority():
		if multiplayer.is_server():
			visible = false
			transform.origin.y += 10
			return
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		visible = false
	elif name == "1":
		visible = false


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		if not is_multiplayer_authority():
			network.process_server_queue()
	else:
		if is_multiplayer_authority():
			var cmd := movement.build_command(network.tick)
			network.send_and_apply(cmd)
			animation.update(movement.input_dir)
		else:
			global_transform.origin = global_transform.origin.lerp(target_position, 10.0 * delta)
			animation.update(movement.input_dir)

	movement.apply_gravity(delta)
	aim_component.update()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or multiplayer.is_server():
		return

	if event is InputEventMouseMotion:
		movement.handle_mouse_motion(event)
		aim_component.aim_angle = movement.rotation_x / 1.5

	if event.is_action_pressed("shoot"):
		weapon_holder.try_shoot(get_shoot_direction())

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(
			Input.MOUSE_MODE_CAPTURED if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
			else Input.MOUSE_MODE_VISIBLE)


func get_shoot_direction() -> Vector3:
	var vp := get_viewport()
	var center := vp.get_visible_rect().size / 2.0
	return camera.project_ray_normal(center)


# ── RPC (роутинг к компонентам) ───────────────────────────────────────────

@rpc("any_peer", "unreliable", "call_local")
func process_server_input(cmd: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	network.enqueue(cmd)


@rpc("any_peer", "call_local")
func client_correct_state(server_pos: Vector3, _server_tick: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	global_transform.origin = server_pos


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
