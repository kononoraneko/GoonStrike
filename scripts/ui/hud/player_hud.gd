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

## Устанавливается при спавне локального игрока.
var player: OnlinePlayer


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
	# Если оружие уже есть при подключении HUD (выдано при спавне)
	_on_weapon_changed(wh.current_weapon)


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
	player = null
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
	weapon_label.text   = weapon.data.weapon_name
	weapon_icon.texture = weapon.data.pickup_icon
	if not weapon.ammo_changed.is_connected(_on_ammo_changed):
		weapon.ammo_changed.connect(_on_ammo_changed)
	_on_ammo_changed(weapon.ammo_in_mag, weapon.ammo_reserve)


func _on_ammo_changed(in_mag: int, in_reserve: int) -> void:
	ammo_label.text = "%d / %d" % [in_mag, in_reserve]
