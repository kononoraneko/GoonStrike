extends Node

@export var potato :bool = true:
	set(val):
		potato_changed.emit(val)

signal potato_changed(val)
