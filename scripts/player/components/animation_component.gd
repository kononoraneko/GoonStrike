class_name AnimationComponent extends Node
 
@onready var anim: AnimationTree = $"../AnimationTree"
@onready var animLegs: AnimationTree = $"../AnimationTreeLegs"
@onready var animArms: AnimationTree = $"../AnimationTreeArms"

func _ready() -> void:
	if anim:
		anim.connect("animation_finished", _on_animation_finished)
	if animArms:
		animArms.connect("animation_finished", _on_animation_finished)

var _shoot_timer: SceneTreeTimer
var _hit_timer: SceneTreeTimer
var _reload_reset_timer: SceneTreeTimer
 
func update(input_dir: Vector2) -> void:
	anim.set("parameters/Locomotion/conditions/moving", input_dir != Vector2.ZERO)
	anim.set("parameters/Locomotion/conditions/idle",   input_dir == Vector2.ZERO)
	anim.set("parameters/Locomotion/BlendSpace2D/blend_position", input_dir)
	if animLegs:
		animLegs.set("parameters/conditions/moving", input_dir != Vector2.ZERO)
		animLegs.set("parameters/conditions/idle",   input_dir == Vector2.ZERO)
		animLegs.set("parameters/BlendSpace2D/blend_position", input_dir)
	if animArms:
		animArms.set("parameters/conditions/moving", input_dir != Vector2.ZERO)
		animArms.set("parameters/conditions/idle",   input_dir == Vector2.ZERO)
		animArms.set("parameters/BlendSpace2D/blend_position", input_dir)
 
 
func play_shoot() -> void:
	if not is_inside_tree(): return
	anim.set("parameters/Action/conditions/shoot", true)
	if _shoot_timer and _shoot_timer.timeout.is_connected(_reset_shoot):
		_shoot_timer.timeout.disconnect(_reset_shoot)
	_shoot_timer = get_tree().create_timer(0.1)
	_shoot_timer.timeout.connect(_reset_shoot)
 
func _reset_shoot() -> void:
	anim.set("parameters/Action/conditions/shoot", false)
 
 
func play_hit() -> void:
	if not is_inside_tree(): return
	anim.set("parameters/Action/conditions/hit", true)
	if _hit_timer and _hit_timer.timeout.is_connected(_reset_hit):
		_hit_timer.timeout.disconnect(_reset_hit)
	_hit_timer = get_tree().create_timer(0.2)
	_hit_timer.timeout.connect(_reset_hit)
 
func _reset_hit() -> void:
	anim.set("parameters/Action/conditions/hit", false)


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
	if animArms:
		animArms.set("parameters/Action/conditions/reload", value)



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
