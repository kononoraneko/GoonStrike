class_name AnimationComponent extends Node

@onready var anim: AnimationTree = $"../AnimationTree"
@onready var anim_legs: AnimationTree = $"../AnimationTreeLegs"
@onready var anim_arms: AnimationTree = $"../AnimationTreeArms"

func _ready() -> void:
	if anim:
		anim.animation_finished.connect(_on_animation_finished)
	if anim_arms:
		anim_arms.animation_finished.connect(_on_animation_finished)

var _shoot_timer: SceneTreeTimer
var _hit_timer: SceneTreeTimer
var _reload_reset_timer: SceneTreeTimer
 
func update(input_dir: Vector2) -> void:
	anim.set("parameters/Locomotion/conditions/moving", input_dir != Vector2.ZERO)
	anim.set("parameters/Locomotion/conditions/idle",   input_dir == Vector2.ZERO)
	anim.set("parameters/Locomotion/BlendSpace2D/blend_position", input_dir)
	if anim_legs:
		anim_legs.set("parameters/conditions/moving", input_dir != Vector2.ZERO)
		anim_legs.set("parameters/conditions/idle",   input_dir == Vector2.ZERO)
		anim_legs.set("parameters/BlendSpace2D/blend_position", input_dir)
	if anim_arms:
		anim_arms.set("parameters/conditions/moving", input_dir != Vector2.ZERO)
		anim_arms.set("parameters/conditions/idle",   input_dir == Vector2.ZERO)
		anim_arms.set("parameters/BlendSpace2D/blend_position", input_dir)
 
 
func play_shoot() -> void:
	_pulse_action_condition("parameters/Action/conditions/shoot", 0.1, _reset_shoot, "shoot")


func _reset_shoot() -> void:
	anim.set("parameters/Action/conditions/shoot", false)


func play_hit() -> void:
	_pulse_action_condition("parameters/Action/conditions/hit", 0.2, _reset_hit, "hit")


func _reset_hit() -> void:
	anim.set("parameters/Action/conditions/hit", false)


func _pulse_action_condition(param_path: String, duration_sec: float, reset_fn: Callable, slot: String) -> void:
	if not is_inside_tree():
		return
	anim.set(param_path, true)
	var old_timer := _shoot_timer if slot == "shoot" else _hit_timer
	if old_timer != null and old_timer.timeout.is_connected(reset_fn):
		old_timer.timeout.disconnect(reset_fn)
	var new_timer := get_tree().create_timer(duration_sec)
	new_timer.timeout.connect(reset_fn)
	if slot == "shoot":
		_shoot_timer = new_timer
	else:
		_hit_timer = new_timer


func play_reload() -> void:
	set_reloading(true)

func set_reloading(value: bool, reload_duration: float = -1.0) -> void:
	_set_reload_condition(value)
	if _reload_reset_timer and _reload_reset_timer.timeout.is_connected(_reset_reload):
		_reload_reset_timer.timeout.disconnect(_reset_reload)
	if value and reload_duration > 0.0:
		_reload_reset_timer = get_tree().create_timer(reload_duration)
		_reload_reset_timer.timeout.connect(_reset_reload)


func _reset_reload() -> void:
	_set_reload_condition(false)



func _set_reload_condition(value: bool) -> void:
	anim.set("parameters/Action/conditions/reload", value)
	if anim_arms:
		anim_arms.set("parameters/Action/conditions/reload", value)



func _set_tree_player_speed(tree: AnimationTree, speed_scale: float) -> void:
	if tree == null:
		return
	var path := tree.get("anim_player") as NodePath
	if path.is_empty():
		return
	var player := tree.get_node_or_null(path) as AnimationPlayer
	if player:
		player.speed_scale = speed_scale


func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "char/reloading":
		_reset_reload()
