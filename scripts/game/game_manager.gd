## GameManager.gd
## Оркестратор игровой сцены. Делегирует спавн → PlayerSpawner,
## HUD → HUDManager и правила матча → GameMode.

class_name GameManager extends Node3D

signal player_spawned(id: int, info: Dictionary)
signal player_despawned(id: int, info: Dictionary)
signal player_died(victim_id: int, attacker_id: int)

signal round_started(round_number: int)
signal round_ended(winning_team: int)
signal team_score_changed(team: int, score: int)
signal round_time_updated(seconds_left: float)
signal match_stats_updated
signal money_changed(peer_id: int, amount: int)
signal buy_availability_changed(availability: Dictionary)

const HOST_PEER_ID := 1
const WORLD_PICKUP_SCENE: PackedScene = preload("res://scenes/weapons/pickup_scene.tscn")
const DROP_FORWARD_OFFSET := 0.85
const DROP_UP_OFFSET := 0.35
const PICKUP_RAY_MAX_DISTANCE := 3.5
const PICKUP_RAY_COLLISION_MASK := 0xFFFFFFFF
const _PICKUP_MAX_AIM_DOT := 0.906
const _PICKUP_MAX_ORIGIN_DIST := 3.0
const _PROXIMITY_PICKUP_MAX_DIST := 2.6
const _PROXIMITY_HINT_POS_EPS := 2.0
const _DROP_INTERACT_COOLDOWN_MSEC := 500

const STARTING_MONEY   := 800
const ROUND_WIN_BONUS  := 3250
const ROUND_LOSS_BONUS := 1900
const KILL_REWARD       := 300
const MAX_MONEY         := 16000

var _round_end_time: float = 0.0
## peer_id → int (текущие деньги игрока; сервер — источник истины).
var _player_money: Dictionary = {}
## peer_id → { "k", "d", "a" } — ведётся на сервере, реплицируется на клиенты.
var _match_stats: Dictionary = {}
## Уникальный id для дропнутых пикапов (RPC по пути узла на клиенте ненадёжен).
var _next_world_pickup_id: int = 0
var _last_buy_availability: Dictionary = {}
var _match_id: String = ""

@onready var spawner: PlayerSpawner = $PlayerSpawner
@onready var hud_manager: HUDManager = $HUDManager

var game_mode: GameMode
var _shared_sync_sent: Dictionary = {}


static func is_host_spectator(id: int) -> bool:
	return id == HOST_PEER_ID


func _ready() -> void:
	add_to_group("game_manager")
	_install_game_mode_from_lobby()
	_setup_game_mode()

	Lobby.player_connected.connect(_on_player_connected)
	Lobby.player_disconnected.connect(_on_player_disconnected)
	Lobby.server_disconnected.connect(_on_server_disconnected)
	Lobby.all_players_loaded.connect(start_game)

	spawner.player_scene = Settings.get_selected_character_scene()

	for id in Lobby.players:
		_spawn(id)

	Lobby.notify_loaded()
	call_deferred("_deferred_reconcile_spawns")


func _deferred_reconcile_spawns() -> void:
	if game_mode and not game_mode.should_spawn_on_player_connected():
		return
	for id in Lobby.players.keys():
		if spawner.get_player(id) == null:
			_spawn(id)


func _process(_delta: float) -> void:
	if _round_end_time > 0.0:
		var left := _round_end_time - Time.get_ticks_msec() / 1000.0
		round_time_updated.emit(maxf(left, 0.0))
	var buy_state := get_local_buy_availability()
	if buy_state != _last_buy_availability:
		_last_buy_availability = buy_state
		buy_availability_changed.emit(buy_state)


func _install_game_mode_from_lobby() -> void:
	for c in get_children():
		if c is GameMode:
			remove_child(c)
			c.queue_free()
	var mode_id: String = Lobby.selected_mode_id
	var scene: PackedScene = GameModeCatalog.get_mode_scene(mode_id)
	var inst: GameMode = scene.instantiate() as GameMode
	inst.name = "ActiveGameMode"
	add_child(inst)
	game_mode = inst
	spawner.apply_mode_from_lobby(mode_id)


func _setup_game_mode() -> void:
	if game_mode:
		game_mode.setup(self)
		game_mode.ffa_score_changed.connect(_on_ffa_score_changed)
		game_mode.ffa_match_finished.connect(_on_ffa_match_finished)
		game_mode.team_score_changed.connect(team_score_changed.emit)
		game_mode.team_match_finished.connect(_on_team_match_finished)
		game_mode.round_started.connect(_on_round_started)
		game_mode.round_ended.connect(_on_round_ended)


