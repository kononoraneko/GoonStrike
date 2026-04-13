class_name MovementComponent extends Node

## Отвечает только за сбор ввода, применение движения и гравитацию.
## Не знает про сеть — владелец сам решает, когда вызывать process_input().

@export var speed := 5.0
@export var jump_velocity := 30.0
@export var mouse_sensitivity := 0.002

var owner_player: OnlinePlayer

# Для анимации и передачи по сети
var input_dir := Vector2.ZERO
var rotation_x := 0.0

func _ready() -> void:
	owner_player = get_parent() as OnlinePlayer
	assert(owner_player != null, "MovementComponent must be child of OnlinePlayer")


## Читает Input и возвращает команду.
## Вызывается только у authority клиента.
func build_command(tick: int) -> Dictionary:
	var dir := Vector3.ZERO
	var is_jump := false

	if Input.is_action_pressed("move_forward"):  dir -= owner_player.transform.basis.z
	if Input.is_action_pressed("move_backward"): dir += owner_player.transform.basis.z
	if Input.is_action_pressed("move_left"):     dir -= owner_player.transform.basis.x
	if Input.is_action_pressed("move_right"):    dir += owner_player.transform.basis.x
	if Input.is_action_just_pressed("move_jump"): is_jump = true

	input_dir = Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	dir = dir.normalized()

	return {
		"tick": tick,
		"dir": dir,
		"raw_dir": input_dir,
		"aim": owner_player.aim_component.aim_angle,
		"rot": owner_player.rotation,
		"jump": is_jump,
	}


## Применяет команду к velocity и вызывает move_and_slide().
## Используется и на клиенте (предсказание), и на сервере (авторитарно).
func apply_movement(cmd: Dictionary) -> void:
	var p := owner_player
	p.velocity.x = cmd["dir"].x * speed
	p.velocity.z = cmd["dir"].z * speed
	if cmd.get("rot") is Vector3:
		var input_rot := cmd["rot"] as Vector3
		p.rotation.y = input_rot.y
	if cmd.get("aim") != null:
		owner_player.aim_component.aim_angle = cmd["aim"]
	if cmd.get("jump", false) and p.is_on_floor():
		p.velocity.y += jump_velocity
	p.move_and_slide()


func apply_gravity(delta: float) -> void:
	if not owner_player.is_on_floor():
		owner_player.velocity += owner_player.get_gravity() * delta


## Обрабатывает мышь — вызывать из _unhandled_input владельца.
func handle_mouse_motion(event: InputEventMouseMotion) -> void:
	owner_player.rotate_y(-event.relative.x * mouse_sensitivity)
	rotation_x -= event.relative.y * mouse_sensitivity
	rotation_x = clamp(rotation_x, -1.5, 1.5)
	if owner_player.camera:
		owner_player.camera.rotation.x = rotation_x
