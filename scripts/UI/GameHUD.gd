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

	ConsoleCommands.register("speed",       mv, "speed",            "Скорость",           1.0,    50.0,  "float")
	ConsoleCommands.register("jump",        mv, "jump_velocity",    "Сила прыжка",        5.0,    100.0, "float")
	ConsoleCommands.register("sensitivity", mv, "mouse_sensitivity","Чувствительность",   0.0001, 0.01,  "float")
	ConsoleCommands.register("maxhp",       hc, "max_health",       "Максимальное HP",    1.0,    1000.0,"int")
	ConsoleCommands.register("potato",      Settings, "potato",       "Анимации волос",    1,    0,"bool")
	# gameplay-параметры оружия больше не доступны из локальной консоли:
	# server-authoritative значения должны меняться только на сервере/в ресурсах.
