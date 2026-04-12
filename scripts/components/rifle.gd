class_name Rifle extends Weapon
 
#var _auto_timer: SceneTreeTimer
 #
#func _unhandled_input(event: InputEvent) -> void:
	#if not owner_player or not owner_player.is_multiplayer_authority():
		#return
	#if not data or not data.is_automatic:
		#return
 #
	#if event.is_action_pressed("shoot"):
		#_start_auto_fire()
	#elif event.is_action_released("shoot"):
		#_stop_auto_fire()
 #
 #
#func _start_auto_fire() -> void:
	#_fire_once()
	#_auto_timer = get_tree().create_timer(data.fire_rate)
	#_auto_timer.timeout.connect(_start_auto_fire)
 #
 #
#func _stop_auto_fire() -> void:
	#if _auto_timer:
		## Отключаем повтор — обнуляем ссылку, таймер сам умрёт
		#if _auto_timer.timeout.is_connected(_start_auto_fire):
			#_auto_timer.timeout.disconnect(_start_auto_fire)
		#_auto_timer = null
 #
 #
#func _fire_once() -> void:
	#var aim_ray := owner_player.get_aim_ray()
	#shoot(aim_ray)
