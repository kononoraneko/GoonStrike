## ChatConsole.gd  –  CS-style chat
## Floating messages появляются снизу и плавно гаснут.
## T → открыть панель, Escape/клик в сторону → закрыть.

class_name ChatConsole extends Control

signal message_sent(text: String)

enum Mode { CHAT, CONSOLE }

# ── Настройки ──────────────────────────────────────────────────────────
const MSG_STAY_TIME  := 5.0    # сек. сообщение остаётся видимым
const MSG_FADE_IN    := 0.15   # скорость появления
const MSG_FADE_OUT   := 0.4    # скорость исчезновения
const MAX_FLOAT_MSGS := 8      # максимум строк одновременно на экране

# ── Ноды ───────────────────────────────────────────────────────────────
@onready var messages_layer : Control       = $MessagesLayer
@onready var msg_vbox       : VBoxContainer = $MessagesLayer/VBoxContainer
@onready var chat_panel     : Panel         = $ChatPanel
@onready var log_box        : RichTextLabel = $ChatPanel/VBoxContainer/Log
@onready var input_line     : LineEdit      = $ChatPanel/VBoxContainer/InputRow/Input
@onready var prefix_lbl     : Label         = $ChatPanel/VBoxContainer/InputRow/Prefix

# ── Состояние ──────────────────────────────────────────────────────────
var current_mode : Mode = Mode.CHAT
var _history     : Array[String] = []
var _history_idx : int = -1
var _full_log    : Array[String] = []   # вся история (bbcode) для панели
var _chat_open   : bool = false
var player       : OnlinePlayer


func _ready() -> void:
	input_line.text_submitted.connect(_on_submitted)
	input_line.gui_input.connect(_on_input_gui)
	input_line.focus_exited.connect(_close_chat)
	chat_panel.visible = false


func setup(p: OnlinePlayer) -> void:
	player = p


func _sender_display_name() -> String:
	if player != null and is_instance_valid(player):
		return str(player.player_info.get("name", "?"))
	return str(Lobby.local_info.get("name", "?"))


# ── Публичное API ──────────────────────────────────────────────────────

func print_system(text: String) -> void:
	_post("[color=gray][система] %s[/color]" % text)

func print_chat(sender_name: String, text: String) -> void:
	_post("[color=yellow][b]%s[/b][/color]: %s" % [sender_name, text])

func print_console(text: String) -> void:
	_post("[color=cyan]>[/color] %s" % text)


# ── Внутренняя логика ──────────────────────────────────────────────────

## Центральная точка: добавить сообщение в лог и отобразить нужным способом.
func _post(bbcode: String) -> void:
	_full_log.append(bbcode)
	if _chat_open:
		# Панель открыта — пишем сразу в лог
		log_box.append_text(bbcode + "\n")
	else:
		# Панель закрыта — создаём плавающую строку
		_spawn_floating(bbcode)


func _spawn_floating(bbcode: String) -> void:
	# Убираем самое старое если экран забит
	while msg_vbox.get_child_count() >= MAX_FLOAT_MSGS:
		msg_vbox.get_child(0).queue_free()

	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled          = true
	lbl.fit_content             = true
	lbl.scroll_active           = false
	lbl.mouse_filter            = Control.MOUSE_FILTER_IGNORE
	lbl.custom_minimum_size     = Vector2(360, 0)
	lbl.modulate.a              = 0.0
	msg_vbox.add_child(lbl)
	lbl.append_text(bbcode)

	# Tween привязан к lbl — автоматически остановится при queue_free()
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "modulate:a", 1.0, MSG_FADE_IN)
	tw.tween_interval(MSG_STAY_TIME)
	tw.tween_property(lbl, "modulate:a", 0.0, MSG_FADE_OUT)
	tw.tween_callback(lbl.queue_free)


func _open_chat() -> void:
	if _chat_open:
		return
	_chat_open = true
	# Перестраиваем лог из полной истории
	log_box.clear()
	for line in _full_log:
		log_box.append_text(line + "\n")
	messages_layer.visible = false
	chat_panel.visible     = true
	input_line.grab_focus()


func _close_chat() -> void:
	if not _chat_open:
		return
	_chat_open             = false
	chat_panel.visible     = false
	messages_layer.visible = true
	_history_idx           = -1


# ── Обработка ввода ────────────────────────────────────────────────────

func _on_submitted(raw: String) -> void:
	var text := raw.strip_edges()
	input_line.clear()
	_history_idx = -1
	_close_chat()          # закрываем ДО обработки — чтобы print_chat → _spawn_floating
	if text.is_empty():
		return
	match current_mode:
		Mode.CHAT:    _handle_chat(text)
		Mode.CONSOLE: _handle_console(text)


func _handle_chat(text: String) -> void:
	if text.begins_with("/"):
		_handle_console(text)
		return
	_history.push_front(text)
	message_sent.emit(text)


func _handle_console(text: String) -> void:
	_history.push_front(text)
	if _is_server_command(text):
		ChatNetwork.send_admin_command(text)
		return
	var result: String = ConsoleCommands.execute(text)
	if result.is_empty():
		print_chat(_sender_display_name(), text)
		message_sent.emit(text)
	else:
		print_console(result)


func _is_server_command(text: String) -> bool:
	if not text.begins_with("/"):
		return false
	var parts := text.trim_prefix("/").split(" ", false)
	if parts.is_empty():
		return false
	return parts[0].to_lower() in ["op", "speed", "jump", "sv_ammo", "round_time", "round_limit"]


## Навигация по истории стрелками.
func _on_input_gui(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_UP:
			_history_idx = mini(_history_idx + 1, _history.size() - 1)
			if _history_idx >= 0:
				input_line.text = _history[_history_idx]
				input_line.caret_column = input_line.text.length()
		KEY_DOWN:
			_history_idx = maxi(_history_idx - 1, -1)
			input_line.text = _history[_history_idx] if _history_idx >= 0 else ""
			input_line.caret_column = input_line.text.length()
		KEY_ESCAPE:
			input_line.release_focus()   # → focus_exited → _close_chat()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_chat"):
		_open_chat()
		get_viewport().set_input_as_handled()
