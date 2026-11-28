extends Control

const DeliveryOrder = preload("res://scripts/orders/DeliveryOrder.gd")
const GameClock = preload("res://scripts/simulation/GameClock.gd")

var order: DeliveryOrder

func fill(model: DeliveryOrder, clock: GameClock) -> void:
	order = model
	var passenger := order.is_passenger_order()
	%Office.text = order.pickup_city_name
	%Number.text = "№ %03d" % order.dispatch_number
	%Heading.text = "Пассажирская ведомость" if passenger else "Транспортная накладная"
	%Route.text = "%s → %s" % [order.pickup_city_name, order.delivery_city_name]
	if order.pickup_city_id == order.delivery_city_id:
		%Route.text = "%s → %s" % [order.pickup_name, order.delivery_name]
	accessibility_name = "%s · %s · %s" % [%Heading.text, %Number.text, %Route.text]
	%From.text = "%s · %s" % [order.pickup_city_name, order.pickup_name]
	%To.text = "%s · %s" % [order.delivery_city_name, order.delivery_name]
	%LoadTitle.text = "Пассажиры" if passenger else "Груз"
	if passenger:
		%Load.text = order.passenger_name if not order.passenger_name.is_empty() else "По посадочной ведомости"
		%Quantity.text = "%d чел." % order.passenger_count
	else:
		%Load.text = order.cargo_text()
		%Quantity.text = "%d шт." % order.cargo.size()
	%Deadline.text = ("Срочно · " if order.is_urgent else "") + clock.format_deadline(order.deadline_total_minutes)
	%Distance.text = "%.1f км" % order.distance_km
	%Reward.text = "%d кр." % order.reward
	%Fee.text = %Reward.text
	%Details.scroll_vertical = 0

func set_filed(filed: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if filed else Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_ALL if filed else Control.FOCUS_NONE
	%Details.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED if filed else Control.MOUSE_BEHAVIOR_INHERITED
	if filed:
		%Details.scroll_vertical = 0
