extends RefCounted

const VehicleState = preload("res://scripts/simulation/VehicleState.gd")

# Один участок поездки: между городами или по улицам города.
var active: bool = false
var elapsed_seconds: float = 0.0
var duration_seconds: float = 1.0
var distance_units: float = 0.0
var progress: float = 0.0
var road_offsets := PackedFloat64Array()
var pace_offsets := PackedFloat64Array()


func start(distance: float, duration: float, road := PackedFloat64Array(), pace := PackedFloat64Array()) -> void:
	active = true
	elapsed_seconds = 0.0
	progress = 0.0
	distance_units = distance
	duration_seconds = duration
	road_offsets = road
	pace_offsets = pace


func advance(delta: float, vehicle: VehicleState, speed_multiplier: float = 1.0, distance_limit: float = INF) -> float:
	# elapsed_seconds хранит эффективное время прохождения маршрута.
	# delta остаётся реальным временем: штраф скорости увеличивает длительность
	# поездки, но не замедляет игровые часы.
	speed_multiplier *= vehicle.overload_speed_multiplier() * vehicle.drive_speed_multiplier()
	var effective_delta := delta * maxf(speed_multiplier, 0.01)
	var proposed_elapsed := minf(elapsed_seconds + effective_delta, duration_seconds)
	var proposed_progress := proposed_elapsed / duration_seconds
	if not pace_offsets.is_empty():
		proposed_progress = _convert_distance(proposed_progress * pace_offsets[-1], pace_offsets, road_offsets) / distance_units
	if distance_units > 0.0:
		proposed_progress = minf(proposed_progress, progress + maxf(0.0, distance_limit) / distance_units)
	var distance_delta := maxf(0.0, proposed_progress - progress) * distance_units
	var actual_distance := vehicle.consume_distance(distance_delta)
	if actual_distance < distance_delta:
		progress = minf(proposed_progress, progress + actual_distance / maxf(distance_units, 0.001))
	else:
		progress = proposed_progress
	var previous_elapsed := elapsed_seconds
	if pace_offsets.is_empty():
		elapsed_seconds = progress * duration_seconds
	else:
		elapsed_seconds = _convert_distance(progress * distance_units, road_offsets, pace_offsets) / pace_offsets[-1] * duration_seconds
	return (elapsed_seconds - previous_elapsed) / maxf(speed_multiplier, 0.01)


func _convert_distance(distance: float, source: PackedFloat64Array, target: PackedFloat64Array) -> float:
	if distance >= source[-1]:
		return target[-1]
	var i := clampi(source.bsearch(distance), 1, source.size() - 1)
	return remap(distance, source[i - 1], source[i], target[i - 1], target[i])
