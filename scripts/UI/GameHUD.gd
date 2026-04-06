## GameHUD.gd  (обновлённый)
## Корневой узел UI. Инициализируется через setup(player).
## Чат подключается снаружи — в HUDManager.
##
## Структура сцены:
## GameHUD  (CanvasLayer, layer=10)
## ├── PlayerHUD    (PlayerHUD.tscn)
## └── ChatConsole  (ChatConsole.tscn)

class_name GameHUD extends CanvasLayer

@onready var player_hud:   PlayerHUD   = $PlayerHUD
@onready var chat_console: ChatConsole = $ChatConsole


func setup(player: OnlinePlayer) -> void:
	player_hud.setup(player)
	chat_console.setup(player)
	_register_console_commands(player)


func _register_console_commands(player: OnlinePlayer) -> void:
	var mv := player.movement
	var hc := player.health_component
	var wh := player.weapon_holder

	ConsoleCommands.register("speed",       mv, "speed",            "Скорость",           1.0,    50.0,  "float")
	ConsoleCommands.register("jump",        mv, "jump_velocity",    "Сила прыжка",        5.0,    100.0, "float")
	ConsoleCommands.register("sensitivity", mv, "mouse_sensitivity","Чувствительность",   0.0001, 0.01,  "float")
	ConsoleCommands.register("maxhp",       hc, "max_health",       "Максимальное HP",    1.0,    1000.0,"int")
	ConsoleCommands.register("potato",      Settings, "potato",       "Анимации волос",    1,    0,"bool")
	#ConsoleCommands.register("potato",      player.springbone, "active",       "Анимации волос",    1,    0,"bool")

	ConsoleCommands.register_callable(
		"damage",
		func(): return wh.current_weapon.data.damage    if wh.current_weapon else null,
		func(v): if wh.current_weapon: wh.current_weapon.data.damage   = v,
		"Урон оружия", 1.0, 500.0, "int"
	)
	ConsoleCommands.register_callable(
		"firerate",
		func(): return wh.current_weapon.data.fire_rate if wh.current_weapon else null,
		func(v): if wh.current_weapon: wh.current_weapon.data.fire_rate = v,
		"Задержка выстрела", 0.01, 5.0, "float"
	)
	ConsoleCommands.register_callable(
		"range",
		func(): return wh.current_weapon.data.range     if wh.current_weapon else null,
		func(v): if wh.current_weapon: wh.current_weapon.data.range    = v,
		"Дальность", 1.0, 2000.0, "float"
	)
	#ConsoleCommands.register_callable(
		#"potato",
		#func(): Settings.potato,
		#func(v): Settings.potato = v,
		#"Анимации волос", 1, 0, "bool"
	#)
