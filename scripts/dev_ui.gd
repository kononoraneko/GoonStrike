extends Control

@export var gm: GameManager 
@onready var log:RichTextLabel = $VBoxContainer/Log
@onready var chat_input:LineEdit = $VBoxContainer/HBoxContainer/ChatInput

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#Lobby.player_connected.connect(_on_player_connected)
	gm.player_spawned.connect(_on_player_connected)
	gm.player_despawned.connect(_on_player_disconnected)
	
	Lobby.message_recieved.connect(_on_message_recieved)

func _on_player_connected(id, player_info):
	log.append_text("Игрок " + player_info["name"] + "(" + str(id) + ") присоединился\n")

func _on_player_disconnected(id, player_info):
	log.append_text("Игрок " + player_info["name"] + "(" + str(id) + ") отсоединился\n")

func _on_Send_pressed():
	if chat_input.text.strip_edges() == "":
		return
	
	Lobby.handle_message.rpc(chat_input.text)
	chat_input.clear()

func _on_message_recieved(player_info, message):
	log.append_text(player_info["name"] + ": " + message + "\n")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
