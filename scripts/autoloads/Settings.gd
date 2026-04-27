extends Node

const CHARACTERS_REGISTRY_PATH := "res://resources/characters/characters_registry.tres"
const SETTINGS_PATH := "user://settings.cfg"

var _characters: Array[CharacterData] = []

var selected_char: int = 0

# ── Видео (сохраняются в user://settings.cfg) ─────────────────────────────

## Размер окна в оконном / безрамочном режиме.
var window_width: int = 1280
var window_height: int = 720

## DisplayServer.WINDOW_MODE_*
var window_mode: int = DisplayServer.WINDOW_MODE_WINDOWED

## DisplayServer.VSYNC_*
var vsync_mode: int = DisplayServer.VSYNC_ENABLED

## Значение ProjectSettings rendering/anti_aliasing/quality/msaa_3d (0 = выкл).
var msaa_3d: int = 1

## 0 низкие, 1 средние, 2 высокие (тени направленного света + фильтр).
var shadow_quality: int = 1

## Режим «картошка»: только через консоль /potato; отключает — восстанавливает бэкап.
var _potato_mode: bool = false
var _video_state_before_potato: Dictionary = {}

signal video_settings_applied
signal potato_mode_changed(active: bool)


func _ready() -> void:
	_load_characters_registry()
	var first_run := not FileAccess.file_exists(SETTINGS_PATH)
	load_video_settings_from_file()
	load_cosmetic_settings_from_file()
	call_deferred("_boot_apply_video", first_run)


func _boot_apply_video(first_run: bool) -> void:
	_apply_video_to_engine()
	if first_run:
		save_video_settings()


func load_and_apply_video_settings() -> void:
	load_video_settings_from_file()
	call_deferred("_apply_video_to_engine")


func _persist_video_backup_to_cfg() -> void:
	var st := _capture_video_state()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for k in st.keys():
		cfg.set_value("video_backup", str(k), st[k])
	cfg.save(SETTINGS_PATH)


func _restore_video_backup_from_cfg() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return false
	if not cfg.has_section("video_backup"):
		return false
	_restore_video_state({
		"window_width": int(cfg.get_value("video_backup", "window_width", 1280)),
		"window_height": int(cfg.get_value("video_backup", "window_height", 720)),
		"window_mode": int(cfg.get_value("video_backup", "window_mode", DisplayServer.WINDOW_MODE_WINDOWED)),
		"vsync_mode": int(cfg.get_value("video_backup", "vsync_mode", DisplayServer.VSYNC_ENABLED)),
		"msaa_3d": int(cfg.get_value("video_backup", "msaa_3d", 1)),
		"shadow_quality": int(cfg.get_value("video_backup", "shadow_quality", 1)),
	})
	return true


func _erase_video_backup_section() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	if cfg.has_section("video_backup"):
		cfg.erase_section("video_backup")
		cfg.save(SETTINGS_PATH)


func _load_characters_registry() -> void:
	var reg := load(CHARACTERS_REGISTRY_PATH) as CharactersRegistry
	if reg == null:
		push_error("Settings: failed to load characters registry at " + CHARACTERS_REGISTRY_PATH)
		return
	_characters = reg.characters.duplicate()


func get_character_count() -> int:
	return _characters.size()


func get_selected_character_scene() -> PackedScene:
	if _characters.is_empty():
		push_error("Settings: no characters in registry")
		return null
	var i := clampi(selected_char, 0, _characters.size() - 1)
	var ch: CharacterData = _characters[i]
	if ch == null or ch.character_scene == null:
		push_error("Settings: invalid character at index %d" % i)
		return null
	return ch.character_scene


func get_selected_character_id() -> String:
	if _characters.is_empty():
		return "lain"
	var i := clampi(selected_char, 0, _characters.size() - 1)
	var ch: CharacterData = _characters[i]
	return ch.id if ch != null and not ch.id.is_empty() else "lain"


func set_selected_character_id(character_id: String) -> void:
	var normalized := character_id.strip_edges().to_lower()
	for i in range(_characters.size()):
		var ch: CharacterData = _characters[i]
		if ch != null and ch.id == normalized:
			selected_char = i
			save_cosmetic_settings()
			return


func get_character_data(index: int) -> CharacterData:
	if index < 0 or index >= _characters.size():
		return null
	return _characters[index]


# ── Potato (консоль) ───────────────────────────────────────────────────────

func is_potato_mode() -> bool:
	return _potato_mode


func set_potato_mode(active: bool) -> void:
	if _potato_mode == active:
		return
	if active:
		_persist_video_backup_to_cfg()
		_video_state_before_potato = _capture_video_state()
		window_width = 854
		window_height = 480
		window_mode = DisplayServer.WINDOW_MODE_WINDOWED
		vsync_mode = DisplayServer.VSYNC_DISABLED
		msaa_3d = 0
		shadow_quality = 0
		_potato_mode = true
		_apply_video_to_engine()
		save_video_settings()
	else:
		_potato_mode = false
		if not _video_state_before_potato.is_empty():
			_restore_video_state(_video_state_before_potato)
			_video_state_before_potato.clear()
		elif not _restore_video_backup_from_cfg():
			_bootstrap_defaults_from_screen()
		_erase_video_backup_section()
		_apply_video_to_engine()
		save_video_settings()
	potato_mode_changed.emit(_potato_mode)
	video_settings_applied.emit()