func _on_round_started(round_number: int) -> void:
	if multiplayer.is_server() and round_number > 1 and game_mode is TeamEliminationMode:
		_clear_world_weapon_pickups_local()
		if multiplayer.has_multiplayer_peer():
			_rpc_clear_world_weapon_pickups.rpc()
	round_started.emit(round_number)
	var duration := game_mode.get_round_timer_duration()
	if duration > 0.0:
		_round_end_time = Time.get_ticks_msec() / 1000.0 + duration
	if multiplayer.is_server():
		for p in multiplayer.get_peers():
			_rpc_client_round_started.rpc_id(p, round_number, duration)


func _on_round_ended(winning_team: int) -> void:
	_round_end_time = 0.0
	round_ended.emit(winning_team)
	if multiplayer.is_server():
		_award_round_money(winning_team)
		for p in multiplayer.get_peers():
			_rpc_client_round_ended.rpc_id(p, winning_team)


func _on_team_match_finished(winning_team: int, score: int) -> void:
	if not (game_mode is TeamGameMode):
		return
	var tm := game_mode as TeamGameMode
	var tname := tm.get_team_name(winning_team)
	ChatNetwork.send_system("[Match] Победа: %s (%d)" % [tname, score])
	var winners: Array[int] = []
	for pid in tm.get_team_members(winning_team):
		winners.append(int(pid))
	_submit_match_result(winners)


# ── Спавн / деспавн ───────────────────────────────────────────────────────

func _on_player_connected(id: int, _info: Dictionary) -> void:
	if spawner.get_player(id) != null:
		return
	if game_mode and not game_mode.should_spawn_on_player_connected():
		return
	if Lobby.players.has(id):
		_spawn(id)


func _on_player_disconnected(id: int, info: Dictionary) -> void:
	_despawn_player(id, info)
	_shared_sync_sent.erase(id)
	game_mode.on_player_despawned(id, info)


func _spawn(id: int) -> void:
	if not Lobby.players.has(id):
		return

	_ensure_match_stat_entry(id)

	var had_existing := spawner.get_player(id) != null
	var player := spawner.spawn(id, Lobby.players[id])
	if player == null:
		return

	if had_existing:
		spawner.reapply_spawn_transform(id)

	_wire_player_events(player)
	if multiplayer.is_server() and not _shared_sync_sent.has(id):
		ServerConfig.sync_to_peer(id)
		_shared_sync_sent[id] = true
	player_spawned.emit(id, Lobby.players[id])

	if not is_host_spectator(id):
		player.reset_dm_loadout_tracking()
		game_mode.on_player_spawned(id, player, Lobby.players[id], had_existing)
		player.set_alive_state()
		if multiplayer.is_server():
			player.health_component.reset_health()

	if multiplayer.is_server() and not is_host_spectator(id):
		if not _player_money.has(id):
			_set_money(id, STARTING_MONEY)
		else:
			_set_money(id, get_player_money(id))
		if game_mode != null and game_mode is TeamGameMode:
			var tm := game_mode as TeamGameMode
			tm.sync_scores_to_peer(id)
			if game_mode.get_round_timer_duration() > 0.0 and _round_end_time > 0.0:
				var remaining := maxf(_round_end_time - Time.get_ticks_msec() / 1000.0, 0.0)
				_sync_late_join_round_state.rpc_id(id, tm.get_current_round(), remaining)

	if multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		call_deferred("_late_join_sync_session_state_to_peer", id)

	if id == multiplayer.get_unique_id():
		hud_manager.create_hud(player)


func _despawn_player(id: int, info: Dictionary, keep_local_hud_for_respawn: bool = false) -> void:
	spawner.despawn(id)
	if keep_local_hud_for_respawn and id == multiplayer.get_unique_id():
		hud_manager.freeze_for_local_death()
	else:
		hud_manager.remove_hud(id)
	player_despawned.emit(id, info)


func _wire_player_events(player: OnlinePlayer) -> void:
	if player.health_component.died.is_connected(_on_player_died):
		return
	player.health_component.died.connect(_on_player_died)


func _on_player_died(victim_id: int, attacker_id: int, assist_id: int = 0) -> void:
	if not multiplayer.is_server():
		return

	_record_kill_death_assist(victim_id, attacker_id, assist_id)
	if attacker_id > 0 and attacker_id != victim_id and not is_host_spectator(attacker_id):
		_add_money(attacker_id, KILL_REWARD)
	match_stats_updated.emit()
	_rpc_sync_match_stats.rpc(_pack_match_stats_for_net())
	_broadcast_killfeed(victim_id, attacker_id)
	_rpc_on_player_died.rpc(victim_id, attacker_id)
	if not is_host_spectator(victim_id):
		game_mode.on_player_died(victim_id, attacker_id)


