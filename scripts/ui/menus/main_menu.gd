extends Control

const SETTINGS_SCREEN_SCRIPT := preload("res://scripts/ui/settings/settings_screen.gd")
const LOCAL_SERVER_LAUNCHER := preload("res://scripts/server/local_server_launcher.gd")
const LOCAL_SERVER_CONNECT_DELAY := 0.6

@onready var play_tab_btn: Button = $RootMargin/ShellRow/SideTabsPanel/SideTabsVBox/PlayTabButton
@onready var servers_tab_btn: Button = $RootMargin/ShellRow/SideTabsPanel/SideTabsVBox/ServersTabButton
@onready var profile_tab_btn: Button = $RootMargin/ShellRow/SideTabsPanel/SideTabsVBox/ProfileTabButton
@onready var inventory_tab_btn: Button = $RootMargin/ShellRow/SideTabsPanel/SideTabsVBox/InventoryTabButton
@onready var close_drawer_btn: Button = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerHeader/CloseDrawerButton
@onready var drawer_title_label: Label = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerHeader/DrawerTitleLabel
@onready var play_drawer: Control = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/PlayDrawer
@onready var servers_drawer: Control = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ServersDrawer
@onready var profile_drawer: Control = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ProfileDrawer
@onready var inventory_drawer: Control = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/InventoryDrawer
@onready var name_edit: LineEdit = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/PlayDrawer/NameEdit
@onready var auth_status_label: Label = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ProfileDrawer/AuthStatusLabel
@onready var email_edit: LineEdit = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ProfileDrawer/EmailEdit
@onready var password_edit: LineEdit = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ProfileDrawer/PasswordEdit
@onready var login_btn: Button = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ProfileDrawer/AuthButtons/LoginButton
@onready var register_btn: Button = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ProfileDrawer/AuthButtons/RegisterButton
@onready var logout_btn: Button = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ProfileDrawer/LogoutButton
@onready var ip_edit: LineEdit = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/PlayDrawer/IpRow/IpEdit
@onready var refresh_servers_btn: Button = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ServersDrawer/ServerBrowserButtons/RefreshServersButton
@onready var connect_selected_server_btn: Button = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ServersDrawer/ServerBrowserButtons/ConnectSelectedServerButton
@onready var trusted_servers_list: ItemList = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ServersDrawer/TrustedServersList
@onready var servers_status_label: Label = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ServersDrawer/ServersStatusLabel
@onready var join_btn: Button = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/PlayDrawer/PlayButtons/JoinButton
@onready var local_dedicated_btn: Button = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/PlayDrawer/PlayButtons/LocalDedicatedButton
@onready var settings_btn: Button = $RootMargin/ShellRow/SideTabsPanel/SideTabsVBox/SettingsButton
@onready var quit_btn: Button = $RootMargin/ShellRow/SideTabsPanel/SideTabsVBox/QuitButton
@onready var character_option: OptionButton = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ProfileDrawer/CharacterRow/OptionButton
@onready var economy_status_label: Label = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ProfileDrawer/EconomyStatusLabel
@onready var soft_balance_label: Label = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ProfileDrawer/SoftBalanceLabel
@onready var dev_grant_btn: Button = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/ProfileDrawer/DevGrantButton
@onready var ar15_skin_option: OptionButton = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/InventoryDrawer/InventoryOptionsPanel/InventoryOptionsVBox/AR15SkinRow/AR15SkinOption
@onready var barret_skin_option: OptionButton = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/InventoryDrawer/InventoryOptionsPanel/InventoryOptionsVBox/BarretSkinRow/BarretSkinOption
@onready var case_option: OptionButton = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/InventoryDrawer/InventoryOptionsPanel/InventoryOptionsVBox/CaseRow/CaseOption
@onready var open_case_btn: Button = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/InventoryDrawer/InventoryOptionsPanel/InventoryOptionsVBox/CaseRow/OpenCaseButton
@onready var inventory_items: ItemList = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/InventoryDrawer/InventoryBody/InventoryItems
@onready var inventory_item_title: Label = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/InventoryDrawer/InventoryBody/InventoryDetailsPanel/InventoryDetailsVBox/InventoryItemTitle
@onready var inventory_item_meta: Label = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/InventoryDrawer/InventoryBody/InventoryDetailsPanel/InventoryDetailsVBox/InventoryItemMeta
@onready var inventory_equip_btn: Button = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/InventoryDrawer/InventoryBody/InventoryDetailsPanel/InventoryDetailsVBox/InventoryEquipButton
@onready var connecting_overlay: Control = $ConnectingOverlay
@onready var error_label: Label = $RootMargin/ShellRow/DrawerHostPanel/DrawerHostVBox/DrawerStack/PlayDrawer/ErrorLabel

