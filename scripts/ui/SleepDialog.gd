extends "res://scripts/ui/QuantityDialog.gd"

const GameClock = preload("res://scripts/simulation/GameClock.gd")

signal sleep_requested(hours: float, at_hotel: bool)

@onready var hours_input: HSlider = $Body/Content/Slider
@onready var duration: Label = $Body/Content/Selection
@onready var hotel_terms: Label = $Body/Content/Details
var sleeping_at_hotel: bool = false
var clock: GameClock


func _ready() -> void:
	super()
	confirmed.connect(_request_sleep)
	hours_input.value_changed.connect(_update_duration)


func open(at_hotel: bool, hotel_cost: float, hotel_restore_per_hour: float, game_clock: GameClock) -> void:
	clock = game_clock
	sleeping_at_hotel = at_hotel
	$Body/Illustration.texture = preload("res://resources/atlas/rest.webp") if at_hotel else preload("res://resources/atlas/ural_side.webp")
	title = "Сон в отеле" if at_hotel else "Сон на стоянке"
	if at_hotel:
		hotel_terms.text = "%.0f кр. за весь отдых · +%.0f бодрости в час" % [hotel_cost, hotel_restore_per_hour]
	else:
		hotel_terms.text = "Отдых на стоянке бесплатный"
	hours_input.set_value_no_signal(hours_input.min_value)
	_update_duration(hours_input.value)
	open_slider()


func _update_duration(hours: float) -> void:
	duration.text = "Сон на %d ч. · Подъём в %s" % [int(hours), clock.format_deadline(clock.total_minutes + hours * 60.0)]


func _request_sleep() -> void:
	sleep_requested.emit(hours_input.value, sleeping_at_hotel)
