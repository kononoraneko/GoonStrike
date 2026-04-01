extends CharacterBody3D

@export var speed := 5.0
@export var mouse_sensitivity := 0.002

@onready var name_label = $Label3D
@onready var camera = $Camera3D
@onready var anim = $AnimationTree

var rotation_x := 0.0

var is_local = true

func _ready():
	is_local = is_multiplayer_authority()
	if is_local:
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	name_label.text = Lobby.players[int(name)]["name"]

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		rotation_x -= event.relative.y * mouse_sensitivity
		rotation_x = clamp(rotation_x, -1.5, 1.5)
		camera.rotation.x = rotation_x


func send_state():
	update_state.rpc(global_position, rotation)

@rpc("unreliable")
func update_state(pos, rot):
	if not is_multiplayer_authority():
		global_position = pos
		rotation = rot

func _physics_process(delta):
	if is_multiplayer_authority():
		process_input()
		send_state()


func process_input():
	var direction = Vector3.ZERO
	
	if Input.is_action_pressed("move_forward"):
		direction -= transform.basis.z
		#anim.play("character_model/run_forward")
	if Input.is_action_pressed("move_backward"):
		direction += transform.basis.z
		#anim.play("character_model/run_backward")
	if Input.is_action_pressed("move_left"):
		direction -= transform.basis.x

	if Input.is_action_pressed("move_right"):
		direction += transform.basis.x

	
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_VISIBLE)
	
	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	
	anim.set("parameters/conditions/moving", direction != Vector3.ZERO)
	anim.set("parameters/conditions/idle", direction == Vector3.ZERO)
	anim.set("parameters/BlendSpace2D/blend_position", Vector2(direction.x, -direction.z))
	
	move_and_slide()
