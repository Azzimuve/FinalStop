extends HBoxContainer

const VehicleState = preload("res://scripts/simulation/VehicleState.gd")
var vehicle: VehicleState

func show_vehicle(model: VehicleState) -> void:
	if vehicle != model:
		if is_instance_valid(vehicle):
			vehicle.passengers_changed.disconnect(_refresh)
		vehicle = model
		if vehicle != null:
			vehicle.passengers_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	var occupants: Array[TextureRect] = [$Passenger1/Occupant, $Passenger2/Occupant]
	for i in occupants.size():
		occupants[i].visible = is_instance_valid(vehicle) and i < vehicle.passenger_count
		if occupants[i].visible:
			var portrait := vehicle.passenger_portraits[i]
			occupants[i].texture = portrait if portrait != null else preload("res://resources/atlas/driver.webp")
