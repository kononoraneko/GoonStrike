class_name NetworkComponent extends Node

## Отвечает за: буфер ввода, отправку команд на сервер,
## коррекцию позиции от сервера, репликацию состояния другим клиентам.

var owner_player: OnlinePlayer

# Клиент
var tick: int = 0
var input_buffer: Array = []   # команды, ожидающие подтверждения

# Сервер
var input_queue: Array = []
var last_processed_tick: int = 0

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
	input_queue.append(cmd)


## Сервер: обрабатывает все накопленные команды за кадр.
func process_server_queue() -> void:
	input_queue.sort_custom(func(a, b): return a.tick < b.tick)
	var processed := 0
	while input_queue.size() > 0 and processed < 5:
		var cmd: Dictionary = input_queue.pop_front()
		owner_player.movement.apply_movement(cmd)
		last_processed_tick = cmd.tick
		# Корректируем позицию у владельца и обновляем остальных
		owner_player.rpc_id(owner_player.remote_player_id, "client_correct_state",
			owner_player.global_transform.origin, last_processed_tick)
		owner_player.rpc("update_remote_state",
			owner_player.global_transform.origin, cmd)
		processed += 1
