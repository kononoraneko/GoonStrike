## ChatConsole.gd
## Чат + консоль команд в одном окне.
## Структура сцены:
##
## ChatConsole  (Control, Layer=3, скрипт: ChatConsole.gd)
## └── Panel  (якорь: bottom-right, size=(360,280), offset bottom:-20 right:-20)
##     └── VBoxContainer  (fill, margins=8px)
##         ├── Header  (HBoxContainer)
##         │   ├── TitleLabel  (Label, text="ЧАТ")
##         │   └── ModeBtn     (Button, text="[ ]  консоль")
##         ├── Log  (RichTextLabel, bbcode=true, size_flags_v=EXPAND, scroll_follow=true)
##         └── InputRow  (HBoxContainer)
##             ├── Prefix  (Label, text="›", visible=false)  ← показывается в режиме консоли
##             └── Input   (LineEdit, size_flags_h=EXPAND, placeholder="Написать...")

class_name ChatConsole extends Control

signal message_sent(text: String)   # для отправки в сеть

enum Mode { CHAT, CONSOLE }

@onready var log_box:    RichTextLabel = $Panel/VBoxContainer/Log
@onready var input_line: LineEdit      = $Panel/VBoxContainer/InputRow/Input
@onready var prefix_lbl: Label         = $Panel/VBoxContainer/InputRow/Prefix
@onready var mode_btn:   Button        = $Panel/VBoxContainer/Header/ModeBtn
@onready var title_lbl:  Label         = $Panel/VBoxContainer/Header/TitleLabel

var current_mode: Mode = Mode.CHAT

# История команд (стрелки вверх/вниз)
var _history: Array[String] = []
var _history_idx: int = -1

# Кому принадлежит этот HUD
var player: OnlinePlayer


func _ready() -> void:
	mode_btn.pressed.connect(_toggle_mode)
	input_line.text_submitted.connect(_on_submitted)
	input_line.gui_input.connect(_on_input_gui)
	_apply_mode()


func setup(p: OnlinePlayer) -> void:
	player = p


# ── Публичное API ─────────────────────────────────────────────────────────

## Добавить системное сообщение (сервер, события).
func print_system(text: String) -> void:
	_append("[color=gray][система] %s[/color]" % text)


## Добавить сообщение от игрока.
func print_chat(sender_name: String, text: String) -> void:
	_append("[color=yellow][b]%s[/b][/color]: %s" % [sender_name, text])


## Добавить ответ консоли.
func print_console(text: String) -> void:
	_append("[color=cyan]>[/color] %s" % text)


# ── UI события ────────────────────────────────────────────────────────────

func _toggle_mode() -> void:
	current_mode = Mode.CONSOLE if current_mode == Mode.CHAT else Mode.CHAT
	_apply_mode()


func _apply_mode() -> void:
	match current_mode:
		Mode.CHAT:
			title_lbl.text = "ЧАТ"
			mode_btn.text  = "[  ]  консоль"
			prefix_lbl.visible = false
			input_line.placeholder_text = "Написать... (Enter)"
		Mode.CONSOLE:
			title_lbl.text = "КОНСОЛЬ"
			mode_btn.text  = "[✓]  консоль"
			prefix_lbl.visible = true
			input_line.placeholder_text = "/команда [значение]"


func _on_submitted(text: String) -> void:
	text = text.strip_edges()
	input_line.clear()
	_history_idx = -1
	if text.is_empty():
		return

	match current_mode:
		Mode.CHAT:
			_handle_chat(text)
		Mode.CONSOLE:
			_handle_console(text)


func _handle_chat(text: String) -> void:
	# Команды работают и в режиме чата если начинаются с /
	if text.begins_with("/"):
		_handle_console(text)
		return
	_history.push_front(text)
	#print_chat(player.player_info.get("name", "?"), text)
	message_sent.emit(text)


func _handle_console(text: String) -> void:
	_history.push_front(text)

	if _is_server_command(text):
		ChatNetwork.send_admin_command(text)
		return

	var result : String = ConsoleCommands.execute(text)
	if result.is_empty():
		# Не команда в режиме чата — отправляем как сообщение
		print_chat(player.player_info.get("name", "?"), text)
		message_sent.emit(text)
	else:
		print_console(result)


func _is_server_command(text: String) -> bool:
	if not text.begins_with("/"):
		return false
	var parts := text.trim_prefix("/").split(" ", false)
	if parts.is_empty():
		return false
	var cmd := parts[0].to_lower()
	return cmd in ["op", "speed", "jump"]


## Навигация по истории стрелками вверх/вниз.
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
			input_line.release_focus()


func _append(bbcode: String) -> void:
	log_box.append_text(bbcode + "\n")


# ── Захват клавиши T для открытия чата ───────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_chat"):   # добавь action "open_chat" → T
		input_line.grab_focus()
		get_viewport().set_input_as_handled()
