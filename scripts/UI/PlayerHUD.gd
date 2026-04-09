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

@onready var hp_bar:      ProgressBar = $HBoxContainer/HPPanel/VBoxContainer/HPBar
@onready var hp_label:    Label       = $HBoxContainer/HPPanel/VBoxContainer/HPLabel
@onready var weapon_icon: TextureRect = $HBoxContainer/VBoxContainer/WeaponIcon
@onready var weapon_label:Label       = $HBoxContainer/VBoxContainer/WeaponLabel

## Устанавливается при спавне локального игрока.
var player: OnlinePlayer


func setup(p: OnlinePlayer) -> void:
	player = p

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


func _on_health_changed(current_hp: int) -> void:
	hp_bar.value  = current_hp
	hp_label.text = "%d / %d" % [current_hp, player.health_component.max_health]

	# Анимация: краснеем при низком HP
	var t := float(current_hp) / player.health_component.max_health
	hp_bar.modulate = Color(1.0, t, t)


func _on_weapon_changed(weapon: Weapon) -> void:
	if weapon == null or weapon.data == null:
		weapon_label.text = "—"
		weapon_icon.texture = null
		return
	weapon_label.text   = weapon.data.weapon_name
	weapon_icon.texture = weapon.data.pickup_icon
