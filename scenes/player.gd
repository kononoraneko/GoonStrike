extends CharacterBody3D

@export var speed := 5.0
@export var mouse_sensitivity := 0.002
@export var jump_velocity = 30

@onready var name_label = $Label3D
@onready var camera = $Camera3D
@onready var anim = $AnimationTree

var rotation_x := 0.0
var input_dir = Vector2.ZERO

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
	update_state.rpc(global_position, rotation, input_dir)

@rpc("unreliable")
func update_state(pos, rot, in_dir):
	if not is_multiplayer_authority():
		global_position = pos
		rotation = rot
		input_dir = in_dir
		handle_animation()

func _physics_process(delta):
	if is_multiplayer_authority():
		process_input()
		send_state()
		apply_gravity(delta)


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

	if Input.is_action_just_pressed("move_jump"):
		jump()
	
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_VISIBLE)
	
	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	
	input_dir = Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	handle_animation()
	move_and_slide()

func apply_gravity(delta):
	if not is_on_floor():
		velocity += get_gravity() * delta

func jump():
	if is_on_floor():
		velocity.y += jump_velocity

func handle_animation():
	anim.set("parameters/conditions/moving", input_dir != Vector2.ZERO)
	anim.set("parameters/conditions/idle", input_dir == Vector2.ZERO)
	anim.set("parameters/BlendSpace2D/blend_position", input_dir)