var _is_waiting_connection: bool = false
var _local_server_pid: int = -1
var _inventory_selected_meta: Dictionary = {}


func _ready() -> void:
	name_edit.text_changed.connect(_on_name_text_changed)
	login_btn.pressed.connect(_on_login_pressed)
	register_btn.pressed.connect(_on_register_pressed)
	logout_btn.pressed.connect(_on_logout_pressed)
	refresh_servers_btn.pressed.connect(_on_refresh_servers_pressed)
	connect_selected_server_btn.pressed.connect(_on_connect_selected_server_pressed)
	trusted_servers_list.item_selected.connect(_on_trusted_server_selected)
	trusted_servers_list.item_activated.connect(_on_trusted_server_activated)
	join_btn.pressed.connect(_on_join_pressed)
	local_dedicated_btn.pressed.connect(_on_local_dedicated_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	play_tab_btn.pressed.connect(func() -> void: _open_drawer(&"play"))
	servers_tab_btn.pressed.connect(func() -> void: _open_drawer(&"servers"))
	profile_tab_btn.pressed.connect(func() -> void: _open_drawer(&"profile"))
	inventory_tab_btn.pressed.connect(func() -> void: _open_drawer(&"inventory"))
	close_drawer_btn.pressed.connect(_on_close_drawer_pressed)
	dev_grant_btn.pressed.connect(_on_dev_grant_pressed)
	open_case_btn.pressed.connect(_on_open_case_pressed)
	inventory_items.item_selected.connect(_on_inventory_item_selected)
	inventory_equip_btn.pressed.connect(_on_inventory_equip_pressed)
	ar15_skin_option.item_selected.connect(func(index: int): _on_weapon_skin_selected("ar-15", ar15_skin_option, index))
	barret_skin_option.item_selected.connect(func(index: int): _on_weapon_skin_selected("barret", barret_skin_option, index))
	Lobby.server_disconnected.connect(_on_server_disconnected)
	AuthState.auth_changed.connect(_refresh_auth_ui)
	AuthState.session_conflict.connect(_on_session_conflict)
	AuthState.auth_error.connect(show_error)
	ProfileState.profile_changed.connect(_refresh_economy_ui)

	_populate_character_options()
	_refresh_auth_ui()
	_refresh_economy_ui()
	_open_drawer(&"play")
	show_connecting_overlay(false)
	error_label.hide()

	name_edit.text = str(Lobby.local_info.get("name", "Player"))
	ProfileState.load_profile(name_edit.text)
	call_deferred("_refresh_servers")

	var pending_error: String = SceneRouter.consume_pending_error()
	if not pending_error.is_empty():
		show_error(pending_error)


func _on_name_text_changed(new_text: String) -> void:
	Lobby.set_player_name(new_text)


func _on_close_drawer_pressed() -> void:
	play_drawer.hide()
	servers_drawer.hide()
	profile_drawer.hide()
	inventory_drawer.hide()
	drawer_title_label.text = "Панель закрыта"


func _open_drawer(drawer: StringName) -> void:
	play_drawer.visible = drawer == &"play"
	servers_drawer.visible = drawer == &"servers"
	profile_drawer.visible = drawer == &"profile"
	inventory_drawer.visible = drawer == &"inventory"
	match String(drawer):
		"play":
			drawer_title_label.text = "Играть"
		"servers":
			drawer_title_label.text = "Серверы"
		"profile":
			drawer_title_label.text = "Профиль"
		"inventory":
			drawer_title_label.text = "Инвентарь"
		_:
			drawer_title_label.text = "Панель"


func _on_login_pressed() -> void:
	var ok := await AuthState.login(email_edit.text, password_edit.text)
	if ok:
		password_edit.clear()
	else:
		show_error("Не удалось войти")


func _on_register_pressed() -> void:
	var display_name := name_edit.text.strip_edges()
	if display_name.is_empty():
		display_name = "Player"
	var ok := await AuthState.register(email_edit.text, password_edit.text, display_name)
	if ok:
		password_edit.clear()
	else:
		show_error("Не удалось зарегистрироваться")


func _on_logout_pressed() -> void:
	await AuthState.logout()
	ProfileState.load_profile(name_edit.text)


func _on_session_conflict() -> void:
	show_error("Сессии этой учётки сброшены. Войдите ещё раз.")


func _on_join_pressed() -> void:
	if _is_waiting_connection:
		return
	_begin_join(ip_edit.text.strip_edges())


func _on_refresh_servers_pressed() -> void:
	await _refresh_servers()


func _on_connect_selected_server_pressed() -> void:
	_connect_to_selected_server()


func _on_trusted_server_selected(_index: int) -> void:
	connect_selected_server_btn.disabled = _is_waiting_connection


func _on_trusted_server_activated(index: int) -> void:
	_connect_to_server_item(index)


func _refresh_servers() -> void:
	if _is_waiting_connection:
		return
	refresh_servers_btn.disabled = true
	connect_selected_server_btn.disabled = true
	trusted_servers_list.clear()
	servers_status_label.text = "Обновление списка серверов..."

	var result := await BackendClient.fetch_servers()
	refresh_servers_btn.disabled = _is_waiting_connection
	if not result.get("ok", false):
		var status_code := int(result.get("status", 0))
		if status_code == 401 or status_code == 403:
			servers_status_label.text = "Registry требует авторизацию. Используйте ручной IP."
			return
		servers_status_label.text = "Registry недоступен. Можно подключиться вручную по IP."
		return

	var data: Dictionary = result.get("data", {}) as Dictionary
	var servers: Array = data.get("servers", []) as Array
	for entry_variant in servers:
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		var item_text := "%s | %s/%s | %d/%d | %s:%d" % [
			String(entry.get("display_name", "Server")),
			String(entry.get("mode_id", "?")),
			String(entry.get("map_id", "?")),
			int(entry.get("current_players", 0)),
			int(entry.get("max_players", 0)),
			String(entry.get("host", "")),
			int(entry.get("port", Lobby.PORT)),
		]
		trusted_servers_list.add_item(item_text)
		trusted_servers_list.set_item_metadata(trusted_servers_list.get_item_count() - 1, {
			"host": String(entry.get("host", "")),
			"port": int(entry.get("port", Lobby.PORT)),
		})

	servers_status_label.text = "Доверенных серверов: %d" % trusted_servers_list.get_item_count() if trusted_servers_list.get_item_count() > 0 else "Доверенных серверов нет. Можно подключиться вручную по IP."


func _connect_to_selected_server() -> void:
	var selected := trusted_servers_list.get_selected_items()
	if selected.is_empty():
		show_error("Выберите сервер из списка")
		return
	_connect_to_server_item(selected[0])


func _connect_to_server_item(index: int) -> void:
	if _is_waiting_connection or index < 0 or index >= trusted_servers_list.get_item_count():
		return
	var metadata: Dictionary = trusted_servers_list.get_item_metadata(index) as Dictionary
	var host := String(metadata.get("host", "")).strip_edges()
	var port := int(metadata.get("port", Lobby.PORT))
	if host.is_empty():
		show_error("У сервера нет адреса")
		return
	_begin_join(host, port)


func _on_local_dedicated_pressed() -> void:
	if _is_waiting_connection:
		return
	_local_server_pid = LOCAL_SERVER_LAUNCHER.launch(Lobby.PORT, "default", GameModeCatalog.ID_TEAM_ELIM)
	if _local_server_pid <= 0:
		show_error("Не удалось запустить локальную игру")
		return
	Lobby.register_local_dedicated_process(_local_server_pid)
	_is_waiting_connection = true
	show_connecting_overlay(true)
	await get_tree().create_timer(LOCAL_SERVER_CONNECT_DELAY).timeout
	if not _is_waiting_connection:
		return
	_begin_join(Lobby.DEFAULT_IP, Lobby.PORT)


func _begin_join(address: String, port: int = -1) -> void:
	_sync_local_profile_to_lobby()
	var err: Error = Lobby.join_game(address, port)
	if err != OK:
		show_error("Не удалось начать подключение: %d" % err)
		_is_waiting_connection = false
		show_connecting_overlay(false)
		return
	_is_waiting_connection = true
	show_connecting_overlay(true)
	multiplayer.connected_to_server.connect(_on_connected_ok, CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)


func _on_connected_ok() -> void:
	_is_waiting_connection = false
	show_connecting_overlay(false)
	SceneRouter.go_lobby()


func _on_connection_failed() -> void:
	_is_waiting_connection = false
	show_connecting_overlay(false)
	Lobby.disconnect_game()
	show_error("Не удалось подключиться")


func _on_settings_pressed() -> void:
	SETTINGS_SCREEN_SCRIPT.open(get_tree().root)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_server_disconnected() -> void:
	if _is_waiting_connection:
		_on_connection_failed()


func show_connecting_overlay(visible: bool) -> void:
	connecting_overlay.visible = visible
	join_btn.disabled = visible
	local_dedicated_btn.disabled = visible
	refresh_servers_btn.disabled = visible
	connect_selected_server_btn.disabled = visible or trusted_servers_list.get_selected_items().is_empty()


func show_error(msg: String) -> void:
	error_label.text = msg
	error_label.show()
	var timer := get_tree().create_timer(4.0)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(error_label):
			error_label.hide()
	)


