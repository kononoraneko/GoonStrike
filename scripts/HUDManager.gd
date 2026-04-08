## ─────────────────────────────────────────────────────────────────────────
## HUDManager.gd
## Создаёт и удаляет GameHUD для локального игрока.
## Живёт в CanvasLayer чтобы не зависеть от камеры.
 
class_name HUDManager extends CanvasLayer
 
@export var hud_scene: PackedScene
 
## Храним на случай если надо удалить при дисконнекте
var _hud: GameHUD = null
var _local_player_id: int = -1
 
 
func create_hud(player: OnlinePlayer) -> void:
	if _hud != null:
		_hud.queue_free()
 
	if hud_scene == null:
		push_error("HUDManager: hud_scene is not set")
		return
 
	_hud = hud_scene.instantiate() as GameHUD
	_local_player_id = player.remote_player_id
	add_child(_hud)
 
	# Инициализируем HUD — он сам подпишется на сигналы игрока
	_hud.setup(player)
 
	# Подключаем чат: отправка → сеть, получение → HUD
	_hud.chat_console.message_sent.connect(ChatNetwork.send)
	ChatNetwork.chat_received.connect(_hud.chat_console.print_chat)
	ChatNetwork.system_received.connect(_hud.chat_console.print_system)
	ChatNetwork.console_feedback.connect(_hud.chat_console.print_console)
 
	# Системные события
	Lobby.player_connected.connect(
		func(id, info): _hud.chat_console.print_system("%s вошёл в игру" % info.get("name","?"))
	)
	Lobby.player_disconnected.connect(
		func(id, info): _hud.chat_console.print_system("%s вышел из игры" % info.get("name","?"))
	)
	
	#print("chat_received connections: ", 
		#ChatNetwork.chat_received.get_connections().size())
	#print("message_sent connections: ", 
		#_hud.chat_console.message_sent.get_connections().size())
 
 
func remove_hud(id: int) -> void:
	if id == _local_player_id and _hud != null:
		_hud.queue_free()
		_hud = null