@rpc("authority", "reliable", "call_local")
func _rpc_on_player_died(victim_id: int, attacker_id: int) -> void:
	var info: Dictionary = Lobby.players.get(victim_id, {}) as Dictionary
	var keep_ui := victim_id == multiplayer.get_unique_id()
	_despawn_player(victim_id, info, keep_ui)
	player_died.emit(victim_id, attacker_id)


func schedule_respawn(peer_id: int, delay_sec: float) -> void:
	if not multiplayer.is_server():
		return
	var timer := get_tree().create_timer(max(delay_sec, 0.0))
	timer.timeout.connect(func(): _rpc_respawn_player.rpc(peer_id))


@rpc("authority", "reliable", "call_local")
func _rpc_respawn_player(peer_id: int) -> void:
	_spawn(peer_id)


# ── Старт / финиш игры ────────────────────────────────────────────────────

func start_game() -> void:
	if _match_id.is_empty():
		_match_id = _create_match_id()
	for pid in Lobby.players.keys():
		_ensure_match_stat_entry(int(pid))
		if multiplayer.is_server() and not is_host_spectator(int(pid)):
			_set_money(int(pid), STARTING_MONEY)
	game_mode.on_game_started()
	var mode_name := GameModeCatalog.display_name(Lobby.selected_mode_id)
	var msg := "[%s] Матч начался" % mode_name
	print(msg)
	if multiplayer.is_server():
		_rpc_sync_match_stats.rpc(_pack_match_stats_for_net())
		ChatNetwork.send_system(msg)
	match_stats_updated.emit()


func _on_ffa_score_changed(player_id: int, score: int) -> void:
	var player_name: String = Lobby.get_player_display_name(player_id)
	var msg: String = "[DM] %s: %d" % [player_name, score]
	print(msg)
	ChatNetwork.send_system(msg)


func _on_ffa_match_finished(winner_id: int, score: int) -> void:
	var winner_name: String = Lobby.get_player_display_name(winner_id)
	var msg: String = "[DM] Победитель: %s (%d фрагов)" % [winner_name, score]
	print(msg)
	ChatNetwork.send_system(msg)
	_submit_match_result([winner_id])


func _broadcast_killfeed(victim_id: int, attacker_id: int) -> void:
	var victim_name: String = Lobby.get_player_display_name(victim_id)
	var msg: String
	if attacker_id <= 0:
		msg = "[KILL] %s погиб" % victim_name
	elif attacker_id == victim_id:
		msg = "[KILL] %s самоустранился" % victim_name
	else:
		var attacker_name: String = Lobby.get_player_display_name(attacker_id)
		msg = "[KILL] %s → %s" % [attacker_name, victim_name]
	print(msg)
	ChatNetwork.send_system(msg)


func _submit_match_result(winner_ids: Array[int]) -> void:
	if not multiplayer.is_server():
		return
	var backend := get_node_or_null("/root/BackendClient")
	if backend == null or not backend.has_method("submit_match_result"):
		return
	var map_id := "unknown"
	if Lobby.selected_map != null:
		map_id = Lobby.selected_map.id if not Lobby.selected_map.id.is_empty() else Lobby.selected_map.resource_path
	backend.call("submit_match_result", _match_id, Lobby.selected_mode_id, map_id, _pack_match_stats_for_net(), winner_ids)


func _create_match_id() -> String:
	return "%s-%d" % [Lobby.selected_mode_id, Time.get_unix_time_from_system()]


func _on_server_disconnected() -> void:
	SceneRouter.go_main_menu_with_error("Потеряно соединение с сервером")


# ── Match stats ────────────────────────────────────────────────────────────

func _ensure_match_stat_entry(peer_id: int) -> void:
	if peer_id <= 0:
		return
	if not _match_stats.has(peer_id):
		_match_stats[peer_id] = {"k": 0, "d": 0, "a": 0}


func _increment_match_stat(peer_id: int, key: String, delta: int) -> void:
	if peer_id <= 0:
		return
	_ensure_match_stat_entry(peer_id)
	var e: Dictionary = _match_stats[peer_id]
	e[key] = int(e.get(key, 0)) + delta
	_match_stats[peer_id] = e


