extends Node

@export var start_city := "nearby_settlement"
@export var start_place := "settlement_shop"
@export_range(1.35, 2.4) var map_zoom := 1.4
@onready var game := $Game

func _ready() -> void:
	game.prologue.step = game.prologue.Step.FREE
	game.prologue._refresh()
	game.prologue._close_radio()
	game.prologue.set_process(false)
	game.travel_events.events.clear()
	game.road_bulletins.chance_percent = 0
	game.vehicle.fuel_liters = game.vehicle.settings.fuel_tank_capacity_liters
	game.current_city_id = start_city
	game.current_location_id = start_place
	var map = game.map_view
	game.current_city_name = map.routes.cities_by_id[start_city].name
	map._cancel_camera_transition()
	map.set_current_location(start_city, start_place, false)
	map.camera.position = map.routes.cities_by_id[start_city].position
	map.camera.zoom = Vector2.ONE * map_zoom
	map.target_zoom = map_zoom
	game._refresh_interface()
	game.status_label.text = "ЛКМ по дороге — к ближайшему городу или объекту. Shift + ЛКМ — к следующему по этой дороге."
