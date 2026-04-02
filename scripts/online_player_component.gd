class_name OnlinePlayerComponent extends CharacterBody3D 

@export var speed := 5.0
@export var mouse_sensitivity := 0.002
@export var jump_velocity = 30

@export var game_manager: GameManager

@onready var name_label = $Label3D
@onready var camera = $Camera3D
@onready var anim = $AnimationTree

var target_position: Vector3

# prediction
var input_buffer = []
var last_server_tick = 0
var tick = 0

var rotation_x := 0.0
var input_dir = Vector2.ZERO

var is_local = true


func _ready():
	if is_multiplayer_authority():
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	name_label.text = Lobby.players[int(name)]["name"]


func _physics_process(delta):
	if is_multiplayer_authority():
		process_input(delta)
	else:
		global_transform.origin = global_transform.origin.lerp(target_position, 10 * delta)


func _unhandled_input(event):
	if !is_multiplayer_authority():
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		rotation_x -= event.relative.y * mouse_sensitivity
		rotation_x = clamp(rotation_x, -1.5, 1.5)
		camera.rotation.x = rotation_x



func process_input(delta):
	tick += 1
	var direction = Vector2.ZERO
	var is_jump = false
	
	if Input.is_action_pressed("move_forward"):
		direction -= transform.basis.y
	if Input.is_action_pressed("move_backward"):
		direction += transform.basis.y
	if Input.is_action_pressed("move_left"):
		direction -= transform.basis.x
	if Input.is_action_pressed("move_right"):
		direction += transform.basis.x

	if Input.is_action_just_pressed("move_jump"):
		is_jump = true
	
	direction = direction.normalized()
	
	#input_dir = Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	
	var cmd = {
		"tick": tick,
		"dir": direction,
		"jump": is_jump
	}
	
	input_buffer.append(cmd)
	
	get_node("/root/GameManager").rpc_id(1, "server_receive_input", cmd)
	
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_VISIBLE)
	
	apply_movement(cmd, delta)
	#handle_animation()



func process_server_input(cmd):
	last_server_tick = cmd.tick
	
	apply_movement(cmd, get_physics_process_delta_time())
	
	rpc_id(multiplayer.get_remote_sender_id(),
		"client_correct_state",
		global_transform.origin,
		last_server_tick
	)
	
	rpc("update_remote_position",global_transform.origin)



func apply_movement(cmd, delta):
	velocity.x = cmd.dir.x * speed * delta * 20
	velocity.z = cmd.dir.y * speed * delta * 20
	move_and_slide()



@rpc("any_peer","call_local")
func client_correct_state(server_pos: Vector3, server_tick: int):
	if multiplayer.get_remote_sender_id() != 1 || true:
		return
	
	#print(multiplayer.get_unique_id(), "  ", multiplayer.get_remote_sender_id())
	
	# 🔹 ставим “истинную” позицию
	global_transform.origin = server_pos

	#print(multiplayer.get_remote_sender_id(), global_transform.origin)

	# 🔹 удаляем старые команды
	input_buffer = input_buffer.filter(func(cmd):
		return cmd.tick > server_tick
	)
	# 🔹 переигрываем оставшиеся input’ы
	for cmd in input_buffer:
		apply_movement(cmd, get_physics_process_delta_time())



@rpc("any_peer")
func update_remote_position(pos):
	target_position = pos



func apply_gravity(delta):
	if not is_on_floor():
		velocity += get_gravity() * delta



func handle_animation():
	anim.set("parameters/conditions/moving", input_dir != Vector2.ZERO)
	anim.set("parameters/conditions/idle", input_dir == Vector2.ZERO)
	anim.set("parameters/BlendSpace2D/blend_position", input_dir)
