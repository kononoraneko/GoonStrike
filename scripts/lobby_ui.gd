extends Control

@onready var chat_log = $VBoxContainer/ChatLog
@onready var input = $VBoxContainer/HBoxContainer/MessageInput

var lobby

func _ready():
	lobby = Lobby
	lobby.player_connected.connect(_on_player_connected)
	lobby.message_recieved.connect(_on_message_recieved)
	
	

func _on_Send_pressed():
	if input.text.strip_edges() == "":
		return
	
	lobby.handle_message.rpc(input.text)
	input.clear()

func _on_chat(name, message):
	chat_log.append_text(name + ": " + message + "\n")

func _on_message_recieved(player_info, message):
	chat_log.append_text(player_info["name"] + ": " + message + "\n")

func _on_player_connected(id, player_info):
	_on_chat(player_info["name"],"connected")
