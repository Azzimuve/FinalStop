extends PanelContainer
const DeliveryOrder = preload("res://scripts/orders/DeliveryOrder.gd")
const GameClock = preload("res://scripts/simulation/GameClock.gd")
signal selected(order: DeliveryOrder)
var order: DeliveryOrder
func _ready() -> void:
	$Content/Choose.pressed.connect(func(): selected.emit(order))
func show_order(model: DeliveryOrder, clock: GameClock) -> void:
	order = model
	var heading := "Пассажиры" if order.is_passenger_order() else "Доставка"
	if order.is_urgent:
		heading = "Срочно · " + heading
	$Content/Heading.text = "%s · %d кр." % [heading, order.reward]
	$Content/Details/Cities.text = "%s → %s" % [order.pickup_city_name, order.delivery_city_name]
	$Content/Details/Places.text = "От: %s\nДо: %s" % [order.pickup_name, order.delivery_name]
	$Content/Details/Deadline.text = "До %s · %.1f км" % [clock.format_deadline(order.deadline_total_minutes), order.distance_km]
	if order.is_passenger_order():
		$Content/Details/Load.text = "Пассажиров: %d\nТребуется мест: %d" % [order.passenger_count, order.passenger_count]
	else:
		var lines := PackedStringArray()
		for item in order.cargo:
			var title := item.title.trim_prefix("Тестовый ").trim_prefix("Тестовая ")
			lines.append("%s %d×%d" % [title, item.size.x, item.size.y])
		$Content/Details/Load.text = "Груз:\n" + "\n".join(lines)
