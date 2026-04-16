class_name WeaponData extends Resource

## Ресурс с данными конкретного оружия.
## Создаётся в редакторе как .tres файл для каждого оружия.
## WeaponPickup и WeaponHolder работают только с этим ресурсом —
## они не знают о конкретных классах Rifle, Pistol и т.д.

@export var weapon_name: String = "Unnamed"
@export var damage: int = 25
@export var range: float = 100.0
@export var fire_rate: float = 0.2          # секунд между выстрелами
@export var is_automatic: bool = false       # автоматический огонь
@export var magazine_size: int = 30          # патронов в магазине
@export var reserve_ammo: int = 90           # запас патронов
@export var reload_time: float = 1.6         # длительность перезарядки
@export var spread_pattern: SpreadPattern

@export_group("Sniper scope")
@export var has_sniper_scope: bool = false
## Если scope_stage_fovs пуст или один элемент — fallback от этого FOV.
@export var scope_fov: float = 22.0
## Два FOV: ступень 1 и 2 (цикл ПКМ 0 → 1 → 2 → 0).
@export var scope_stage_fovs: Array[float] = [36.0, 18.0]
@export var scope_spread_multiplier: float = 0.15


func get_scope_stage_count() -> int:
	return 2


func resolve_scope_fovs() -> Array[float]:
	if scope_stage_fovs.size() >= 2:
		return [scope_stage_fovs[0], scope_stage_fovs[1]]
	if scope_stage_fovs.size() == 1:
		var a := scope_stage_fovs[0]
		return [a, a * 0.65]
	var f := scope_fov
	return [f * 1.25, f * 0.72]


func get_scope_fov_for_stage(stage: int) -> float:
	var arr := resolve_scope_fovs()
	var idx := clampi(stage - 1, 0, 1)
	return arr[idx]

@export_group("Scenes")
@export var weapon_scene: PackedScene        # сцена самого оружия (Node3D)
@export var bullet_scene: PackedScene        # трассер
@export var muzzle_flash_scene: PackedScene
@export var hit_scene: PackedScene
@export var pickup_icon: Texture2D           # иконка для HUD
@export var pickup_physics_shape: Shape3D    # форма физики world-pickup (fallback: shape из pickup_scene)
