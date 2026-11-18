extends "res://scripts/simulation/CargoItem.gd"

# Параметры конкретной модели детали сохраняются при её установке.
@export var model_name: String
var parameters: Dictionary:
	get:
		return {"speed_multiplier": 1.0 + float(properties.get("speed_bonus_percent", 0.0)) / 100.0}
@export var slot_type: String
@export var condition_percent: float = 100.0:
	set(value):
		condition_percent = clampf(value, 0.0, 100.0)


func repair() -> void:
	condition_percent = 100.0


func wear(amount_percent: float) -> void:
	condition_percent -= maxf(0.0, amount_percent)
