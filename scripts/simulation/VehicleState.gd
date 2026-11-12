extends RefCounted

const TravelRules = preload("res://scripts/simulation/TravelRules.gd")
const VehicleInventory = preload("res://scripts/simulation/VehicleInventory.gd")

var inventory := VehicleInventory.new()

var fuel_liters: float
const VehiclePart = preload("res://scripts/simulation/VehiclePart.gd")

# ID обозначает место установки, а не модель установленной детали.
const PART_NAMES := {
	"front_left_wheel": "Переднее левое колесо",
	"front_right_wheel": "Переднее правое колесо",
	"rear_left_wheel": "Заднее левое колесо",
	"rear_right_wheel": "Заднее правое колесо",
	"engine": "Двигатель",
	"transmission": "Трансмиссия",
}

const PART_SLOT_SIZES := {
	"front_left_wheel": Vector2i(2, 2),
	"front_right_wheel": Vector2i(2, 2),
	"rear_left_wheel": Vector2i(2, 2),
	"rear_right_wheel": Vector2i(2, 2),
	"engine": Vector2i(2, 3),
	"transmission": Vector2i(2, 3),
}

var _parts: Dictionary = {}
var condition_percent: float:
	get:
		var total := 0.0
		for part_id in PART_NAMES:
			if get_part(part_id) != null:
				total += get_part(part_id).condition_percent
		return total / PART_NAMES.size()
var settings: GameBalanceSettings


func _init(balance_settings: GameBalanceSettings) -> void:
	settings = balance_settings
	fuel_liters = settings.fuel_tank_capacity_liters
	for part_id in PART_NAMES:
		_parts[part_id] = VehiclePart.new("Стандартная", {}, PART_SLOT_SIZES[part_id])
		get_part(part_id).slot_type = slot_type(part_id)
		get_part(part_id).title = PART_NAMES[part_id]


func affordable_refuel_liters(credits: float) -> float:
	var missing_liters := maxf(0.0, settings.fuel_tank_capacity_liters - fuel_liters)
	return minf(missing_liters, credits / settings.fuel_price_per_liter_credits)


func consume_distance(distance_units: float) -> float:
	# Возвращаем реально пройденное расстояние, ограниченное запасом топлива.
	if distance_units <= 0.0:
		return 0.0
	var liters_per_unit := settings.fuel_consumption_liters_per_100_units / 100.0
	var actual_distance := distance_units
	if distance_units * liters_per_unit >= fuel_liters:
		actual_distance = fuel_liters / liters_per_unit
		fuel_liters = 0.0
	else:
		fuel_liters = maxf(0.0, fuel_liters - distance_units * liters_per_unit)
	var distance_km := actual_distance * TravelRules.DISTANCE_KM_PER_UNIT
	var condition_loss := distance_km / 10.0 * settings.vehicle_condition_loss_percent_per_10_km
	for part_id in PART_NAMES:
		if get_part(part_id) != null:
			get_part(part_id).wear(condition_loss)
	return actual_distance


func get_part(part_id: String) -> VehiclePart:
	return _parts.get(part_id)


func repair_part(part_id: String) -> bool:
	var part := get_part(part_id)
	if part == null:
		return false
	part.repair()
	return true


func replace_part(part_id: String, replacement: VehiclePart) -> bool:
	if not PART_NAMES.has(part_id) or replacement == null:
		return false
	if replacement.size != PART_SLOT_SIZES[part_id]:
		return false
	if replacement.slot_type != slot_type(part_id):
		return false
	# Каждая установленная деталь имеет независимое состояние.
	for installed in _parts.values():
		if installed == replacement:
			return false
	_parts[part_id] = replacement
	return true


func repair_all() -> void:
	for part_id in PART_NAMES:
		repair_part(part_id)


static func slot_type(part_id: String) -> String:
	return "wheel" if part_id.ends_with("wheel") else part_id


func parts_snapshot() -> Dictionary:
	return _parts.duplicate()


func restore_parts(snapshot: Dictionary) -> void:
	_parts = snapshot.duplicate()


func remove_part(part_id: String) -> void:
	_parts.erase(part_id)


func is_complete() -> bool:
	for part_id in PART_NAMES:
		if get_part(part_id) == null:
			return false
	return true


func duration_for_distance(distance: float) -> float:
	var engine := get_part("engine")
	var multiplier := float(engine.parameters.get("speed_multiplier", 1.0)) if engine != null else 1.0
	return maxf(0.5, distance / (TravelRules.DISTANCE_UNITS_PER_SECOND * multiplier))
