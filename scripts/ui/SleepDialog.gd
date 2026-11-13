extends AcceptDialog

signal sleep_requested(hours: float, at_hotel: bool)

var hours_input: SpinBox
var sleeping_at_hotel: bool = false


func _ready() -> void:
	title = "Сон"
	dialog_text = "Сколько часов проспать?"
	ok_button_text = "Спать"
	hours_input = SpinBox.new()
	hours_input.min_value = 1.0
	hours_input.max_value = 12.0
	hours_input.step = 1.0
	hours_input.value = 1.0
	add_child(hours_input)
	confirmed.connect(_request_sleep)


func open(at_hotel: bool, hotel_cost: float, hotel_restore_per_hour: float) -> void:
	sleeping_at_hotel = at_hotel
	title = "Сон в отеле" if at_hotel else "Сон"
	dialog_text = (
		"Сколько часов проспать? %.0f кр. за весь сон, +%.0f ед. за час."
		% [hotel_cost, hotel_restore_per_hour]
		if at_hotel else "Сколько часов проспать?"
	)
	hours_input.value = 1.0
	popup_centered()


func _request_sleep() -> void:
	sleep_requested.emit(clampf(hours_input.value, 1.0, 12.0), sleeping_at_hotel)
