class_name Weapon extends Node3D

## Базовый класс оружия. Конкретные оружия (Rifle, Pistol) наследуют его.
## Weapon не знает про сеть — он только выполняет стрельбу и визуалы.
## Всю сетевую логику делегирует владельцу через сигналы.

signal shot_requested(muzzle_pos: Vector3, direction: Vector3)

@export var data: WeaponData

@onready var muzzle: Marker3D = $Muzzle

var can_shoot := true
var owner_player: OnlinePlayer

func _ready() -> void:
	var node := get_parent()
	while node != null:
		if node is OnlinePlayer:
			owner_player = node
			break
		node = node.get_parent()

	assert(owner_player != null, "Weapon must be placed inside an OnlinePlayer subtree")


## Вызывается клиентом при нажатии кнопки стрельбы.
## Выполняет локальный визуал и отправляет сигнал для RPC.
func shoot(direction: Vector3) -> void:
	if not can_shoot or data == null:
		return
	can_shoot = false
	get_tree().create_timer(data.fire_rate).timeout.connect(func(): can_shoot = true)

	var muzzle_pos := get_global_muzzle_position()
	play_effects(muzzle_pos)
	show_tracer(muzzle_pos, muzzle_pos + direction * data.range)

	shot_requested.emit(muzzle_pos, direction)


## Вызывается у всех клиентов через broadcast (из WeaponHolder / NetworkComponent).
func on_broadcast_shot(muzzle_pos: Vector3, hit_point: Vector3, hit_success: bool, shooter_id: int) -> void:
	if multiplayer.get_unique_id() != shooter_id:
		play_effects(muzzle_pos)
		show_tracer(muzzle_pos, hit_point)
		owner_player.animation.play_shoot()
	if hit_success:
		show_hit_effect(hit_point)


func get_global_muzzle_position() -> Vector3:
	if muzzle:
		return muzzle.global_position
	return global_position


func play_effects(muzzle_pos: Vector3) -> void:
	if data == null or data.muzzle_flash_scene == null:
		return
	var flash := data.muzzle_flash_scene.instantiate()
	get_tree().root.add_child(flash)
	flash.global_position = muzzle_pos
	get_tree().create_timer(0.1).timeout.connect(flash.queue_free)


func show_tracer(from: Vector3, to: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.ORANGE
	material.emission_enabled = true
	material.emission = Color.ORANGE
	material.emission_energy_multiplier = 5.0

	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.material_override = material
	get_tree().root.add_child(line)

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()

	get_tree().create_timer(0.1).timeout.connect(line.queue_free)


func show_hit_effect(pos: Vector3) -> void:
	if data == null or data.hit_scene == null:
		return
	var hit_instance := data.hit_scene.instantiate()
	get_tree().root.add_child(hit_instance)
	hit_instance.global_position = pos
	get_tree().create_timer(0.1).timeout.connect(hit_instance.queue_free)
