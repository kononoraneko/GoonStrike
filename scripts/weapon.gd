extends Node3D
class_name Weapon

@export var damage := 25
@export var range := 100.0
@export var fire_rate := 0.2          # секунд между выстрелами
@export var bullet_scene: PackedScene  # визуальный эффект (трассер)
@export var muzzle_flash: PackedScene
@export var hit: PackedScene

var can_shoot := true
var shoot_timer: SceneTreeTimer
var owner_player: OnlinePlayer

var world_3d: World3D

func _ready():
	# Находим родительского OnlinePlayer (поднимаемся вверх)
	owner_player = get_parent() as OnlinePlayer
	if not owner_player:
		push_error("Weapon must be child of OnlinePlayer")
		return
	world_3d = get_world_3d()


func shoot(direction: Vector3) -> void:
	if not can_shoot:
		return
	can_shoot = false
	shoot_timer = get_tree().create_timer(fire_rate)
	shoot_timer.timeout.connect(func(): can_shoot = true)
	
	# Локальное предсказание (визуал, звук)
	var muzzle_pos = get_global_muzzle_position()
	play_effects(muzzle_pos)
	show_tracer(muzzle_pos, muzzle_pos + direction * range)
	
	# Отправляем запрос на сервер
	if owner_player.is_multiplayer_authority():
		rpc_id(1, "server_request_shoot", muzzle_pos, direction)

@rpc("any_peer", "reliable")
func server_request_shoot(muzzle_pos: Vector3, direction: Vector3) -> void:
	# Только сервер исполняет
	if not multiplayer.is_server():
		return
	# Проверяем, что запрос пришёл от владельца оружия
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != owner_player.remote_player_id:
		return
	
	# Выполняем рейкаст от дула до цели
	var target_pos = muzzle_pos + direction * range
	var params = PhysicsRayQueryParameters3D.new()
	params.from = muzzle_pos
	params.to = target_pos
	params.collision_mask = 2   # например, слой "игроки" (настройте по своему)
	params.exclude = [owner_player]  # не стрелять в себя
	
	var result = world_3d.direct_space_state.intersect_ray(params)
	var hit_player: OnlinePlayer = null
	var hit_point: Vector3 = target_pos
	
	if result:
		hit_point = result.position
		# Проверяем, попали ли в OnlinePlayer
		if result.collider is OnlinePlayer:
			hit_player = result.collider
			# Наносим урон
			hit_player.take_damage(damage, owner_player)
	
	# Уведомляем всех игроков о выстреле (для визуала)
	rpc("broadcast_shot", muzzle_pos, hit_point, hit_player != null, sender_id)


@rpc("any_peer","reliable", "call_local")
func broadcast_shot(muzzle_pos: Vector3, hit_point: Vector3, hit_success: bool, shooter_id: int):
	#print("broadcast_shot on client ", multiplayer.get_unique_id(), " shooter_id ", shooter_id, " hit_success ", hit_success)
	# На всех клиентах показываем трассер и эффект попадания
	if multiplayer.get_unique_id() != shooter_id:
		#print("  -> showing effects for client ", multiplayer.get_unique_id())
		play_effects(muzzle_pos)
		show_tracer(muzzle_pos, hit_point)
	if hit_success:
		show_hit_effect(hit_point)


func play_effects(muzzle_pos: Vector3):
	# Воспроизвести звук, анимацию отдачи, вспышку
	if muzzle_flash:
		var flash = muzzle_flash.instantiate()
		get_tree().root.add_child(flash)
		flash.global_position = muzzle_pos
		# Удалить через 0.1 сек
		await get_tree().create_timer(0.1).timeout
		flash.queue_free()


func show_tracer(from: Vector3, to: Vector3):
	var mesh = ImmediateMesh.new()
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.ORANGE
	
	material.emission_enabled = true
	material.emission = Color.ORANGE
	material.emission_energy_multiplier = 5.0
	
	var line = MeshInstance3D.new()
	line.mesh = mesh
	line.material_override = material
	get_tree().root.add_child(line)
	
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	
	await get_tree().create_timer(0.1).timeout
	line.queue_free()
	#if bullet_scene:
		##print("tracer pos from - ", from, " to - ", to)
		#
		#print("show_tracer on client ", multiplayer.get_unique_id(), " from ", from, " to ", to)
		#var tracer = bullet_scene.instantiate()
		#
		#get_tree().root.add_child(tracer)
		#tracer.global_position = from
		#
		#var distance = from.distance_to(to)
		#var speed = 2000.0 
		#var duration = distance / speed
		#duration = clamp(duration, 0.02, 0.2)
		#
		#var tween = create_tween()
		#tween.tween_property(tracer, "global_position", to, duration)
		#tween.finished.connect(func(): tracer.queue_free())



func show_hit_effect(pos: Vector3):
	# Эффект попадания (кровь, искры)
	var hit = hit.instantiate()
	get_tree().root.add_child(hit)
	hit.global_position = pos
	# Удалить через 0.1 сек
	await get_tree().create_timer(0.1).timeout
	hit.queue_free()



func get_global_muzzle_position() -> Vector3:
	
	# Предполагаем, что у оружия есть узел Marker3D "Muzzle"
	var muzzle = $"../Camera3D/Muzzle"
	if muzzle:
		#print("muzzle pos - ", muzzle.global_position)
		return muzzle.global_position
	return global_position  # запасной вариант
