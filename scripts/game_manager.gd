class_name GameManager extends Node3D 

var player_scene = preload("res://scenes/Player_character.tscn")
var players_nodes = {}

@onready var log = $Control/Log

signal player_spawned(id, p_info)
signal player_despawned(id, p_info)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Lobby.player_connected.connect(_on_player_connected)
	Lobby.player_disconnected.connect(_on_player_disconnected)

	for player in Lobby.players:
		spawn_player(player)

func _on_player_connected(id, info):
	spawn_player(id)
	#if multiplayer.is_server():
		#spawn_player(id)

func _on_player_disconnected(id, p_info):
	players_nodes[id].queue_free()
	players_nodes.erase(id)
	player_despawned.emit(id, p_info)

func spawn_player(id):
	player_spawned.emit(id, Lobby.players[id])
	var player = player_scene.instantiate()
	player.name = str(id)
	player.set_multiplayer_authority(id)
	
	add_child(player)
	players_nodes[id] = player
