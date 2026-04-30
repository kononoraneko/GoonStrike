## PlayerHUD.gd
## Подключается к компонентам игрока через сигналы — не опрашивает каждый кадр.
## Структура сцены:
##
## PlayerHUD  (Control, Layer=2, скрипт: PlayerHUD.gd)
## ├── HBoxContainer  (якорь: bottom-left, offset bottom:-20 left:20)
## │   ├── HPPanel  (PanelContainer, custom_minimum_size=(220,64))
## │   │   └── VBoxContainer
## │   │       ├── HPLabel   (Label, text="HP")
## │   │       └── HPBar     (TextureProgressBar или ProgressBar)
## │   └── WeaponPanel  (PanelContainer, custom_minimum_size=(180,64))
## │       └── VBoxContainer
## │           ├── WeaponIcon   (TextureRect, custom_minimum_size=(40,40))
## │           └── WeaponLabel  (Label, text="—")
## └── CrossHair  (TextureRect или ColorRect, якорь: center)

class_name PlayerHUD extends Control

@onready var hp_bar:      ProgressBar = $HPPanel/VBoxContainer/HPBar
@onready var hp_label:    Label       = $HPPanel/VBoxContainer/HPLabel
@onready var weapon_icon: TextureRect = $VBoxContainer/WeaponIcon
@onready var weapon_label:Label       = $VBoxContainer/WeaponLabel
@onready var ammo_label:  Label       = $VBoxContainer/AmmoLabel
@onready var cross_hair: ColorRect    = $CrossHair
@onready var scope_overlay: Control   = $ScopeOverlay

## Устанавливается при спавне локального игрока.
var player: OnlinePlayer
var _crosshair_base_size: float = 8.0
var _crosshair_target_gap: float = 6.0
var _crosshair_current_gap: float = 6.0
var _crosshair_dynamic: bool = true
var _crosshair_lines_count: int = 4
var _crosshair_color: Color = Color(0.2, 1.0, 0.2, 0.95)
var _crosshair_line_len: float = 8.0
var _crosshair_thickness: float = 2.0
var _crosshair_lines: Array[ColorRect] = []


func setup(p: OnlinePlayer) -> void:
	if player != null and is_instance_valid(player) and player != p:
		unbind_player()
	player = p
	visible = true

	# ── HP ──────────────────────────────────────────────────────────────
	var hc := player.health_component
	hp_bar.max_value = hc.max_health
	hp_bar.value     = hc.health
	hp_label.text    = "%d / %d" % [hc.health, hc.max_health]
	hc.health_changed.connect(_on_health_changed)

	# ── Оружие ──────────────────────────────────────────────────────────
	var wh := player.weapon_holder
	wh.weapon_changed.connect(_on_weapon_changed)
	if not player.sniper_scope_changed.is_connected(_on_sniper_scope_changed):
		player.sniper_scope_changed.connect(_on_sniper_scope_changed)
	# Если оружие уже есть при подключении HUD (выдано при спавне)
	_on_weapon_changed(wh.current_weapon)
	_on_sniper_scope_changed(player.is_sniper_scoped)
	_init_crosshair_size()


func unbind_player() -> void:
	if player != null and is_instance_valid(player):
		var hc := player.health_component
		if hc.health_changed.is_connected(_on_health_changed):
			hc.health_changed.disconnect(_on_health_changed)
		var wh := player.weapon_holder
		if wh.weapon_changed.is_connected(_on_weapon_changed):
			wh.weapon_changed.disconnect(_on_weapon_changed)
		if wh.current_weapon != null and wh.current_weapon.ammo_changed.is_connected(_on_ammo_changed):
			wh.current_weapon.ammo_changed.disconnect(_on_ammo_changed)
		if player.sniper_scope_changed.is_connected(_on_sniper_scope_changed):
			player.sniper_scope_changed.disconnect(_on_sniper_scope_changed)
	player = null
	if scope_overlay:
		scope_overlay.visible = false
	if cross_hair:
		cross_hair.visible = true
	visible = false


