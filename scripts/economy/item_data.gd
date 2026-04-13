class_name ItemData extends Resource

## Заготовка под скины, стикеры, дроп с кейсов. Игровая логика пока не подключена.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

@export var item_id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D
@export var rarity: Rarity = Rarity.COMMON
