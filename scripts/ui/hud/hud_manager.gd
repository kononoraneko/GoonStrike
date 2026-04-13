## ─────────────────────────────────────────────────────────────────────────
## HUDManager.gd
## Создаёт и удаляет GameHUD для локального игрока.
## Живёт в CanvasLayer чтобы не зависеть от камеры.
 
class_name HUDManager extends CanvasLayer
 
@export var hud_scene: PackedScene
 
## Храним на случай если надо удалить при дисконнекте
var _hud: GameHUD = null
var _local_player_id: int = -1
var _chat_connected_cb: Callable
var _chat_disconnected_cb: Callable
 
 
func create_hud(player: OnlinePlayer) -> void:
	if hud_scene == null:
		push_error("HUDManager: hud_scene is not set")
		return

	var gm: GameManager = get_parent() as GameManager
	if _hud != null:
		_local_player_id = player.remote_player_id
		_hud.setup(player, gm)
		return

	_hud = hud_scene.instantiate() as GameHUD
	_local_player_id = player.remote_player_id
	add_child(_hud)
	_hud.setup(player, gm)

	# Подключаем чат: отправка → сеть, получение → HUD
	_hud.chat_console.message_sent.connect(ChatNetwork.send)
	ChatNetwork.chat_received.connect(_hud.chat_console.print_chat)
	ChatNetwork.system_received.connect(_hud.chat_console.print_system)
	ChatNetwork.console_feedback.connect(_hud.chat_console.print_console)

	# Системные события
	_chat_connected_cb = func(_id, info):
		if _hud and _hud.chat_console:
			_hud.chat_console.print_system("%s вошёл в игру" % info.get("name","?"))
	_chat_disconnected_cb = func(_id, info):
		if _hud and _hud.chat_console:
			_hud.chat_console.print_system("%s вышел из игры" % info.get("name","?"))
	Lobby.player_connected.connect(_chat_connected_cb)
	Lobby.player_disconnected.connect(_chat_disconnected_cb)
	
	#print("chat_received connections: ", 
		#ChatNetwork.chat_received.get_connections().size())
	#print("message_sent connections: ", 
		#_hud.chat_console.message_sent.get_connections().size())
	gm.round_started.connect(_on_round_started)
	gm.round_ended.connect(_on_round_ended)
	gm.team_score_changed.connect(_on_team_score_changed)
	gm.round_time_updated.connect(_on_round_time_updated)


## Локальный персонаж убран (смерть), но UI и чат остаются до респавна.
func freeze_for_local_death() -> void:
	if _hud != null:
		_hud.player_hud.unbind_player()


func remove_hud(id: int) -> void:
	if id == _local_player_id and _hud != null:
		_disconnect_hud_signals()
		_hud.queue_free()
		_hud = null
		_local_player_id = -1


func _disconnect_hud_signals() -> void:
	var gm: GameManager = get_parent() as GameManager
	if gm != null:
		if gm.round_started.is_connected(_on_round_started):
			gm.round_started.disconnect(_on_round_started)
		if gm.round_ended.is_connected(_on_round_ended):
			gm.round_ended.disconnect(_on_round_ended)
		if gm.team_score_changed.is_connected(_on_team_score_changed):
			gm.team_score_changed.disconnect(_on_team_score_changed)
		if gm.round_time_updated.is_connected(_on_round_time_updated):
			gm.round_time_updated.disconnect(_on_round_time_updated)

	if _hud == null:
		return
	if _hud.chat_console and _hud.chat_console.message_sent.is_connected(ChatNetwork.send):
		_hud.chat_console.message_sent.disconnect(ChatNetwork.send)
	if _hud.chat_console and ChatNetwork.chat_received.is_connected(_hud.chat_console.print_chat):
		ChatNetwork.chat_received.disconnect(_hud.chat_console.print_chat)
	if _hud.chat_console and ChatNetwork.system_received.is_connected(_hud.chat_console.print_system):
		ChatNetwork.system_received.disconnect(_hud.chat_console.print_system)
	if _hud.chat_console and ChatNetwork.console_feedback.is_connected(_hud.chat_console.print_console):
		ChatNetwork.console_feedback.disconnect(_hud.chat_console.print_console)
	if _chat_connected_cb.is_valid() and Lobby.player_connected.is_connected(_chat_connected_cb):
		Lobby.player_connected.disconnect(_chat_connected_cb)
	if _chat_disconnected_cb.is_valid() and Lobby.player_disconnected.is_connected(_chat_disconnected_cb):
		Lobby.player_disconnected.disconnect(_chat_disconnected_cb)
	_chat_connected_cb = Callable()
	_chat_disconnected_cb = Callable()


func _on_round_started(round_number: int) -> void:
	if _hud:
		_hud.show_label("Раунд %d" % round_number, 2.0)

func _on_round_ended(_winning_team: int) -> void:
	if _hud:
		_hud.show_label("Раунд окончен", 2.0)

func _on_team_score_changed(team: int, score: int) -> void:
	if _hud:
		_hud.update_team_score(team, score)

func _on_round_time_updated(seconds_left: float) -> void:
	if _hud:
		_hud.set_timer(seconds_left)