func _on_health_changed(current_hp: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	hp_bar.value  = current_hp
	hp_label.text = "%d / %d" % [current_hp, player.health_component.max_health]

	# Анимация: краснеем при низком HP
	var t := float(current_hp) / player.health_component.max_health
	hp_bar.modulate = Color(1.0, t, t)


func _on_weapon_changed(weapon: Weapon) -> void:
	if weapon == null or weapon.data == null:
		weapon_label.text = "—"
		weapon_icon.texture = null
		ammo_label.text = "-- / --"
		return
	weapon_label.text = player.weapon_holder.get_current_weapon_display_name()
	weapon_icon.texture = weapon.data.pickup_icon
	if not weapon.ammo_changed.is_connected(_on_ammo_changed):
		weapon.ammo_changed.connect(_on_ammo_changed)
	_on_ammo_changed(weapon.ammo_in_mag, weapon.ammo_reserve)


func _on_ammo_changed(in_mag: int, in_reserve: int) -> void:
	ammo_label.text = "%d / %d" % [in_mag, in_reserve]


func _on_sniper_scope_changed(active: bool) -> void:
	if scope_overlay:
		scope_overlay.visible = active
	if cross_hair:
		cross_hair.visible = not active


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or cross_hair == null:
		return
	if not _crosshair_dynamic:
		_crosshair_target_gap = _crosshair_base_size
		_crosshair_current_gap = _crosshair_base_size
		_redraw_crosshair_lines(_crosshair_base_size)
		return
	var weapon := player.weapon_holder.current_weapon
	if weapon == null:
		_crosshair_target_gap = _crosshair_base_size
		_crosshair_current_gap = _crosshair_base_size
		_redraw_crosshair_lines(_crosshair_base_size)
		return
	var angle := weapon.get_crosshair_spread_angle_deg()
	_crosshair_target_gap = clampf(_crosshair_base_size + angle * 1.35, _crosshair_base_size, 48.0)
	# Быстрее отклик — чтобы в контр-стрейфе визуал почти моментально сходился.
	_crosshair_current_gap = lerpf(_crosshair_current_gap, _crosshair_target_gap, clampf(delta * 40.0, 0.0, 1.0))
	_redraw_crosshair_lines(_crosshair_current_gap)


func _init_crosshair_size() -> void:
	if cross_hair == null:
		return
	_crosshair_target_gap = _crosshair_base_size
	_crosshair_current_gap = _crosshair_base_size
	cross_hair.color = Color(0, 0, 0, 0)
	_rebuild_crosshair_lines()
	_redraw_crosshair_lines(_crosshair_base_size)


func _rebuild_crosshair_lines() -> void:
	if cross_hair == null:
		return
	for n in _crosshair_lines:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_crosshair_lines.clear()
	for _i in range(4):
		var line := ColorRect.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.color = _crosshair_color
		cross_hair.add_child(line)
		_crosshair_lines.append(line)


func _redraw_crosshair_lines(gap: float) -> void:
	if _crosshair_lines.size() < 4:
		return
	var show_count := clampi(_crosshair_lines_count, 3, 4)
	for i in range(_crosshair_lines.size()):
		_crosshair_lines[i].visible = i < show_count
		_crosshair_lines[i].color = _crosshair_color
	var half_t := _crosshair_thickness * 0.5
	var left := _crosshair_lines[0]
	var right := _crosshair_lines[1]
	var up := _crosshair_lines[2]
	left.position = Vector2(-gap - _crosshair_line_len, -half_t)
	left.size = Vector2(_crosshair_line_len, _crosshair_thickness)
	right.position = Vector2(gap, -half_t)
	right.size = Vector2(_crosshair_line_len, _crosshair_thickness)
	up.position = Vector2(-half_t, -gap - _crosshair_line_len)
	up.size = Vector2(_crosshair_thickness, _crosshair_line_len)
	if show_count >= 4:
		var down := _crosshair_lines[3]
		down.position = Vector2(-half_t, gap)
		down.size = Vector2(_crosshair_thickness, _crosshair_line_len)


func set_crosshair_dynamic(enabled: bool) -> void:
	_crosshair_dynamic = enabled


func is_crosshair_dynamic() -> bool:
	return _crosshair_dynamic


func set_crosshair_size(px: float) -> void:
	_crosshair_base_size = clampf(px, 2.0, 28.0)
	_crosshair_target_gap = _crosshair_base_size
	_crosshair_current_gap = _crosshair_base_size
	_redraw_crosshair_lines(_crosshair_base_size)


func get_crosshair_size() -> float:
	return _crosshair_base_size


func set_crosshair_style_lines(lines_count: int) -> void:
	_crosshair_lines_count = clampi(lines_count, 3, 4)
	_redraw_crosshair_lines(_crosshair_current_gap)


func get_crosshair_style_lines() -> int:
	return _crosshair_lines_count


func set_crosshair_color_hex(hex: String) -> void:
	var c := Color.from_string(hex, _crosshair_color)
	_crosshair_color = c
	_redraw_crosshair_lines(_crosshair_current_gap)


func get_crosshair_color_hex() -> String:
	return _crosshair_color.to_html()
