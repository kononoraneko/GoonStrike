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

@export_group("Scenes")
@export var weapon_scene: PackedScene        # сцена самого оружия (Node3D)
@export var bullet_scene: PackedScene        # трассер
@export var muzzle_flash_scene: PackedScene
@export var hit_scene: PackedScene
@export var pickup_icon: Texture2D           # иконка для HUD