func _on_character_option_button_item_selected(index: int) -> void:
	Settings.selected_char = index
	var data : CharacterData = Settings.get_character_data(index)
	if data != null:
		ProfileState.set_local_character_id(data.id)
		_sync_local_profile_to_lobby()


func _populate_character_options() -> void:
	character_option.clear()
	for i in range(Settings.get_character_count()):
		var data :CharacterData = Settings.get_character_data(i)
		if data == null:
			continue
		character_option.add_item(data.display_name, i)
		if data.id == ProfileState.get_equipped_character_id() or i == Settings.selected_char:
			character_option.select(character_option.get_item_count() - 1)


func _sync_local_profile_to_lobby() -> void:
	var weapon_skins := {
		"ar-15": ProfileState.get_equipped_weapon_skin("ar-15"),
		"barret": ProfileState.get_equipped_weapon_skin("barret"),
	}
	Lobby.set_player_cosmetics(ProfileState.get_equipped_character_id(), weapon_skins)


func _refresh_economy_ui() -> void:
	var auth_ready := AuthState.is_authenticated()
	var status := "online" if ProfileState.backend_available and auth_ready else "offline fallback"
	economy_status_label.text = "Economy: %s" % status
	soft_balance_label.text = "Soft: %d" % ProfileState.get_wallet_amount("soft")
	dev_grant_btn.disabled = not ProfileState.backend_available or not auth_ready
	open_case_btn.disabled = not ProfileState.backend_available or not auth_ready
	_populate_skin_option(ar15_skin_option, "ar-15")
	_populate_skin_option(barret_skin_option, "barret")
	_populate_case_options()
	_rebuild_inventory_items()
	_sync_local_profile_to_lobby()


