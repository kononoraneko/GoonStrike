extends Control

@export var player: OnlinePlayer
@onready var hp_label = $HBoxContainer/MarginContainer/HpLabel

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if !is_multiplayer_authority():
		queue_free()
	hp_label.text = str(player.health)
	player.damage_taken.connect(_on_damage_taken)

func _on_damage_taken(cur_hp):
	hp_label.text = str(cur_hp)
	print("HELLO ")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
