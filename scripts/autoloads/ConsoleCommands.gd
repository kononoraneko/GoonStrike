## ConsoleCommands.gd  —  Autoload (singleton)
## Добавь в Project → Project Settings → Autoload как "ConsoleCommands"
##
## Использование:
##   ConsoleCommands.register("speed", player, "speed",
##       "Скорость движения игрока", 1.0, 50.0)
##
## Команды в чате:
##   /speed          — показать текущее значение
##   /speed 12       — установить значение
##   /help           — список команд
##   /help speed     — справка по команде

extends Node

## Одна зарегистрированная команда
class CommandEntry:
	var name: String
	var target: Object        # объект, у которого меняем свойство
	var property: String      # имя property или вложенный путь "movement/speed"
	var description: String
	var min_val: float
	var max_val: float
	var value_type: String    # "float" | "int" | "bool" | "string"
	var _getter: Callable
	var _setter: Callable

	func get_value() -> Variant:
		if _getter.is_valid():
			return _getter.call()
		if "." in property:
			# вложенный путь: "movement_component.speed"
			var parts := property.split(".")
			var obj: Object = target
			for i in range(parts.size() - 1):
				obj = obj.get(parts[i])
			return obj.get(parts[-1])
		return target.get(property)

	func set_value(raw: String) -> String:
		var new_val: Variant
		match value_type:
			"bool":
				if raw in ["true","1","on","yes"]:   new_val = true
				elif raw in ["false","0","off","no"]: new_val = false
				else: return "[color=red]Ожидается true/false[/color]"
			"int":
				if not raw.is_valid_int(): return "[color=red]Ожидается целое число[/color]"
				new_val = int(raw)
				if min_val != max_val:
					new_val = clampi(new_val, int(min_val), int(max_val))
			"string":
				new_val = raw
			_:  # float по умолчанию
				if not raw.is_valid_float(): return "[color=red]Ожидается число[/color]"
				new_val = float(raw)
				if min_val != max_val:
					new_val = clampf(new_val, min_val, max_val)

		if "." in property:
			var parts := property.split(".")
			var obj: Object = target
			for i in range(parts.size() - 1):
				obj = obj.get(parts[i])
			obj.set(parts[-1], new_val)
		else:
			target.set(property, new_val)
		
		if _setter.is_valid():
			_setter.call(new_val)
		else:
			target.set(property, new_val)
		return "[color=lime]%s[/color] = [b]%s[/b]" % [name, str(new_val)]


# ── Реестр ────────────────────────────────────────────────────────────────

var _commands: Dictionary = {}   # name → CommandEntry


## Зарегистрировать команду-переменную.
## min_val == max_val == 0.0  означает «без ограничений».
func register(
	cmd_name:    String,
	target:      Object,
	property:    String,
	description: String = "",
	min_val:     float  = 0.0,
	max_val:     float  = 0.0,
	value_type:  String = "float"
) -> void:
	var entry        := CommandEntry.new()
	entry.name        = cmd_name
	entry.target      = target
	entry.property    = property
	entry.description = description
	entry.min_val     = min_val
	entry.max_val     = max_val
	entry.value_type  = value_type
	_commands[cmd_name] = entry


## Регистрация через геттер/сеттер — для динамических объектов.
func register_callable(
	cmd_name:    String,
	getter:      Callable,
	setter:      Callable,
	description: String = "",
	min_val:     float  = 0.0,
	max_val:     float  = 0.0,
	value_type:  String = "float"
) -> void:
	var entry        := CommandEntry.new()
	entry.name        = cmd_name
	entry.description = description
	entry.min_val     = min_val
	entry.max_val     = max_val
	entry.value_type  = value_type
	entry.target      = null
	entry.property    = ""
	entry._getter     = getter
	entry._setter     = setter
	_commands[cmd_name] = entry


## Выполнить строку команды. Возвращает текст-ответ (BBCode).
func execute(input: String) -> String:
	input = input.strip_edges()
	if not input.begins_with("/"):
		return ""               # не команда — пусть чат обработает

	var parts := input.trim_prefix("/").split(" ", false)
	if parts.is_empty():
		return ""

	var cmd_name := parts[0].to_lower()

	# ── встроенные команды ─────────────────────────────────────────────
	if cmd_name == "help":
		if parts.size() > 1:
			return _help_single(parts[1])
		return _help_all()

	# ── пользовательские команды ───────────────────────────────────────
	if not _commands.has(cmd_name):
		return "[color=red]Неизвестная команда:[/color] %s\nНапиши [b]/help[/b]" % cmd_name

	var entry: CommandEntry = _commands[cmd_name]

	if parts.size() == 1:
		# Показать текущее значение
		return "[color=aqua]%s[/color] = %s  (%s)" % [
			cmd_name, str(entry.get_value()), entry.description
		]
	else:
		return entry.set_value(parts[1])


func _help_all() -> String:
	var lines := ["[b]Доступные команды:[/b]"]
	for k in _commands.keys():
		var e: CommandEntry = _commands[k]
		lines.append("  [color=aqua]/%s[/color] — %s" % [k, e.description])
	lines.append("  [color=aqua]/help <команда>[/color] — подробнее")
	return "\n".join(lines)


func _help_single(cmd_name: String) -> String:
	if not _commands.has(cmd_name):
		return "[color=red]Команда не найдена:[/color] " + cmd_name
	var e: CommandEntry = _commands[cmd_name]
	var range_str := ""
	if e.min_val != e.max_val:
		range_str = "  диапазон: [%s .. %s]" % [e.min_val, e.max_val]
	return "[b]/%s[/b]\n%s\nТип: %s%s\nТекущее: %s" % [
		cmd_name, e.description, e.value_type, range_str, str(e.get_value())
	]
