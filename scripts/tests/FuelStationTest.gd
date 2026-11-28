extends "res://scripts/tests/CustomRouteTest.gd"

@export var initial_liters := 18.0
@export var initial_credits := 300.0

func _ready() -> void:
	super()
	game.vehicle.fuel_liters = clampf(initial_liters, 0.0, game.vehicle.settings.fuel_tank_capacity_liters)
	game.money_credits = initial_credits
	game._refresh_interface()
	game._on_refuel_pressed()