func _populate_skin_option(option: OptionButton, weapon_short_name: String) -> void:
	option.clear()
	var selected_item := ProfileState.get_equipped_weapon_skin(weapon_short_name)
	for skin in CosmeticsRegistry.get_weapon_skins_for_weapon(weapon_short_name):
		if not ProfileState.owns_item(skin.item_key):
			continue
		option.add_item("%s [%s]" % [skin.display_name, skin.rarity])
		var idx := option.get_item_count() - 1
		option.set_item_metadata(idx, skin.item_key)
		if skin.item_key == selected_item:
			option.select(idx)
	option.disabled = option.get_item_count() <= 1


func _populate_case_options() -> void:
	case_option.clear()
	for case_data in ProfileState.get_available_cases():
		var case_key := String(case_data.get("case_key", ""))
		if case_key.is_empty():
			continue
		case_option.add_item("%s (%d %s)" % [
			String(case_data.get("display_name", case_key)),
			int(case_data.get("price_amount", 0)),
			String(case_data.get("price_currency", "soft")),
		])
		case_option.set_item_metadata(case_option.get_item_count() - 1, case_key)
	case_option.disabled = case_option.get_item_count() == 0 or not ProfileState.backend_available or not AuthState.is_authenticated()


func _rebuild_inventory_items() -> void:
	inventory_items.clear()
	_inventory_selected_meta.clear()
	inventory_item_title.text = "Выберите предмет"
	inventory_item_meta.text = "-"
	inventory_equip_btn.disabled = true
	var weapons: Array[String] = ["ar-15", "barret"]
	for weapon_short_name in weapons:
		for skin in CosmeticsRegistry.get_weapon_skins_for_weapon(weapon_short_name):
			if not ProfileState.owns_item(skin.item_key):
				continue
			var equipped: bool = ProfileState.get_equipped_weapon_skin(weapon_short_name) == skin.item_key
			var display := "%s%s [%s]" % ["[E] " if equipped else "", skin.display_name, skin.rarity]
			inventory_items.add_item(display)
			inventory_items.set_item_metadata(inventory_items.get_item_count() - 1, {
				"slot": "weapon:%s" % weapon_short_name,
				"item_key": skin.item_key,
				"rarity": skin.rarity,
				"display_name": skin.display_name,
			})


