class_name BuyMenu extends Control

## Меню закупок оружия. Открывается клавишей B.
## В Elimination — с ценами и деньгами; в Deathmatch — всё бесплатно.

signal buy_requested(weapon_path: String)
signal closed

var _game_manager: GameManager
var _is_economy: bool = false
var _category_buttons: Dictionary = {}
var _weapon_container: VBoxContainer
var _money_label: Label
var _title_label: Label
var _buy_blocked_hint: Label
var _buy_status_hint: Label
var _active_category: String = ""
var _purchase_allowed: bool = true

const CATEGORY_DISPLAY: Dictionary = {
	"pistols": "Пистолеты",
	"smgs": "ПП",
	"rifles": "Винтовки",
	"snipers": "Снайперские",
	"heavy": "Тяжёлые",
	"equipment": "Снаряжение",
	"other": "Прочее",
}

const CATEGORY_ORDER: Array = ["pistols", "smgs", "rifles", "snipers", "heavy", "equipment", "other"]


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _exit_tree() -> void:
	if _game_manager:
		if _game_manager.money_changed.is_connected(_on_money_changed):
			_game_manager.money_changed.disconnect(_on_money_changed)
		if _game_manager.buy_availability_changed.is_connected(_on_buy_availability_changed):
			_game_manager.buy_availability_changed.disconnect(_on_buy_availability_changed)


func setup(game_manager: GameManager) -> void:
	_game_manager = game_manager
	_is_economy = game_manager.is_economy_mode()
	if _game_manager:
		if not _game_manager.money_changed.is_connected(_on_money_changed):
			_game_manager.money_changed.connect(_on_money_changed)
		if not _game_manager.buy_availability_changed.is_connected(_on_buy_availability_changed):
			_game_manager.buy_availability_changed.connect(_on_buy_availability_changed)
	_update_money_display()


func open() -> void:
	if _game_manager != null and not _game_manager.can_open_buy_menu():
		return
	_purchase_allowed = true
	_refresh_buy_status_labels()
	_populate_first_category()
	_update_money_display()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _refresh_buy_status_labels() -> void:
	var prev := _purchase_allowed
	var detail := ""
	if _game_manager:
		var availability := _game_manager.get_local_buy_availability()
		_purchase_allowed = bool(availability.get("can_buy_now", false))
		detail = String(availability.get("hint_text", ""))
	if _buy_status_hint:
		_buy_status_hint.text = detail
		_buy_status_hint.visible = not detail.is_empty()
	if _buy_blocked_hint:
		_buy_blocked_hint.visible = not _purchase_allowed
		_buy_blocked_hint.text = "Покупка сейчас заблокирована — см. текст выше." if not _purchase_allowed else ""
	if prev != _purchase_allowed and not _active_category.is_empty():
		_show_category(_active_category)


func _on_buy_availability_changed(availability: Dictionary) -> void:
	if visible and not bool(availability.get("can_open_menu", false)):
		close()
		return
	if visible:
		_refresh_buy_status_labels()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("buy_menu") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.08, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root_vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root_vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "ЗАКУПКИ"
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.clip_text = true
	header.add_child(_title_label)

	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 22)
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_money_label.custom_minimum_size.x = 160
	_money_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_money_label.clip_text = true
	header.add_child(_money_label)

	_buy_status_hint = Label.new()
	_buy_status_hint.visible = false
	_buy_status_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_buy_status_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buy_status_hint.add_theme_font_size_override("font_size", 13)
	_buy_status_hint.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	root_vbox.add_child(_buy_status_hint)

	_buy_blocked_hint = Label.new()
	_buy_blocked_hint.visible = false
	_buy_blocked_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buy_blocked_hint.add_theme_font_size_override("font_size", 14)
	_buy_blocked_hint.add_theme_color_override("font_color", Color(0.85, 0.45, 0.35))
	root_vbox.add_child(_buy_blocked_hint)

	var sep := HSeparator.new()
	root_vbox.add_child(sep)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(body)

	var cat_vbox := VBoxContainer.new()
	cat_vbox.custom_minimum_size.x = 180
	body.add_child(cat_vbox)

	var cat_title := Label.new()
	cat_title.text = "Категории"
	cat_title.add_theme_font_size_override("font_size", 16)
	cat_vbox.add_child(cat_title)

	for cat_id in CATEGORY_ORDER:
		var btn := Button.new()
		btn.text = String(CATEGORY_DISPLAY.get(cat_id, cat_id))
		btn.pressed.connect(_on_category_pressed.bind(cat_id))
		btn.custom_minimum_size.y = 36
		cat_vbox.add_child(btn)
		_category_buttons[cat_id] = btn

	var vsep := VSeparator.new()
	body.add_child(vsep)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)

	_weapon_container = VBoxContainer.new()
	_weapon_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_weapon_container)

	var hint := Label.new()
	hint.text = "[B / Esc] — закрыть"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(hint)


