extends "res://scripts/tests/CustomRouteTest.gd"

const DeliveryOrder = preload("res://scripts/orders/DeliveryOrder.gd")

func _ready() -> void:
	super()
	var order := DeliveryOrder.new()
	var desk = game.passenger_desk
	order.pickup_city_id = start_city
	order.pickup_city_name = game.current_city_name
	order.pickup_location_id = start_place
	order.pickup_name = "Автостанция"
	order.delivery_city_id = "northern_settlement"
	order.delivery_city_name = game.map_view.routes.cities_by_id[order.delivery_city_id].name
	order.delivery_location_id = "north_busstop"
	order.delivery_name = "Автостанция"
	order.title = "Пассажирский рейс"
	order.passenger_count = 2
	order.reward = 720
	order.deadline_total_minutes = game.clock.total_minutes + 360
	order.manifest.append(desk.tutorial_passenger)
	for profile in desk.applicants:
		if desk.wanted.has(profile.booked_number):
			order.manifest.append(profile)
			break
	game._on_order_selected(order)
	game._handle_trip_arrival()
	game._on_accept_pressed()
