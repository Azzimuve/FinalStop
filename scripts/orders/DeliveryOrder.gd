extends RefCounted

const CargoItem = preload("res://scripts/simulation/CargoItem.gd")
var cargo: Array[CargoItem] = []
var delivered_cargo: Array[CargoItem] = []
var lost_cargo: Array[CargoItem] = []
const PassengerProfile = preload("res://scripts/orders/PassengerProfile.gd")
var manifest: Array[PassengerProfile] = []
var decisions: Array[bool] = []
var passenger_name := ""
var passenger_count: int = 0
var passengers_picked_up: bool = false


func is_passenger_order() -> bool:
	return passenger_count > 0


func onboard_count() -> int:
	return decisions.count(true)

func payable_reward() -> int:
	if not is_passenger_order() or not passengers_picked_up:
		return reward
	return roundi(float(reward) * onboard_count() / passenger_count)

func trip_passenger_count() -> int:
	return onboard_count() if passengers_picked_up else passenger_count

func has_pending_pickup() -> bool:
	return not passengers_picked_up if is_passenger_order() else not remaining_cargo().is_empty()


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

var is_urgent: bool = false

var dispatch_number := 0
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