func _on_inventory_item_selected(index: int) -> void:
	var meta_variant: Variant = inventory_items.get_item_metadata(index)
	if not (meta_variant is Dictionary):
		return
	_inventory_selected_meta = meta_variant
	inventory_item_title.text = String(_inventory_selected_meta.get("display_name", "Предмет"))
	inventory_item_meta.text = "Слот: %s | Редкость: %s" % [
		String(_inventory_selected_meta.get("slot", "-")),
		String(_inventory_selected_meta.get("rarity", "-")),
	]
	var slot := String(_inventory_selected_meta.get("slot", ""))
	var item_key := String(_inventory_selected_meta.get("item_key", ""))
	var equipped := false
	if slot.begins_with("weapon:"):
		equipped = ProfileState.get_equipped_weapon_skin(slot.trim_prefix("weapon:")) == item_key
	inventory_equip_btn.disabled = equipped or slot.is_empty() or item_key.is_empty()


func _on_inventory_equip_pressed() -> void:
	var slot := String(_inventory_selected_meta.get("slot", ""))
	var item_key := String(_inventory_selected_meta.get("item_key", ""))
	if slot.is_empty() or item_key.is_empty():
		return
	var ok := await ProfileState.equip_cosmetic(slot, item_key)
	if not ok:
		show_error("Не удалось экипировать предмет")
		return
	_refresh_economy_ui()


func _on_weapon_skin_selected(weapon_short_name: String, option: OptionButton, index: int) -> void:
	var item_key := String(option.get_item_metadata(index))
	if item_key.is_empty():
		return
	await ProfileState.equip_cosmetic("weapon:%s" % weapon_short_name, item_key)
	_refresh_economy_ui()


func _on_dev_grant_pressed() -> void:
	var ok := await ProfileState.grant_dev_currency("soft", 1000)
	if not ok:
		show_error("Backend dev grant недоступен")


func _on_open_case_pressed() -> void:
	if case_option.get_item_count() == 0:
		show_error("Нет доступных кейсов")
		return
	var case_key := String(case_option.get_item_metadata(case_option.selected))
	var result := await ProfileState.open_case(case_key)
	if not result.get("ok", false):
		show_error("Кейс недоступен: %s" % str(result.get("error", result.get("raw", "offline"))))
		return
	var data: Dictionary = result.get("data", {})
	show_error("Выпало: %s" % String(data.get("granted_item_key", "unknown")))


func _refresh_auth_ui() -> void:
	auth_status_label.text = "Auth: %s" % AuthState.status
	var authenticated := AuthState.is_authenticated()
	login_btn.disabled = authenticated
	register_btn.disabled = authenticated
	logout_btn.disabled = not authenticated
	email_edit.editable = not authenticated
	password_edit.editable = not authenticated
	if authenticated:
		var account: Dictionary = AuthState.account
		email_edit.text = String(account.get("email", email_edit.text))
		ProfileState.load_profile(name_edit.text)
