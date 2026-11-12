extends "res://scripts/simulation/CargoItem.gd"

# Параметры конкретной модели детали сохраняются при её установке.
var model_name: String
var parameters: Dictionary
var slot_type: String
var condition_percent: float = 100.0:
	set(value):
		condition_percent = clampf(value, 0.0, 100.0)


func _init(name: String = "Стандартная", specifications: Dictionary = {}, footprint: Vector2i = Vector2i(2, 2)) -> void:
	super(name, footprint)
	price_credits = 600.0
	model_name = name
	parameters = specifications.duplicate(true)
	size = footprint


func repair() -> void:
	condition_percent = 100.0


func wear(amount_percent: float) -> void:
	condition_percent -= maxf(0.0, amount_percent)
