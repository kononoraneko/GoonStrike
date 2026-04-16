## GameHUD.gd
## Корневой узел UI. Инициализируется через setup(player, game_manager).
## Чат подключается снаружи — в HUDManager.

class_name GameHUD extends CanvasLayer

const BUY_MENU_SCENE: PackedScene = preload("res://scenes/ui/hud/buy_menu.tscn")

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
var _buy_menu: BuyMenu
var _money_label: Label


func _exit_tree() -> void:
	_disconnect_score_signals()


func _process(_delta: float) -> void:
	var show_sb := Input.is_action_pressed("scoreboard")
	scoreboard_panel.visible = show_sb
	if show_sb:
		_refresh_scoreboard()
	_update_money_hud()


func setup(player: OnlinePlayer, game_manager: GameManager) -> void:
	_game_manager = game_manager
	_disconnect_score_signals()
	player_hud.setup(player)
	chat_console.setup(player)
	_register_console_commands(player)
	_connect_score_signals_if_needed()
	_setup_buy_menu()
	_setup_money_label()


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("buy_menu"):
		if _buy_menu != null:
			if _buy_menu.visible:
				_buy_menu.close()
			else:
				if _game_manager != null:
					var buy_state := _game_manager.get_local_buy_availability()
					if not bool(buy_state.get("can_open_menu", false)):
						get_viewport().set_input_as_handled()
						return
				else:
					get_viewport().set_input_as_handled()
					return
				_buy_menu.open()
			get_viewport().set_input_as_handled()


func _setup_buy_menu() -> void:
	if _buy_menu != null:
		_buy_menu.queue_free()
		_buy_menu = null
	_buy_menu = BUY_MENU_SCENE.instantiate() as BuyMenu
	add_child(_buy_menu)
	_buy_menu.setup(_game_manager)


func _setup_money_label() -> void:
	if _money_label != null:
		_money_label.queue_free()
		_money_label = null
	if _game_manager == null or not _game_manager.is_economy_mode():
		return
	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 18)
	_money_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	_money_label.anchors_preset = Control.PRESET_TOP_RIGHT
	_money_label.anchor_left = 1.0
	_money_label.anchor_right = 1.0
	# Шире зона и обрезка — иначе длинная сумма рисуется поверх таймера по центру.
	_money_label.offset_left = -220.0
	_money_label.offset_right = -12.0
	_money_label.offset_top = 36.0
	_money_label.offset_bottom = 62.0
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_money_label.clip_text = true
	_money_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_money_label)


func _update_money_hud() -> void:
	if _money_label == null or _game_manager == null:
		return
	if not _game_manager.is_economy_mode():
		return
	var money := _game_manager.get_player_money(multiplayer.get_unique_id())
	_money_label.text = "$%d" % money
	# В меню закупок сумма уже в шапке — не дублируем в углу.
	_money_label.visible = _buy_menu == null or not _buy_menu.visible


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
