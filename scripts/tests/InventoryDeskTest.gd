extends "res://scripts/tests/CustomRouteTest.gd"

const CargoItem = preload("res://scripts/simulation/CargoItem.gd")

@export var parcel: CargoItem = preload("res://resources/items/test_crate.tres")

func _ready() -> void:
	super()
	game.vehicle.inventory.place(parcel.duplicate(true), Vector2i.ZERO, false)
	game.sheet_button.button_pressed = true
	game._open_inventory()
