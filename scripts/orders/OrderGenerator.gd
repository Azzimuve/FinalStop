extends RefCounted

const ItemCatalog = preload("res://scripts/simulation/ItemCatalog.gd")

const DeliveryOrder = preload("res://scripts/orders/DeliveryOrder.gd")
const CargoItem = preload("res://scripts/simulation/CargoItem.gd")
const RoutePlanner = preload("res://scripts/map/RoutePlanner.gd")
const WorldMapData = preload("res://scripts/WorldMapData.gd")
const GameClock = preload("res://scripts/simulation/GameClock.gd")
const TravelRules = preload("res://scripts/simulation/TravelRules.gd")

const DEADLINE_BUFFER_MINUTES: float = 300.0
const CARD_COUNT: int = 3
const REFRESH_MINUTES: float = 360.0

var settings: GameBalanceSettings
var available_offers: Array[DeliveryOrder] = []
var next_refresh_minutes: float = -1.0


func refresh_offers(routes: RoutePlanner, current_minutes: float) -> bool:
	if next_refresh_minutes >= 0.0 and current_minutes < next_refresh_minutes:
		return false
	var refresh_time := current_minutes
	if next_refresh_minutes >= 0.0:
		refresh_time = next_refresh_minutes + floorf((current_minutes - next_refresh_minutes) / REFRESH_MINUTES) * REFRESH_MINUTES
	available_offers = generate(routes, refresh_time)
	next_refresh_minutes = refresh_time + REFRESH_MINUTES
	return true


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
			for item_id in ["test_crate", "test_box", "test_long_cargo", "test_small_item"]:
				var item := ItemCatalog.create(item_id)
				if item != null:
					order.cargo.append(item)
			if order.cargo.size() != 4:
				continue
			order.is_urgent = randf() < clampf(settings.urgent_order_chance_percent / 100.0, 0.0, 1.0)
			order.title = ("Срочная доставка: %s" if order.is_urgent else "Доставка груза: %s") % destination_place["name"]
			order.pickup_city_id = company_city["id"]
			order.pickup_city_name = company_city["name"]
			order.pickup_location_id = pickup["id"]
			order.pickup_name = pickup["name"]
			order.delivery_city_id = destination_city["id"]
			order.delivery_city_name = destination_city["name"]
			order.delivery_location_id = destination_place["id"]
			order.delivery_name = destination_place["name"]
			order.distance_km = distance * TravelRules.DISTANCE_KM_PER_UNIT
			var reward_multiplier := 1.0
			var buffer_minutes := DEADLINE_BUFFER_MINUTES
			if order.is_urgent:
				reward_multiplier += maxf(0.0, settings.urgent_order_reward_bonus_percent) / 100.0
				buffer_minutes *= 1.0 - clampf(settings.urgent_order_buffer_reduction_percent / 100.0, 0.0, 1.0)
			order.reward = roundi(distance / 100.0 * settings.order_payment_per_100_distance_units * reward_multiplier)
			order.deadline_total_minutes = current_minutes + estimated_minutes + buffer_minutes
			offers.append(order)

	offers.shuffle()
	var selected_offers: Array[DeliveryOrder] = []
	for index in range(mini(CARD_COUNT, offers.size())):
		selected_offers.append(offers[index])
	return selected_offers