func _populate_first_category() -> void:
	var cats := WeaponRegistry.get_weapons_by_category()
	var picked := ""
	for cat_id in CATEGORY_ORDER:
		if cats.has(cat_id) and not (cats[cat_id] as Array).is_empty():
			picked = cat_id
			break
	if picked.is_empty() and not cats.is_empty():
		picked = String(cats.keys()[0])
	if not picked.is_empty():
		_show_category(picked)


func _on_category_pressed(cat_id: String) -> void:
	_show_category(cat_id)


func _show_category(cat_id: String) -> void:
	_active_category = cat_id
	while _weapon_container.get_child_count() > 0:
		var c := _weapon_container.get_child(0)
		_weapon_container.remove_child(c)
		c.queue_free()

	for key in _category_buttons.keys():
		var btn: Button = _category_buttons[key]
		btn.disabled = (key == cat_id)

	var cats := WeaponRegistry.get_weapons_by_category()
	if not cats.has(cat_id):
		var empty := Label.new()
		empty.text = "Нет оружия"
		_weapon_container.add_child(empty)
		return

	var weapons: Array = cats[cat_id]
	var my_money := _get_local_money()

	for data in weapons:
		if data is not WeaponData:
			continue
		var wd := data as WeaponData
		_add_weapon_row(wd, my_money)


func _add_weapon_row(wd: WeaponData, my_money: int) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 48

	if wd.pickup_icon:
		var icon := TextureRect.new()
		icon.texture = wd.pickup_icon
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(48, 48)
		row.add_child(icon)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = wd.weapon_name
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	info_vbox.add_child(name_label)

	if _is_economy and wd.price > 0:
		var price_label := Label.new()
		price_label.text = "$%d" % wd.price
		price_label.add_theme_font_size_override("font_size", 13)
		if my_money < wd.price:
			price_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		else:
			price_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.4))
		info_vbox.add_child(price_label)

	var buy_btn := Button.new()
	if _is_economy:
		buy_btn.text = "Купить ($%d)" % wd.price if wd.price > 0 else "Купить"
		buy_btn.disabled = not _purchase_allowed or my_money < wd.price
	else:
		buy_btn.text = "Взять"
		buy_btn.disabled = not _purchase_allowed
	buy_btn.custom_minimum_size = Vector2(140, 40)
	var wp := wd.resource_path
	buy_btn.pressed.connect(func(): _on_buy_pressed(wp))
	row.add_child(buy_btn)

	_weapon_container.add_child(row)


func _on_buy_pressed(weapon_path: String) -> void:
	if _game_manager == null:
		return
	if multiplayer.has_multiplayer_peer():
		_game_manager.rpc_request_buy.rpc_id(1, weapon_path)
	else:
		# Оффлайн/локальный запуск без net-peer.
		_game_manager.rpc_request_buy(weapon_path)
	buy_requested.emit(weapon_path)
	close()


func _on_money_changed(peer_id: int, _amount: int) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	_update_money_display()
	if visible and not _active_category.is_empty():
		_show_category(_active_category)


func _update_money_display() -> void:
	if _money_label == null:
		return
	if not _is_economy:
		_money_label.text = ""
		return
	var amount := _get_local_money()
	_money_label.text = "$%d" % amount


func _get_local_money() -> int:
	if _game_manager == null:
		return 0
	return _game_manager.get_player_money(multiplayer.get_unique_id())
