extends HBoxContainer

const VehicleState = preload("res://scripts/simulation/VehicleState.gd")
var vehicle: VehicleState

func show_vehicle(model: VehicleState) -> void:
	if vehicle != model:
		if vehicle != null:
			vehicle.passengers_changed.disconnect(_refresh)
		vehicle = model
		if vehicle != null:
			vehicle.passengers_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	$Passenger1/Occupant.visible = vehicle != null and vehicle.passenger_count >= 1
	$Passenger2/Occupant.visible = vehicle != null and vehicle.passenger_count >= 2
