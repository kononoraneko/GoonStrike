## GameHUD.gd
## Корневой узел UI. Инициализируется через setup(player, game_manager).
## Чат подключается снаружи — в HUDManager.

class_name GameHUD extends CanvasLayer

@onready var player_hud: PlayerHUD = $PlayerHUD
@onready var chat_console: ChatConsole = $ChatConsole
@onready var round_timer_label: Label = $RoundTimerLabel
@onready var round_banner_label: Label = $RoundBannerLabel
@onready var scoreboard_panel: ColorRect = $ScoreboardPanel
@onready var score_title: Label = $ScoreboardPanel/MarginContainer/VBox/ScoreTitle
@onready var player_list: ItemList = $ScoreboardPanel/MarginContainer/VBox/PlayerList

var _game_manager: GameManager
var _banner_timer: SceneTreeTimer
var _score_signals_ok: bool = false


func _exit_tree() -> void:
	_disconnect_score_signals()


func _process(_delta: float) -> void:
	var show_sb := Input.is_action_pressed("scoreboard")
	scoreboard_panel.visible = show_sb
	if show_sb:
		_refresh_scoreboard()


func setup(player: OnlinePlayer, game_manager: GameManager) -> void:
	_game_manager = game_manager
	player_hud.setup(player)
	chat_console.setup(player)
	_register_console_commands(player)
	_connect_score_signals_if_needed()


func _connect_score_signals_if_needed() -> void:
	if _score_signals_ok or _game_manager == null:
		return
	if _game_manager.game_mode != null:
		var gmode: GameMode = _game_manager.game_mode
		gmode.ffa_score_changed.connect(_on_ffa_score_changed)
		gmode.team_score_changed.connect(_on_team_score_changed)
	if not _game_manager.match_stats_updated.is_connected(_on_match_stats_updated):
		_game_manager.match_stats_updated.connect(_on_match_stats_updated)
	_score_signals_ok = true


func _disconnect_score_signals() -> void:
	if not _score_signals_ok:
		return
	if _game_manager != null:
		if _game_manager.match_stats_updated.is_connected(_on_match_stats_updated):
			_game_manager.match_stats_updated.disconnect(_on_match_stats_updated)
		if _game_manager.game_mode != null:
			var gmode: GameMode = _game_manager.game_mode
			if gmode.ffa_score_changed.is_connected(_on_ffa_score_changed):
				gmode.ffa_score_changed.disconnect(_on_ffa_score_changed)
			if gmode.team_score_changed.is_connected(_on_team_score_changed):
				gmode.team_score_changed.disconnect(_on_team_score_changed)
	_score_signals_ok = false


func _on_ffa_score_changed(_player_id: int, _score: int) -> void:
	if scoreboard_panel.visible:
		_refresh_scoreboard()


func _on_team_score_changed(_team: int, _score: int) -> void:
	if scoreboard_panel.visible:
		_refresh_scoreboard()


func _on_match_stats_updated() -> void:
	if scoreboard_panel.visible:
		_refresh_scoreboard()


func _board_peer_ids_sorted() -> Array:
	var pids: Array = []
	for k in Lobby.players.keys():
		var pid := int(k)
		if GameManager.is_host_spectator(pid):
			continue
		pids.append(pid)
	pids.sort()
	return pids


func _stat_line_for_peer(pid: int) -> String:
	var name: String = Lobby.get_player_display_name(pid)
	var k: int = _game_manager.get_match_stat(pid, "k") if _game_manager else 0
	var d: int = _game_manager.get_match_stat(pid, "d") if _game_manager else 0
	var a: int = _game_manager.get_match_stat(pid, "a") if _game_manager else 0
	return "%s   %d / %d / %d" % [name, k, d, a]


func _refresh_scoreboard() -> void:
	player_list.clear()
	if _game_manager == null or _game_manager.game_mode == null:
		player_list.add_item("Нет данных режима")
		return
	score_title.text = "Игроки —  K / D / A "
	var gm: GameMode = _game_manager.game_mode
	if gm is DeathmatchMode:
		for pid in _board_peer_ids_sorted():
			player_list.add_item(_stat_line_for_peer(int(pid)))
	elif gm is TeamGameMode:
		var tm := gm as TeamGameMode
		player_list.add_item(
			"%s  %d  —  %d  %s" % [
				tm.get_team_name(1), tm.get_team_score(1),
				tm.get_team_score(2), tm.get_team_name(2),
			]
		)
		player_list.add_item("────────────────")
		var alive_map: Dictionary = gm.get_alive_peers()
		var has_alive_tracking: bool = not alive_map.is_empty()
		for pid in _board_peer_ids_sorted():
			var team: int = tm.get_team(int(pid))
			var tname: String = tm.get_team_name(team)
			var life := ""
			if has_alive_tracking:
				life = "  жив" if alive_map.get(int(pid), false) else "  мёртв"
			player_list.add_item("%s   [%s]%s   %s" % [Lobby.get_player_display_name(int(pid)), tname, life, _kda_suffix(int(pid))])
	else:
		player_list.add_item("Режим без таблицы счёта")
		for pid in _board_peer_ids_sorted():
			player_list.add_item(_stat_line_for_peer(int(pid)))


func _kda_suffix(pid: int) -> String:
	var k: int = _game_manager.get_match_stat(pid, "k") if _game_manager else 0
	var d: int = _game_manager.get_match_stat(pid, "d") if _game_manager else 0
	var a: int = _game_manager.get_match_stat(pid, "a") if _game_manager else 0
	return "%d/%d/%d" % [k, d, a]


func set_timer(seconds_left: float) -> void:
	if seconds_left <= 0.0:
		round_timer_label.text = ""
		round_timer_label.visible = false
		return
	round_timer_label.visible = true
	var t: int = int(floor(seconds_left))
	var m: int = t / 60
	var s: int = t % 60
	round_timer_label.text = "%d:%02d" % [m, s]


func show_label(text: String, duration: float) -> void:
	if _banner_timer != null and is_instance_valid(_banner_timer) and _banner_timer.timeout.is_connected(_hide_banner):
		_banner_timer.timeout.disconnect(_hide_banner)
	round_banner_label.text = text
	round_banner_label.visible = true
	_banner_timer = get_tree().create_timer(maxf(duration, 0.05))
	_banner_timer.timeout.connect(_hide_banner, CONNECT_ONE_SHOT)


func _hide_banner() -> void:
	round_banner_label.visible = false


func update_team_score(_team: int, _score: int) -> void:
	if scoreboard_panel.visible:
		_refresh_scoreboard()


func _register_console_commands(player: OnlinePlayer) -> void:
	var mv := player.movement
	var hc := player.health_component

	ConsoleCommands.register("speed", mv, "speed", "Скорость", 1.0, 50.0, "float")
	ConsoleCommands.register("jump", mv, "jump_velocity", "Сила прыжка", 5.0, 100.0, "float")
	ConsoleCommands.register("sensitivity", mv, "mouse_sensitivity", "Чувствительность", 0.0001, 0.01, "float")
	ConsoleCommands.register("maxhp", hc, "max_health", "Максимальное HP", 1.0, 1000.0, "int")
	ConsoleCommands.register_callable(
		"potato",
		func() -> bool: return Settings.is_potato_mode(),
		func(v: bool) -> void: Settings.set_potato_mode(v),
		"Минимальная графика (низкое разрешение, без MSAA, низкие тени). false — откат.",
		0,
		0,
		"bool"
	)
