extends RefCounted

# Согласованные временные параметры прототипа.
const DISTANCE_UNITS_PER_SECOND: float = 84.0
const DISTANCE_KM_PER_UNIT: float = 0.03


static func duration_for_distance(distance: float) -> float:
	return maxf(0.5, distance / DISTANCE_UNITS_PER_SECOND)
