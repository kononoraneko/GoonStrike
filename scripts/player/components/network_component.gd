class_name NetworkComponent extends Node

## Отвечает за: буфер ввода, отправку команд на сервер,
## коррекцию позиции от сервера, репликацию состояния другим клиентам.

var owner_player: OnlinePlayer
const MAX_INPUT_DIR_LEN := 1.0
const MAX_QUEUE_SIZE := 64
const MIN_TICKS_BETWEEN_JUMPS := 8

# Клиент
var tick: int = 0
var input_buffer: Array = []   # команды, ожидающие подтверждения

# Сервер
var input_queue: Array = []
var last_processed_tick: int = 0
var _last_received_tick: int = 0
var _last_jump_tick: int = -MIN_TICKS_BETWEEN_JUMPS

func _ready() -> void:
	owner_player = get_parent() as OnlinePlayer


## Клиент: отправляет команду на сервер и применяет локально.
func send_and_apply(cmd: Dictionary) -> void:
	tick += 1
	cmd["tick"] = tick
	input_buffer.append(cmd)
	owner_player.rpc_id(1, "process_server_input", cmd)
	owner_player.movement.apply_movement(cmd)


## Сервер: накапливает команды из очереди.
func enqueue(cmd: Dictionary) -> void:
	var sanitized := _sanitize_server_command(cmd)
	if sanitized.is_empty():
		return
	input_queue.append(sanitized)
	if input_queue.size() > MAX_QUEUE_SIZE:
		input_queue.pop_front()


## Сервер: обрабатывает все накопленные команды за кадр.
func process_server_queue() -> void:
	input_queue.sort_custom(func(a, b): return a.tick < b.tick)
	var processed := 0
	while input_queue.size() > 0 and processed < 5:
		var cmd: Dictionary = input_queue.pop_front()
		var prev_pos := owner_player.global_transform.origin
		owner_player.movement.apply_movement(cmd)
		var moved := owner_player.global_transform.origin - prev_pos
		if moved.length() > owner_player.movement.speed * 0.25:
			owner_player.global_transform.origin = prev_pos + moved.normalized() * owner_player.movement.speed * 0.25
		last_processed_tick = cmd.tick
		# Корректируем позицию у владельца и обновляем остальных
		owner_player.rpc_id(owner_player.remote_player_id, "client_correct_state",
			owner_player.global_transform.origin, owner_player.velocity, last_processed_tick)
		owner_player.rpc("update_remote_state",
			owner_player.global_transform.origin, cmd)
		var raw2: Vector2 = cmd.get("raw_dir", Vector2.ZERO)
		if raw2.length() > 0.08 or bool(cmd.get("jump", false)):
			owner_player.dm_server_mark_movement_for_loadout()
		processed += 1


func _sanitize_server_command(cmd: Dictionary) -> Dictionary:
	if not cmd.has("tick") or not cmd.has("dir"):
		return {}

	var cmd_tick := int(cmd.get("tick", -1))
	if cmd_tick <= _last_received_tick:
		return {}

	var dir_value = cmd.get("dir", Vector3.ZERO)
	if not (dir_value is Vector3):
		return {}
	var dir := dir_value as Vector3
	if dir.length() > MAX_INPUT_DIR_LEN:
		dir = dir.normalized() * MAX_INPUT_DIR_LEN

	var jump := bool(cmd.get("jump", false))
	if jump:
		if cmd_tick - _last_jump_tick < MIN_TICKS_BETWEEN_JUMPS:
			jump = false
		else:
			_last_jump_tick = cmd_tick

	var aim := float(clamp(cmd.get("aim", 0.0), -1.0, 1.0))
	var rot_value = cmd.get("rot", owner_player.rotation)
	var rot := owner_player.rotation
	if rot_value is Vector3:
		rot.y = (rot_value as Vector3).y

	var raw_value = cmd.get("raw_dir", Vector2.ZERO)
	var raw_dir := Vector2.ZERO
	if raw_value is Vector2:
		raw_dir = (raw_value as Vector2).limit_length(1.0)

	_last_received_tick = cmd_tick

	return {
		"tick": cmd_tick,
		"dir": dir,
		"raw_dir": raw_dir,
		"aim": aim,
		"rot": rot,
		"jump": jump,
	}