func _capture_video_state() -> Dictionary:
	return {
		"window_width": window_width,
		"window_height": window_height,
		"window_mode": window_mode,
		"vsync_mode": vsync_mode,
		"msaa_3d": msaa_3d,
		"shadow_quality": shadow_quality,
	}


func _restore_video_state(d: Dictionary) -> void:
	window_width = int(d.get("window_width", 1280))
	window_height = int(d.get("window_height", 720))
	window_mode = int(d.get("window_mode", DisplayServer.WINDOW_MODE_WINDOWED))
	vsync_mode = int(d.get("vsync_mode", DisplayServer.VSYNC_ENABLED))
	msaa_3d = int(d.get("msaa_3d", 1))
	shadow_quality = int(d.get("shadow_quality", 1))


# ── Загрузка / сохранение / применение ─────────────────────────────────────

func load_video_settings_from_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		_bootstrap_defaults_from_screen()
		return
	if not cfg.has_section("video"):
		_bootstrap_defaults_from_screen()
		return
	window_width = int(cfg.get_value("video", "window_width", 1280))
	window_height = int(cfg.get_value("video", "window_height", 720))
	window_mode = int(cfg.get_value("video", "window_mode", DisplayServer.WINDOW_MODE_WINDOWED))
	vsync_mode = int(cfg.get_value("video", "vsync_mode", DisplayServer.VSYNC_ENABLED))
	msaa_3d = int(cfg.get_value("video", "msaa_3d", 1))
	shadow_quality = clampi(int(cfg.get_value("video", "shadow_quality", 1)), 0, 2)
	_potato_mode = bool(cfg.get_value("video", "potato_mode", false))


func load_cosmetic_settings_from_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var character_id := String(cfg.get_value("cosmetics", "character_id", get_selected_character_id()))
	set_selected_character_id(character_id)


func save_cosmetic_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("cosmetics", "character_id", get_selected_character_id())
	cfg.save(SETTINGS_PATH)


func save_video_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("video", "window_width", window_width)
	cfg.set_value("video", "window_height", window_height)
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "vsync_mode", vsync_mode)
	cfg.set_value("video", "msaa_3d", msaa_3d)
	cfg.set_value("video", "shadow_quality", shadow_quality)
	cfg.set_value("video", "potato_mode", _potato_mode)
	cfg.save(SETTINGS_PATH)


func apply_video_from_controls(
	p_width: int, p_height: int, p_window_mode: int, p_vsync: int, p_msaa: int, p_shadows: int
) -> void:
	if _potato_mode:
		_potato_mode = false
		_video_state_before_potato.clear()
		potato_mode_changed.emit(false)
	window_width = maxi(p_width, 640)
	window_height = maxi(p_height, 360)
	window_mode = p_window_mode
	vsync_mode = p_vsync
	msaa_3d = clampi(p_msaa, 0, 3)
	shadow_quality = clampi(p_shadows, 0, 2)
	_apply_video_to_engine()
	save_video_settings()
	video_settings_applied.emit()


func _bootstrap_defaults_from_screen() -> void:
	var sz := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	if sz.x > 100 and sz.y > 100:
		window_width = mini(1920, sz.x)
		window_height = mini(1080, sz.y)
	else:
		window_width = 1280
		window_height = 720


func _apply_video_to_engine() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var vp := tree.root.get_viewport()
	var msaa_clamped := clampi(msaa_3d, 0, 3)
	if vp:
		vp.msaa_3d = msaa_clamped as Viewport.MSAA
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", msaa_clamped)

	match shadow_quality:
		0:
			ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", 1024)
			ProjectSettings.set_setting(
				"rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 0
			)
		1:
			ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", 2048)
			ProjectSettings.set_setting(
				"rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 1
			)
		2:
			ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)
			ProjectSettings.set_setting(
				"rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 2
			)

	call_deferred("_deferred_apply_window")


func _deferred_apply_window() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var win := tree.root as Window
	if win:
		var wid := win.get_window_id()
		DisplayServer.window_set_vsync_mode(vsync_mode, wid)
		win.mode = window_mode as Window.Mode
		if window_mode == DisplayServer.WINDOW_MODE_WINDOWED:
			win.size = Vector2i(window_width, window_height)
			var scr := DisplayServer.screen_get_size(win.current_screen)
			win.position = (scr - win.size) / 2
		return
	DisplayServer.window_set_vsync_mode(vsync_mode)
	DisplayServer.window_set_mode(window_mode)
	if window_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(Vector2i(window_width, window_height))
		var scr := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
		DisplayServer.window_set_position((scr - Vector2i(window_width, window_height)) / 2)
