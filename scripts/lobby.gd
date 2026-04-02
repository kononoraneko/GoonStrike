extends Node

signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id, player_info)
signal server_disconnected
signal message_recieved(player_info, message)

const PORT = 7000
const DEFAULT_SERVER_IP = "127.0.0.1" # IPv4 localhost
const MAX_CONNECTIONS = 20

var players = {}

var player_info = {"name": "Name", "hp": 100}

var players_loaded = 0

func _ready():
	set_multiplayer_authority(1)
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func join_game(address = ""):
	if address.is_empty():
		address = DEFAULT_SERVER_IP
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, PORT)
	if error:
		return error
	multiplayer.multiplayer_peer = peer

func create_game():
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_CONNECTIONS)
	if error:
		return error
	multiplayer.multiplayer_peer = peer

	players[1] = player_info
	player_connected.emit(1, player_info)

func remove_multiplayer_peer():
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()

@rpc("call_local", "reliable")
func load_game(game_scene_path):
	get_tree().change_scene_to_file(game_scene_path)

@rpc("any_peer", "call_local", "reliable")
func player_loaded():
	if multiplayer.is_server():
		players_loaded += 1
		if players_loaded == players.size():
			$/root/Game.start_game()
			players_loaded = 0

func _on_player_connected(id):
	_register_player.rpc_id(id, player_info)

@rpc("any_peer", "reliable")
func _register_player(new_player_info):
	var new_player_id = multiplayer.get_remote_sender_id()
	players[new_player_id] = new_player_info
	player_connected.emit(new_player_id, new_player_info)

@rpc("call_local")
func send_message(player_info,message):
	message_recieved.emit(player_info, message)

@rpc("any_peer", "call_local")
func handle_message(message):
	if multiplayer.is_server():
		print(multiplayer.get_remote_sender_id())
		send_message.rpc(players[multiplayer.get_remote_sender_id()], message)

func _on_player_disconnected(id):
	var p_i = players[id].duplicate()
	players.erase(id)
	player_disconnected.emit(id, p_i)

func _on_connected_ok():
	var peer_id = multiplayer.get_unique_id()
	players[peer_id] = player_info
	player_connected.emit(peer_id, player_info)

func set_playername(new_name):
	player_info["name"] = new_name

func _on_connected_fail():
	remove_multiplayer_peer()


func _on_server_disconnected():
	remove_multiplayer_peer()
	players.clear()
	server_disconnected.emit()
