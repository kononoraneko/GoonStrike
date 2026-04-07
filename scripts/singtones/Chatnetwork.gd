## ChatNetwork.gd  —  Autoload
## Транслирует сообщения чата между всеми клиентами.
## GameHUD подписывается на chat_received/system_received для отображения.

extends Node

signal chat_received(sender_name: String, text: String)
signal system_received(text: String)

const MAX_LENGTH := 200


## Отправить сообщение от локального игрока.
func send(text: String) -> void:
	text = text.strip_edges().left(MAX_LENGTH)
	if text.is_empty():
		return
	var sender_name: String = Lobby.local_info.get("name", "?")
	_rpc_receive.rpc_id(1, text, sender_name)


## Отправить системное сообщение от сервера всем клиентам.
func send_system(text: String) -> void:
	if not multiplayer.is_server():
		return
	text = text.strip_edges().left(MAX_LENGTH)
	if text.is_empty():
		return
	_rpc_broadcast_system.rpc(text)


@rpc("any_peer", "reliable")
func _rpc_receive(text: String, sender_name: String) -> void:
	if not multiplayer.is_server():
		return
	text = text.strip_edges().left(MAX_LENGTH)
	if text.is_empty():
		return
	_rpc_broadcast.rpc(sender_name, text)


@rpc("authority", "reliable", "call_local")
func _rpc_broadcast(sender_name: String, text: String) -> void:
	chat_received.emit(sender_name, text)


@rpc("authority", "reliable", "call_local")
func _rpc_broadcast_system(text: String) -> void:
	system_received.emit(text)
