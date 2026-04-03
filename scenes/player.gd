class_name OnlinePlayer extends CharacterBody3D 

@export var speed := 5.0
@export var mouse_sensitivity := 0.002
@export var jump_velocity = 30

@onready var name_label: Label3D = $Label3D
@onready var camera = $Camera3D
@onready var anim = $AnimationTree

var player_info = {}
var target_position: Vector3

# prediction
var input_buffer = []
var last_server_tick = 0
var tick = 0

var rotation_x := 0.0
var input_dir = Vector2.ZERO

var input_queue: Array = []

var remote_player_id: int = 0   # ID владельца этого персонажа (установить при спавне)
var last_processed_tick: int = 0

func _ready():
	name_label.text = player_info["name"]
	if is_multiplayer_authority():
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if multiplayer.is_server():
		visible = false
		camera.current = false


func _physics_process(delta):
	if is_multiplayer_authority():
		process_input(delta)
	else:
		if multiplayer.is_server():
			#print("Server: _physics_process for remote player", name, " queue size ", input_queue.size())
			process_all_commands()
			
			#if input_queue.is_empty():
				#velocity.x = 0
				#velocity.z = 0
				#move_and_slide()
			
		elif !multiplayer.is_server():
			global_transform.origin = global_transform.origin.lerp(target_position, 10 * delta)
	apply_gravity(delta)
	handle_animation()


func _unhandled_input(event):
	if !is_multiplayer_authority():
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		rotation_x -= event.relative.y * mouse_sensitivity
		rotation_x = clamp(rotation_x, -1.5, 1.5)
		camera.rotation.x = rotation_x


# сбор инпута, отправка на сервер и применение локально на клиенте.
func process_input(_delta):
	tick += 1
	var direction = Vector3.ZERO
	var is_jump = false
	
	if Input.is_action_pressed("move_forward"):
		direction -= transform.basis.z
	if Input.is_action_pressed("move_backward"):
		direction += transform.basis.z
	if Input.is_action_pressed("move_left"):
		direction -= transform.basis.x
	if Input.is_action_pressed("move_right"):
		direction += transform.basis.x

	if Input.is_action_just_pressed("move_jump"):
		is_jump = true

	direction = direction.normalized()
	
	input_dir = Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	
	var cmd = {
		"tick": tick,
		"dir": direction,
		"raw_dir": input_dir,
		"rot": rotation,
		"jump": is_jump
	}
	
	input_buffer.append(cmd)
	
	# GameManager выполняет метод только на сервере. 
	# Хранит список игроков, затем server_receive_input вызывает _process_server_input у игрока, отправившего cmd 
	#get_node("/root/GameManager").rpc_id(1, "server_receive_input", cmd)
	rpc_id(1, "process_server_input", cmd) 
	#if !multiplayer.is_server():
		#print("ms - ", Time.get_ticks_usec(), " send input cmd - ", cmd)
	
	
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_VISIBLE)
	
	#if !multiplayer.is_server():
		#apply_movement(cmd)
	handle_animation()



func process_one_command():
	if input_queue.is_empty():
		return
	# сортировка на всякий случай (хотя команды должны приходить по порядку)
	input_queue.sort_custom(func(a,b): return a.tick < b.tick)
	var cmd = input_queue.pop_front()
	#print("Server applying cmd tick ", cmd.tick, " pos before ", global_transform.origin)
	apply_movement(cmd)              # применяем движение
	#print("Server pos after ", global_transform.origin)
	last_processed_tick = cmd.tick
	
	# теперь отправляем коррекцию владельцу с актуальной позицией и тиком
	rpc_id(remote_player_id, "client_correct_state", global_transform.origin, last_processed_tick)
	# и обновляем позицию для остальных клиентов
	rpc("update_remote_position", global_transform.origin)


func process_all_commands():
	var processed = 0
	while input_queue.size() > 0 and processed < 5:   # лимит, чтобы не тормозить
		var cmd = input_queue.pop_front()
		apply_movement(cmd)
		last_processed_tick = cmd.tick
		rpc_id(remote_player_id, "client_correct_state", global_transform.origin, last_processed_tick)
		rpc("update_remote_state", global_transform.origin, cmd)
		processed += 1
		


# Применение сервером полученного инпута
# Выполняется на нодах игроков только на узле сервера.
@rpc("any_peer", "unreliable", "call_local")
func process_server_input(cmd):
	if !multiplayer.is_server():
		return
	input_queue.append(cmd)
		#print("ms - ", Time.get_ticks_usec(), " processing input on server. player - ", multiplayer.get_remote_sender_id(), " cmd - ", cmd)



# Применение перемещения, используемое и локально и сервером
func apply_movement(cmd):
	#print("uniq id - ", multiplayer.get_unique_id(), " cmd - ", cmd, " sender - " ,multiplayer.get_remote_sender_id(), " delta - ", delta)
	velocity.x = cmd.dir.x * speed
	velocity.z = cmd.dir.z * speed
	if cmd["jump"]:
		velocity.y += jump_velocity
	move_and_slide()


# Корректировка положения игрока клиентом
@rpc("any_peer","call_local")
func client_correct_state(server_pos: Vector3, server_tick: int):
	if multiplayer.get_remote_sender_id() != 1:
		return
	#input_buffer = input_buffer.filter(func(c): return c.tick > server_tick)
	#if !multiplayer.is_server():
		#print("ms - ", Time.get_ticks_usec(), " client start correcting server_pos - ", server_pos, " server_tick - ", server_tick)
		##print(multiplayer.get_unique_id(), "  ", multiplayer.get_remote_sender_id())
		#print("correcting pos. transform before - ", global_transform.origin)
	global_transform.origin = server_pos
	#print(multiplayer.get_remote_sender_id(), global_transform.origin)



# Обновление позиции ноды, если она не является управляемым игроком
@rpc("any_peer")
func update_remote_state(pos,cmd):
	if !is_multiplayer_authority():
		target_position = pos
		rotation = cmd["rot"]
		input_dir = cmd["raw_dir"]




# unused
func apply_gravity(delta):
	if not is_on_floor():
		velocity += get_gravity() * delta



func handle_animation():
	anim.set("parameters/conditions/moving", input_dir != Vector2.ZERO)
	anim.set("parameters/conditions/idle", input_dir == Vector2.ZERO)
	anim.set("parameters/BlendSpace2D/blend_position", input_dir)
