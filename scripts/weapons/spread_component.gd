## SpreadComponent.gd
## Дочерний узел Weapon. Вычисляет итоговое направление с учётом разброса.
## Weapon вызывает apply(direction) и получает отклонённый вектор.
##
## Структура в сцене:
## Rifle  (Weapon)
## ├── Muzzle  (Marker3D)
## └── SpreadComponent  (Node, SpreadComponent.gd)

class_name SpreadComponent extends Node

var _current_bloom: float = 0.0
var _pattern_index: int = 0
var _reset_timer: SceneTreeTimer = null
var _data: SpreadPattern = null


## Вызывается из Weapon._ready() сразу после того, как data назначена.
## Кэширует паттерн — больше не лезем к родителю каждый кадр/выстрел.
func init(pattern: SpreadPattern) -> void:
	_data = pattern
	reset()


func _process(delta: float) -> void:
	# Ранний выход: bloom нужен только в режиме BLOOM
	if _data == null or _data.mode != SpreadPattern.SpreadMode.BLOOM:
		return
	_current_bloom = move_toward(_current_bloom, 0.0, _data.bloom_recovery * delta)


## Вызывается из Weapon.shoot() вместо прямой передачи direction.
## spread_scale: 1.0 обычный разброс; меньше 1 (ADS) — сужает конус.
func apply(base_direction: Vector3, is_moving: bool, is_airborne: bool, spread_scale: float = 1.0) -> Vector3:
	if _data == null:
		return base_direction
	var s := clampf(spread_scale, 0.0, 8.0)
	match _data.mode:
		SpreadPattern.SpreadMode.RANDOM:
			return _apply_random(base_direction, is_moving, is_airborne, s)
		SpreadPattern.SpreadMode.BLOOM:
			return _apply_bloom(base_direction, is_moving, is_airborne, s)
		SpreadPattern.SpreadMode.PATTERN:
			return _apply_pattern(base_direction, s)
	return base_direction


func get_current_spread_angle(is_moving: bool, is_airborne: bool, spread_scale: float = 1.0) -> float:
	if _data == null:
		return 0.0
	var s := clampf(spread_scale, 0.0, 8.0)
	var angle := _data.base_spread
	if _data.mode == SpreadPattern.SpreadMode.BLOOM:
		angle += _current_bloom
	if is_moving:
		angle *= _data.move_multiplier
	if is_airborne:
		angle *= _data.air_multiplier
	return maxf(angle * s, 0.0)


## Вызывается после каждого выстрела — обновляет внутреннее состояние.
func on_shot_fired() -> void:
	if _data == null:
		return
	match _data.mode:
		SpreadPattern.SpreadMode.BLOOM:
			_current_bloom = minf(_current_bloom + _data.bloom_per_shot, _data.bloom_max)
		SpreadPattern.SpreadMode.PATTERN:
			_pattern_index = (_pattern_index + 1) % _data.pattern_points.size()
			_restart_reset_timer()


## Сбрасывает состояние (например при смене оружия).
func reset() -> void:
	_current_bloom = 0.0
	_pattern_index = 0


# ── Режимы ────────────────────────────────────────────────────────────────

func _apply_random(dir: Vector3, is_moving: bool, is_airborne: bool, spread_scale: float) -> Vector3:
	var angle := _data.base_spread
	if is_moving:   angle *= _data.move_multiplier
	if is_airborne: angle *= _data.air_multiplier
	angle *= spread_scale
	return _random_cone(dir, deg_to_rad(angle))


func _apply_bloom(dir: Vector3, is_moving: bool, is_airborne: bool, spread_scale: float) -> Vector3:
	var angle := _data.base_spread + _current_bloom
	if is_moving:   angle *= _data.move_multiplier
	if is_airborne: angle *= _data.air_multiplier
	angle *= spread_scale
	return _random_cone(dir, deg_to_rad(angle))


func _apply_pattern(dir: Vector3, spread_scale: float) -> Vector3:
	if _data.pattern_points.is_empty():
		return dir
	var offset: Vector2 = _data.pattern_points[_pattern_index] * spread_scale
	# offset.x — горизонтальное отклонение (yaw), offset.y — вертикальное (pitch)
	var right := dir.cross(Vector3.UP).normalized()
	var up    := right.cross(dir).normalized()
	return dir.rotated(up, deg_to_rad(offset.x)).rotated(right, deg_to_rad(offset.y)).normalized()


# ── Утилиты ───────────────────────────────────────────────────────────────

## Равномерно случайная точка внутри конуса с половинным углом half_angle_rad.
func _random_cone(dir: Vector3, half_angle_rad: float) -> Vector3:
	if half_angle_rad <= 0.0:
		return dir
	var angle  := randf() * TAU
	var radius := sqrt(randf()) * tan(half_angle_rad)
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 0.001:
		right = dir.cross(Vector3.RIGHT)
	right = right.normalized()
	var up := right.cross(dir).normalized()
	return (dir + right * cos(angle) * radius + up * sin(angle) * radius).normalized()


func _restart_reset_timer() -> void:
	if _reset_timer != null and is_instance_valid(_reset_timer):
		if _reset_timer.timeout.is_connected(_on_pattern_reset):
			_reset_timer.timeout.disconnect(_on_pattern_reset)
	_reset_timer = get_tree().create_timer(_data.pattern_reset_time)
	_reset_timer.timeout.connect(_on_pattern_reset, CONNECT_ONE_SHOT)


func _on_pattern_reset() -> void:
	_pattern_index = 0