func _record_kill_death_assist(victim_id: int, attacker_id: int, assist_id: int) -> void:
	_increment_match_stat(victim_id, "d", 1)
	if attacker_id > 0 and attacker_id != victim_id:
		_increment_match_stat(attacker_id, "k", 1)
	if assist_id > 0 and assist_id != victim_id and assist_id != attacker_id:
		_increment_match_stat(assist_id, "a", 1)


func _pack_match_stats_for_net() -> Dictionary:
	var out: Dictionary = {}
	for k in _match_stats.keys():
		var e: Dictionary = _match_stats[k]
		out[int(k)] = {"k": int(e.get("k", 0)), "d": int(e.get("d", 0)), "a": int(e.get("a", 0))}
	return out


func _apply_match_stats_from_net(packed: Dictionary) -> void:
	_match_stats.clear()
	for k in packed.keys():
		var pid := int(k)
		var v: Variant = packed[k]
		if v is Dictionary:
			var d: Dictionary = v as Dictionary
			_match_stats[pid] = {
				"k": int(d.get("k", 0)),
				"d": int(d.get("d", 0)),
				"a": int(d.get("a", 0)),
			}


@rpc("authority", "reliable")
func _rpc_sync_match_stats(packed: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_apply_match_stats_from_net(packed)
	match_stats_updated.emit()


func get_match_stat(peer_id: int, key: String) -> int:
	var e: Dictionary = _match_stats.get(peer_id, {}) as Dictionary
	return int(e.get(key, 0))


func get_kill_counts_dict_for_board() -> Dictionary:
	var out: Dictionary = {}
	for pid in _match_stats.keys():
		out[int(pid)] = get_match_stat(int(pid), "k")
	return out


# ── Economy ─────────────────────────────────────────────────────────────────

func get_player_money(peer_id: int) -> int:
	return int(_player_money.get(peer_id, 0))


func _set_money(peer_id: int, amount: int) -> void:
	amount = clampi(amount, 0, MAX_MONEY)
	_player_money[peer_id] = amount
	money_changed.emit(peer_id, amount)
	if multiplayer.is_server():
		if peer_id == 1:
			_rpc_sync_money(amount)
		else:
			_rpc_sync_money.rpc_id(peer_id, amount)


func _add_money(peer_id: int, delta: int) -> void:
	var cur := get_player_money(peer_id)
	_set_money(peer_id, cur + delta)


func _award_round_money(winning_team: int) -> void:
	if not multiplayer.is_server():
		return
	if not (game_mode is TeamGameMode):
		return
	var tm := game_mode as TeamGameMode
	for pid in Lobby.players.keys():
		var id := int(pid)
		if is_host_spectator(id):
			continue
		var team := tm.get_team(id)
		if team == TeamGameMode.Team.NONE:
			continue
		if team == winning_team:
			_add_money(id, ROUND_WIN_BONUS)
		else:
			_add_money(id, ROUND_LOSS_BONUS)


func is_economy_mode() -> bool:
	return game_mode is TeamEliminationMode


func get_local_buy_availability() -> Dictionary:
	var state := {
		"can_open_menu": false,
		"can_buy_now": false,
		"reason_code": "unknown",
		"hint_text": "",
	}
	if game_mode == null:
		state.reason_code = "no_mode"
		return state
	var id := multiplayer.get_unique_id()
	if is_host_spectator(id):
		state.reason_code = "spectator"
		return state
	var pl := spawner.get_player(id)
	if pl == null:
		state.reason_code = "no_player"
		return state
	if pl.is_dead:
		state.reason_code = "dead"
		return state
	if game_mode.can_player_buy(pl):
		state.can_open_menu = true
		state.can_buy_now = true
		state.reason_code = "allowed"
		state.hint_text = game_mode.get_buy_menu_status_hint(pl)
		return state
	state.reason_code = "rules_blocked"
	state.hint_text = game_mode.get_buy_menu_status_hint(pl)
	return state


## Локальное зеркало правил покупки (состояние с сервера / синхронизация). Решение о покупке — только rpc_request_buy на сервере.
func can_local_player_buy() -> bool:
	return bool(get_local_buy_availability().get("can_buy_now", false))


func get_local_buy_menu_status_hint() -> String:
	return String(get_local_buy_availability().get("hint_text", ""))


## Меню не открываем без локального «можно купить» (те же правила, что game_mode.can_player_buy на сервере).
func can_open_buy_menu() -> bool:
	return bool(get_local_buy_availability().get("can_open_menu", false))


@rpc("authority", "reliable")
func _rpc_sync_money(amount: int) -> void:
	var local_id := multiplayer.get_unique_id()
	_player_money[local_id] = amount
	money_changed.emit(local_id, amount)


@rpc("any_peer", "reliable")
func rpc_request_buy(weapon_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	var pl := spawner.get_player(sender_id)
	if pl == null or pl.is_dead:
		return
	# Единственная доверенная проверка: клиент лишь запрашивает.
	if not game_mode.can_player_buy(pl):
		return
	var data := load(weapon_path) as WeaponData
	if data == null:
		return
	if is_economy_mode():
		var cur := get_player_money(sender_id)
		if cur < data.price:
			return
		_add_money(sender_id, -data.price)
	if pl.weapon_holder.has_primary_weapon() and game_mode.should_drop_weapon_on_buy_replace():
		_server_drop_player_weapon(pl)
	rpc_equip_weapon_data.rpc(sender_id, weapon_path)


# ── Round sync RPCs ────────────────────────────────────────────────────────

@rpc("authority", "reliable")
func _sync_late_join_round_state(round_number: int, remaining_sec: float) -> void:
	if multiplayer.is_server():
		return
	_round_end_time = Time.get_ticks_msec() / 1000.0 + remaining_sec
	round_started.emit(round_number)


@rpc("authority", "reliable")
func _rpc_client_round_started(round_number: int, duration_sec: float) -> void:
	if multiplayer.is_server():
		return
	if duration_sec > 0.0:
		_round_end_time = Time.get_ticks_msec() / 1000.0 + duration_sec
	round_started.emit(round_number)


@rpc("authority", "reliable")
func _rpc_client_round_ended(winning_team: int) -> void:
	if multiplayer.is_server():
		return
	_round_end_time = 0.0
	round_ended.emit(winning_team)


# ── Weapon equip / drop / pickup (server-authoritative) ───────────────────
#
# Тип оружия задаётся только WeaponData (resource_path); отдельные RPC под
# каждую модель не нужны — достаточно одного запроса дропа текущего слота.
#
# Безопасность:
# - server_request_drop_weapon / server_request_use_pickup /
#   server_request_proximity_pickup: на сервере
#   multiplayer.get_remote_sender_id() == peer_id — нельзя дропнуть/подобрать
#   за другого игрока.
# - Подбор: клиент шлёт луч прицела; сервер сверяет его с своим состоянием
#   игрока и raycast по миру (стены блокируют).
# - rpc_* с authority рассылает хост.

@rpc("authority", "reliable")
func rpc_sync_world_pickups_snapshot(entries: Array) -> void:
	for raw in entries:
		if raw is not Dictionary:
			continue
		var e: Dictionary = raw as Dictionary
		var nid := int(e.get("id", 0))
		if nid <= 0:
			continue
		if _find_pickup_by_network_id(nid) != null:
			continue
		var path := String(e.get("data_path", ""))
		if path.is_empty():
			continue
		var pos: Vector3 = e.get("pos", Vector3.ZERO) as Vector3
		var vel: Vector3 = e.get("vel", Vector3.ZERO) as Vector3
		_spawn_dropped_pickup_local(
			path,
			int(e.get("ammo_in_mag", 0)),
			int(e.get("ammo_reserve", 0)),
			pos,
			vel,
			nid
		)


@rpc("authority", "reliable", "call_local")
func rpc_equip_weapon_data(peer_id: int, data_path: String) -> void:
	var pl := spawner.get_player(peer_id)
	if pl == null:
		return
	pl.weapon_holder.equip_weapon_data_local(data_path)


@rpc("authority", "reliable", "call_local")
func rpc_equip_primary_from_world(peer_id: int, data_path: String, ammo_in_mag: int, ammo_reserve: int) -> void:
	var pl := spawner.get_player(peer_id)
	if pl == null:
		return
	pl.weapon_holder.equip_primary_from_world(data_path, ammo_in_mag, ammo_reserve)


@rpc("authority", "reliable", "call_local")
func rpc_clear_primary_weapon(peer_id: int) -> void:
	var pl := spawner.get_player(peer_id)
	if pl == null:
		return
	pl.weapon_holder.clear_current_weapon()


@rpc("any_peer", "reliable")
func server_request_drop_weapon(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		return
	var pl := spawner.get_player(peer_id)
	if pl == null:
		return
	_server_drop_player_weapon(pl)


@rpc("any_peer", "reliable")
func server_request_use_pickup(peer_id: int, aim_origin: Vector3, aim_direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		return
	var pl := spawner.get_player(peer_id)
	if pl == null or pl.is_dead:
		return
	if Time.get_ticks_msec() < pl.interact_cooldown_until_msec:
		return
	if not _pickup_client_aim_matches_server(pl, aim_origin, aim_direction):
		return
	var aim := _get_server_pickup_aim(pl)
	var origin: Vector3 = aim["origin"]
	var direction: Vector3 = aim["direction"]
	var pickup := _find_weapon_pickup_along_ray(origin, direction)
	if pickup == null:
		return
	_server_handle_primary_pickup(pl, pickup, true)


@rpc("any_peer", "reliable")
func server_request_proximity_pickup(peer_id: int, network_pickup_id: int, client_pickup_pos: Vector3, data_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		return
	var pl := spawner.get_player(peer_id)
	if pl == null or pl.is_dead:
		return
	if Time.get_ticks_msec() < pl.interact_cooldown_until_msec:
		return
	var pickup := _resolve_pickup_from_client_hint(network_pickup_id, client_pickup_pos, data_path)
	if pickup == null:
		return
	if pl.global_position.distance_to(pickup.global_position) > _PROXIMITY_PICKUP_MAX_DIST:
		return
	# Только пустой слот — без свапа (свап только по лучу + use, иначе цепочка подбор/выброс).
	if pl.weapon_holder.has_primary_weapon():
		return
	_server_handle_primary_pickup(pl, pickup, false)


@rpc("any_peer", "reliable")
func server_weapon_sync_request(for_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != for_peer_id:
		return
	var pl := spawner.get_player(for_peer_id)
	if pl == null or pl.weapon_holder.current_weapon == null:
		return
	var snapshot := pl.weapon_holder.create_drop_snapshot()
	var data_path := String(snapshot.get("data_path", ""))
	if data_path.is_empty():
		return
	rpc_equip_primary_from_world.rpc(
		for_peer_id,
		data_path,
		int(snapshot.get("ammo_in_mag", 0)),
		int(snapshot.get("ammo_reserve", 0))
	)


func _server_drop_player_weapon(player: OnlinePlayer) -> bool:
	if player == null or player.weapon_holder == null:
		return false
	var cw := player.weapon_holder.current_weapon
	if cw != null and cw.data != null and not cw.data.can_drop:
		return false
	var snapshot := player.weapon_holder.create_drop_snapshot()
	var data_path := String(snapshot.get("data_path", ""))
	if data_path.is_empty():
		return false
	player.interact_cooldown_until_msec = Time.get_ticks_msec() + _DROP_INTERACT_COOLDOWN_MSEC
	_spawn_world_pickup(player, data_path, int(snapshot.get("ammo_in_mag", 0)), int(snapshot.get("ammo_reserve", 0)))
	rpc_clear_primary_weapon.rpc(player.remote_player_id)
	return true


func _server_handle_primary_pickup(player: OnlinePlayer, pickup: WeaponPickup, requested_via_use: bool) -> bool:
	if player == null or player.weapon_holder == null or pickup == null:
		return false
	if not pickup.is_available():
		return false
	var has_weapon := player.weapon_holder.has_primary_weapon()
	if has_weapon:
		if not requested_via_use or not pickup.use_to_swap_if_slot_busy:
			return false
	else:
		if not pickup.auto_pickup_if_slot_empty and not requested_via_use:
			return false

	var data_path := pickup.get_pickup_data_path()
	if data_path.is_empty():
		return false
	var ammo_state := pickup.get_pickup_ammo_state()
	var target_mag := int(ammo_state.get("ammo_in_mag", 0))
	var target_reserve := int(ammo_state.get("ammo_reserve", 0))

	if has_weapon:
		var old_snapshot := player.weapon_holder.create_drop_snapshot()
		var old_data_path := String(old_snapshot.get("data_path", ""))
		if not old_data_path.is_empty():
			_spawn_world_pickup(
				player,
				old_data_path,
				int(old_snapshot.get("ammo_in_mag", 0)),
				int(old_snapshot.get("ammo_reserve", 0))
			)

	rpc_equip_primary_from_world.rpc(player.remote_player_id, data_path, target_mag, target_reserve)
	pickup.consume_on_server()
	return true


func _compute_safe_drop_spawn(player: OnlinePlayer) -> Dictionary:
	var forward := (-player.global_transform.basis.z).normalized()
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	var start: Vector3 = player.global_position + Vector3.UP * 1.0
	var target: Vector3 = start + forward * DROP_FORWARD_OFFSET + Vector3.UP * DROP_UP_OFFSET
	var space := get_world_3d().direct_space_state
	var pq := PhysicsRayQueryParameters3D.new()
	pq.from = start
	pq.to = target
	pq.collision_mask = PICKUP_RAY_COLLISION_MASK
	pq.exclude = [player]
	var hit: Dictionary = space.intersect_ray(pq)
	var wall_hit: bool = not hit.is_empty()
	var drop_pos: Vector3 = target
	var wall_normal := Vector3.UP
	if wall_hit:
		var hp: Vector3 = hit.get("position", Vector3.ZERO) as Vector3
		wall_normal = hit.get("normal", Vector3.UP) as Vector3
		drop_pos = hp + wall_normal * 0.15
	var linear_vel := Vector3.ZERO
	if wall_hit:
		linear_vel = wall_normal * 0.45 + Vector3.UP * 0.35
	else:
		linear_vel = forward * 2.0 + Vector3.UP * 0.45
	return {"position": drop_pos, "linear_velocity": linear_vel}


func _spawn_world_pickup(player: OnlinePlayer, data_path: String, ammo_in_mag: int, ammo_reserve: int) -> void:
	if WORLD_PICKUP_SCENE == null:
		return
	var spawn := _compute_safe_drop_spawn(player)
	var drop_pos: Vector3 = spawn["position"]
	var linear_vel: Vector3 = spawn["linear_velocity"]
	# Высокоуровневый мультиплеер не реплицирует add_child — иначе пикап есть только
	# на сервере и клиенты не видят меш. Рассылаем спавн с authority + call_local.
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_next_world_pickup_id += 1
			var nid := _next_world_pickup_id
			rpc_spawn_dropped_pickup.rpc(data_path, ammo_in_mag, ammo_reserve, drop_pos, linear_vel, nid)
	else:
		_next_world_pickup_id += 1
		_spawn_dropped_pickup_local(data_path, ammo_in_mag, ammo_reserve, drop_pos, linear_vel, _next_world_pickup_id)


@rpc("authority", "reliable", "call_local")
func rpc_spawn_dropped_pickup(data_path: String, ammo_in_mag: int, ammo_reserve: int, drop_pos: Vector3, linear_vel: Vector3, network_pickup_id: int) -> void:
	_spawn_dropped_pickup_local(data_path, ammo_in_mag, ammo_reserve, drop_pos, linear_vel, network_pickup_id)


func _spawn_dropped_pickup_local(data_path: String, ammo_in_mag: int, ammo_reserve: int, drop_pos: Vector3, linear_vel: Vector3, network_pickup_id: int) -> void:
	if WORLD_PICKUP_SCENE == null:
		return
	var pickup := WORLD_PICKUP_SCENE.instantiate() as WeaponPickup
	if pickup == null:
		return
	pickup.network_pickup_id = network_pickup_id
	pickup.freeze = true
	var parent := _get_world_pickups_root()
	parent.add_child(pickup)
	pickup.global_position = drop_pos
	pickup.setup_world_pickup(data_path, ammo_in_mag, ammo_reserve)
	var vel := linear_vel
	get_tree().create_timer(0.0).timeout.connect(func():
		if is_instance_valid(pickup):
			pickup.freeze = false
			pickup.linear_velocity = vel
	)


@rpc("authority", "reliable", "call_local")
func rpc_remove_world_pickup(network_pickup_id: int) -> void:
	if network_pickup_id <= 0:
		return
	for n in get_tree().get_nodes_in_group("weapon_pickups"):
		if n is WeaponPickup and (n as WeaponPickup).network_pickup_id == network_pickup_id:
			(n as WeaponPickup).queue_free()
			return


func _clear_world_weapon_pickups_local() -> void:
	for n in get_tree().get_nodes_in_group("weapon_pickups"):
		if n is Node:
			(n as Node).queue_free()


@rpc("authority", "reliable")
func _rpc_clear_world_weapon_pickups() -> void:
	_clear_world_weapon_pickups_local()


func _get_world_pickups_root() -> Node:
	# Узел Game в уровне — не родитель SpawnPoints; дропы вешаем на корень уровня.
	var level := get_parent()
	if level != null:
		return level
	return self


func _late_join_sync_session_state_to_peer(joining_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not multiplayer.has_multiplayer_peer():
		return
	if joining_peer_id == multiplayer.get_unique_id():
		return
	var pickup_entries: Array = []
	for node in get_tree().get_nodes_in_group("weapon_pickups"):
		if node is not WeaponPickup:
			continue
		var p := node as WeaponPickup
		if p.network_pickup_id <= 0 or not p.is_available():
			continue
		pickup_entries.append({
			"id": p.network_pickup_id,
			"data_path": p.get_pickup_data_path(),
			"ammo_in_mag": p.ammo_in_mag,
			"ammo_reserve": p.ammo_reserve,
			"pos": p.global_position,
			"vel": p.linear_velocity,
		})
	rpc_sync_world_pickups_snapshot.rpc_id(joining_peer_id, pickup_entries)
	for pid in Lobby.players.keys():
		var holder_id := int(pid)
		var pl := spawner.get_player(holder_id)
		if pl == null or pl.weapon_holder == null:
			continue
		if is_host_spectator(holder_id):
			continue
		if not pl.weapon_holder.has_primary_weapon():
			rpc_clear_primary_weapon.rpc_id(joining_peer_id, holder_id)
			continue
		var snap := pl.weapon_holder.create_drop_snapshot()
		var path := String(snap.get("data_path", ""))
		if path.is_empty():
			rpc_clear_primary_weapon.rpc_id(joining_peer_id, holder_id)
			continue
		rpc_equip_primary_from_world.rpc_id(
			joining_peer_id,
			holder_id,
			path,
			int(snap.get("ammo_in_mag", 0)),
			int(snap.get("ammo_reserve", 0))
		)


func _find_pickup_by_network_id(network_pickup_id: int) -> WeaponPickup:
	if network_pickup_id <= 0:
		return null
	for node in get_tree().get_nodes_in_group("weapon_pickups"):
		if node is WeaponPickup and (node as WeaponPickup).network_pickup_id == network_pickup_id:
			return node as WeaponPickup
	return null


func _resolve_pickup_from_client_hint(network_pickup_id: int, client_pickup_pos: Vector3, data_path: String) -> WeaponPickup:
	if network_pickup_id > 0:
		return _find_pickup_by_network_id(network_pickup_id)
	if data_path.is_empty():
		return null
	var best: WeaponPickup = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("weapon_pickups"):
		if node is not WeaponPickup:
			continue
		var p := node as WeaponPickup
		if p.network_pickup_id != 0 or not p.is_available():
			continue
		if p.get_pickup_data_path() != data_path:
			continue
		var d: float = p.global_position.distance_to(client_pickup_pos)
		if d < best_d and d <= _PROXIMITY_HINT_POS_EPS:
			best_d = d
			best = p
	return best


func _get_server_pickup_aim(player: OnlinePlayer) -> Dictionary:
	var server_origin := player.global_transform.origin + Vector3.UP * 1.5
	if player.camera:
		server_origin = player.camera.global_transform.origin
	var forward := -player.global_transform.basis.z
	var right := player.global_transform.basis.x.normalized()
	var pitch := player.aim_component.aim_angle * 1.5
	var server_direction := forward.rotated(right, pitch).normalized()
	return {"origin": server_origin, "direction": server_direction}


func _pickup_client_aim_matches_server(player: OnlinePlayer, aim_origin: Vector3, aim_direction: Vector3) -> bool:
	if aim_direction.length_squared() < 0.0001:
		return false
	var aim := _get_server_pickup_aim(player)
	var server_direction: Vector3 = aim["direction"]
	var server_origin: Vector3 = aim["origin"]
	if aim_direction.normalized().dot(server_direction) < _PICKUP_MAX_AIM_DOT:
		return false
	if aim_origin.distance_to(server_origin) > _PICKUP_MAX_ORIGIN_DIST:
		return false
	return true


func _find_weapon_pickup_along_ray(origin: Vector3, direction: Vector3) -> WeaponPickup:
	var dir := direction.normalized()
	if dir == Vector3.ZERO:
		return null
	var to := origin + dir * PICKUP_RAY_MAX_DISTANCE
	var params := PhysicsRayQueryParameters3D.new()
	params.from = origin
	params.to = to
	params.collision_mask = PICKUP_RAY_COLLISION_MASK
	params.exclude = []
	for node in get_tree().get_nodes_in_group("online_players"):
		if node is CollisionObject3D:
			params.exclude.append(node as CollisionObject3D)
	var space := get_world_3d().direct_space_state
	var result := space.intersect_ray(params)
	if not result:
		return null
	var collider: Variant = result.get("collider")
	if collider is WeaponPickup:
		return collider as WeaponPickup
	if collider is Node3D:
		var n: Node = collider as Node
		while n:
			if n is WeaponPickup:
				return n as WeaponPickup
			n = n.get_parent()
	return null
