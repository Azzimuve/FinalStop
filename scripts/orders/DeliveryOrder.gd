extends RefCounted

const CargoItem = preload("res://scripts/simulation/CargoItem.gd")
var cargo: Array[CargoItem] = []
var delivered_cargo: Array[CargoItem] = []
var lost_cargo: Array[CargoItem] = []


func remaining_cargo() -> Array[CargoItem]:
	var remaining: Array[CargoItem] = []
	for item in cargo:
		if not delivered_cargo.has(item) and not lost_cargo.has(item):
			remaining.append(item)
	return remaining


func cargo_text() -> String:
	var names := PackedStringArray()
	for item in cargo:
		names.append("%s %d×%d" % [item.title, item.size.x, item.size.y])
	return ", ".join(names)

var title: String
var pickup_city_id: String
var pickup_city_name: String
var pickup_location_id: String
var pickup_name: String
var delivery_city_id: String
var delivery_city_name: String
var delivery_location_id: String
var delivery_name: String
var distance_km: float
var reward: int
var deadline_total_minutes: float
