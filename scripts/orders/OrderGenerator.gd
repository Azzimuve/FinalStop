extends RefCounted

const DeliveryOrder = preload("res://scripts/orders/DeliveryOrder.gd")
const CargoItem = preload("res://scripts/simulation/CargoItem.gd")
const RoutePlanner = preload("res://scripts/map/RoutePlanner.gd")
const WorldMapData = preload("res://scripts/WorldMapData.gd")
const GameClock = preload("res://scripts/simulation/GameClock.gd")
const TravelRules = preload("res://scripts/simulation/TravelRules.gd")

const DEADLINE_BUFFER_MINUTES: float = 300.0
const CARD_COUNT: int = 3

var settings: GameBalanceSettings


func _init(balance_settings: GameBalanceSettings) -> void:
	settings = balance_settings


func generate(routes: RoutePlanner, current_minutes: float) -> Array[DeliveryOrder]:
	var offers: Array[DeliveryOrder] = []
	var company_city: Dictionary = routes.cities_by_id[WorldMapData.START_CITY_ID]
	var pickup_places: Array[Dictionary] = []
	for place in company_city["places"]:
		if place.get("type", "") in ["warehouse", "stop"]:
			pickup_places.append(place)

	var delivery_places: Array[Dictionary] = []
	for city in routes.cities:
		for place in city["places"]:
			if place.get("type", "") in ["delivery_point", "store", "stop"]:
				delivery_places.append({"city": city, "place": place})

	for pickup in pickup_places:
		for destination_data in delivery_places:
			var destination_city: Dictionary = destination_data["city"]
			var destination_place: Dictionary = destination_data["place"]
			if (
				destination_city["id"] == company_city["id"]
				and destination_place["id"] == pickup["id"]
			):
				continue
			var distance: float = routes.get_route_distance(
				company_city["id"],
				pickup["id"],
				destination_city["id"],
				destination_place["id"]
			)
			if distance <= 0.0:
				continue
			var estimated_minutes := TravelRules.duration_for_distance(distance) * GameClock.GAME_MINUTES_PER_REAL_SECOND
			var order := DeliveryOrder.new()
			order.cargo = [CargoItem.new("Тестовый ящик", Vector2i(2, 2)), CargoItem.new("Тестовая коробка", Vector2i(1, 2)), CargoItem.new("Тестовый длинный груз", Vector2i(1, 4))]
			order.cargo.append(CargoItem.new("Тестовый маленький предмет", Vector2i(1, 1)))
			order.title = "Доставка груза: %s" % destination_place["name"]
			order.pickup_city_id = company_city["id"]
			order.pickup_city_name = company_city["name"]
			order.pickup_location_id = pickup["id"]
			order.pickup_name = pickup["name"]
			order.delivery_city_id = destination_city["id"]
			order.delivery_city_name = destination_city["name"]
			order.delivery_location_id = destination_place["id"]
			order.delivery_name = destination_place["name"]
			order.distance_km = distance * TravelRules.DISTANCE_KM_PER_UNIT
			order.reward = roundi(distance / 100.0 * settings.order_payment_per_100_distance_units)
			order.deadline_total_minutes = current_minutes + estimated_minutes + DEADLINE_BUFFER_MINUTES
			offers.append(order)

	offers.shuffle()
	var selected_offers: Array[DeliveryOrder] = []
	for index in range(mini(CARD_COUNT, offers.size())):
		selected_offers.append(offers[index])
	return selected_offers
