## SpreadPattern.gd  —  Resource
## Описывает КАК именно разбрасывает конкретное оружие.
## Создаётся в редакторе как .tres и назначается в WeaponData.
##
## Три режима (SpreadMode):
##   RANDOM   — случайный конус (пистолет, дробовик)
##   PATTERN  — фиксированная последовательность точек (как в CS:GO)
##   BLOOM    — конус расширяется при стрельбе, сужается в покое

class_name SpreadPattern extends Resource

enum SpreadMode { RANDOM, PATTERN, BLOOM }

@export var mode: SpreadMode = SpreadMode.RANDOM

# ── RANDOM и BLOOM ────────────────────────────────────────────────────────

## Базовый угол конуса в градусах (при стоянии/прицеливании)
@export var base_spread: float = 1.0

## Множитель при движении
@export var move_multiplier: float = 2.5

## Множитель при прыжке
@export var air_multiplier: float = 4.0

# ── BLOOM (только для этого режима) ───────────────────────────────────────

## На сколько градусов растёт конус за каждый выстрел
@export var bloom_per_shot: float = 0.8

## Максимальный угол конуса
@export var bloom_max: float = 6.0

## Скорость восстановления (градусов в секунду)
@export var bloom_recovery: float = 4.0

# ── PATTERN ───────────────────────────────────────────────────────────────

## Список точек паттерна: Vector2(yaw_deg, pitch_deg)
## Первый выстрел — points[0], второй — points[1] и т.д.
## После последней точки цикл сбрасывается.
@export var pattern_points: Array[Vector2] = []

## Через сколько секунд без стрельбы сбрасывается позиция в паттерне
@export var pattern_reset_time: float = 0.4
