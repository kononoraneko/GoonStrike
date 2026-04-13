extends CanvasLayer

const SETTINGS_PATH := "user://settings.cfg"

@onready var resolution_option: OptionButton = %ResolutionOption
@onready var window_mode_option: OptionButton = %WindowModeOption
@onready var vsync_option: OptionButton = %VsyncOption
@onready var msaa_option: OptionButton = %MsaaOption
@onready var shadow_option: OptionButton = %ShadowOption
@onready var potato_hint: Label = $PanelContainer/MarginContainer/VBoxContainer/TabContainer/Графика/PotatoHint
@onready var apply_graphics_button: Button = $PanelContainer/MarginContainer/VBoxContainer/TabContainer/Графика/ApplyGraphicsButton
@onready var close_button: Button = $PanelContainer/MarginContainer/VBoxContainer/CloseButton


static func open(parent: Node) -> CanvasLayer:
	var scene := preload("res://scenes/ui/settings/settings_screen.tscn")
	var inst := scene.instantiate() as CanvasLayer
	parent.add_child(inst)
	return inst


func _ready() -> void:
	_build_option_lists()
	_sync_ui_from_settings()
	apply_graphics_button.pressed.connect(_on_apply_graphics_pressed)
	close_button.pressed.connect(_on_close_pressed)
	Settings.potato_mode_changed.connect(_on_potato_mode_changed)
	Settings.video_settings_applied.connect(_sync_ui_from_settings)
	_on_potato_mode_changed(Settings.is_potato_mode())


func _exit_tree() -> void:
	if Settings.potato_mode_changed.is_connected(_on_potato_mode_changed):
		Settings.potato_mode_changed.disconnect(_on_potato_mode_changed)
	if Settings.video_settings_applied.is_connected(_sync_ui_from_settings):
		Settings.video_settings_applied.disconnect(_sync_ui_from_settings)


func _build_option_lists() -> void:
	resolution_option.clear()
	var presets: Array = [
		["640 × 360", Vector2i(640, 360)],
		["854 × 480", Vector2i(854, 480)],
		["1280 × 720", Vector2i(1280, 720)],
		["1600 × 900", Vector2i(1600, 900)],
		["1920 × 1080", Vector2i(1920, 1080)],
	]
	for p in presets:
		resolution_option.add_item(p[0])
		resolution_option.set_item_metadata(resolution_option.item_count - 1, p[1])
	resolution_option.add_item("Размер экрана")
	resolution_option.set_item_metadata(resolution_option.item_count - 1, Vector2i(-1, -1))

	window_mode_option.clear()
	window_mode_option.add_item("В окне")
	window_mode_option.set_item_metadata(0, DisplayServer.WINDOW_MODE_WINDOWED)
	window_mode_option.add_item("Полный экран")
	window_mode_option.set_item_metadata(1, DisplayServer.WINDOW_MODE_FULLSCREEN)
	window_mode_option.add_item("Полный экран (эксклюзив)")
	window_mode_option.set_item_metadata(2, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

	vsync_option.clear()
	vsync_option.add_item("Выкл.")
	vsync_option.set_item_metadata(0, DisplayServer.VSYNC_DISABLED)
	vsync_option.add_item("Вкл.")
	vsync_option.set_item_metadata(1, DisplayServer.VSYNC_ENABLED)
	vsync_option.add_item("Адаптивный")
	vsync_option.set_item_metadata(2, DisplayServer.VSYNC_ADAPTIVE)

	msaa_option.clear()
	msaa_option.add_item("Выкл.")
	msaa_option.set_item_metadata(0, 0)
	msaa_option.add_item("2× MSAA")
	msaa_option.set_item_metadata(1, 1)
	msaa_option.add_item("4× MSAA")
	msaa_option.set_item_metadata(2, 2)
	msaa_option.add_item("8× MSAA")
	msaa_option.set_item_metadata(3, 3)

	shadow_option.clear()
	shadow_option.add_item("Низкое")
	shadow_option.set_item_metadata(0, 0)
	shadow_option.add_item("Среднее")
	shadow_option.set_item_metadata(1, 1)
	shadow_option.add_item("Высокое")
	shadow_option.set_item_metadata(2, 2)


func _sync_ui_from_settings() -> void:
	_select_resolution(Settings.window_width, Settings.window_height)
	_select_by_metadata(window_mode_option, Settings.window_mode)
	_select_by_metadata(vsync_option, Settings.vsync_mode)
	_select_by_metadata(msaa_option, Settings.msaa_3d)
	_select_by_metadata(shadow_option, Settings.shadow_quality)


func _select_resolution(w: int, h: int) -> void:
	var best_i := 0
	var best_dist := 999999
	for i in resolution_option.item_count:
		var meta: Variant = resolution_option.get_item_metadata(i)
		if meta is Vector2i:
			var sz: Vector2i = meta
			if sz.x < 0:
				continue
			var d: int = absi(sz.x - w) + absi(sz.y - h)
			if d < best_dist:
				best_dist = d
				best_i = i
	var native_i := resolution_option.item_count - 1
	var native_meta: Vector2i = resolution_option.get_item_metadata(native_i)
	if native_meta.x < 0:
		var scr := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
		if w == scr.x and h == scr.y:
			best_i = native_i
	resolution_option.select(best_i)


func _select_by_metadata(opt: OptionButton, value: int) -> void:
	for i in opt.item_count:
		if int(opt.get_item_metadata(i)) == value:
			opt.select(i)
			return
	opt.select(0)


func _on_apply_graphics_pressed() -> void:
	var res_meta: Variant = resolution_option.get_item_metadata(resolution_option.selected)
	var wh: Vector2i
	if res_meta is Vector2i:
		wh = res_meta
	if wh.x < 0 or wh.y < 0:
		wh = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())

	var wm := int(window_mode_option.get_item_metadata(window_mode_option.selected))
	var vs := int(vsync_option.get_item_metadata(vsync_option.selected))
	var ms := int(msaa_option.get_item_metadata(msaa_option.selected))
	var sh := int(shadow_option.get_item_metadata(shadow_option.selected))

	Settings.apply_video_from_controls(wh.x, wh.y, wm, vs, ms, sh)


func _on_potato_mode_changed(active: bool) -> void:
	var enable_controls := not active
	resolution_option.disabled = not enable_controls
	window_mode_option.disabled = not enable_controls
	vsync_option.disabled = not enable_controls
	msaa_option.disabled = not enable_controls
	shadow_option.disabled = not enable_controls
	apply_graphics_button.disabled = not enable_controls
	if active:
		potato_hint.text = "Включён режим /potato — элементы отключены. В консоли: /potato false для отката."
	else:
		potato_hint.text = "Режим минимальной графики: команда /potato в игровой консоли (чат → режим консоли). Повторный /potato false откатывает настройки."


func _on_close_pressed() -> void:
	queue_free()
