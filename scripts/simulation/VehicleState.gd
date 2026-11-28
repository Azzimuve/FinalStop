extends Node2D


const TravelRules = preload("res://scripts/simulation/TravelRules.gd")
const VehicleInventory = preload("res://scripts/simulation/VehicleInventory.gd")

enum DriveMode { ECONOMY, NORMAL, FORCED }

@export var drive_mode: DriveMode = DriveMode.NORMAL
var inventory: VehicleInventory
const PASSENGER_CAPACITY: int = 2
signal passengers_changed
var passenger_portraits: Array[Texture2D] = []
var passenger_count: int:
	get:
		return passenger_portraits.size()

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
@export_group("Автомобиль")
@export var settings: GameBalanceSettings
@export_range(0.0, 1.0) var initial_fuel_fraction: float = 1.0
@export var inventory_dimensions := Vector2i(6, 12)
@export_range(0.01, 1000.0) var base_speed: float = TravelRules.DISTANCE_UNITS_PER_SECOND
@export var installed_parts: Array[VehiclePart] = []


func _ready() -> void:
	inventory = VehicleInventory.new(Vector2i(maxi(1, inventory_dimensions.x), maxi(1, inventory_dimensions.y)))
	fuel_liters = settings.fuel_tank_capacity_liters * initial_fuel_fraction
	var index := 0
	for part_id in PART_NAMES:
		if index < installed_parts.size() and installed_parts[index] != null:
			var part := installed_parts[index].duplicate(true) as VehiclePart
			if part.slot_type == slot_type(part_id) and part.size == PART_SLOT_SIZES[part_id]:
				_parts[part_id] = part
		index += 1


func affordable_refuel_liters(credits: float, unit_price: float = settings.fuel_price_per_liter_credits) -> float:
	var missing_liters := maxf(0.0, settings.fuel_tank_capacity_liters - fuel_liters)
	if unit_price <= 0.0:
		return missing_liters if unit_price == 0.0 else 0.0
	return minf(missing_liters, maxf(credits, 0.0) / unit_price)


func free_passenger_seats() -> int:
	return PASSENGER_CAPACITY - passenger_count


func board_passengers(count: int, portrait: Texture2D = null) -> bool:
	if count <= 0 or count > free_passenger_seats():
		return false
	for i in count:
		passenger_portraits.append(portrait)
	passengers_changed.emit()
	return true


func disembark_passengers(count: int) -> bool:
	if count <= 0 or count > passenger_count:
		return false
	for i in count:
		passenger_portraits.pop_front()
	passengers_changed.emit()
	return true


func consume_distance(distance_units: float) -> float:
	# Возвращаем реально пройденное расстояние, ограниченное запасом топлива.
	if distance_units <= 0.0:
		return 0.0
	var liters_per_unit := settings.fuel_consumption_liters_per_100_units / 100.0 * overload_fuel_multiplier() * drive_fuel_multiplier()
	var actual_distance := distance_units
	if distance_units * liters_per_unit >= fuel_liters:
		actual_distance = fuel_liters / liters_per_unit
		fuel_liters = 0.0
	else:
		fuel_liters = maxf(0.0, fuel_liters - distance_units * liters_per_unit)
	var distance_km := actual_distance * TravelRules.DISTANCE_KM_PER_UNIT
	for part_id in PART_NAMES:
		if get_part(part_id) != null:
			var service_distance := settings.service_distance_km(slot_type(part_id))
			if service_distance > 0.0:
				var loss := distance_km / service_distance * (100.0 - settings.vehicle_service_condition_percent)
				get_part(part_id).wear(loss * overload_wear_multiplier() * drive_wear_multiplier())
	return actual_distance


func get_part(part_id: String) -> VehiclePart:
	return _parts.get(part_id)


func repair_cost(part_id: String) -> float:
	var part := get_part(part_id)
	if part == null:
		return 0.0
	return settings.full_repair_cost(slot_type(part_id)) * (100.0 - part.condition_percent) / 100.0


func repair_time_minutes(part_id: String) -> float:
	var part := get_part(part_id)
	if part == null:
		return 0.0
	return settings.full_repair_time(slot_type(part_id)) * (100.0 - part.condition_percent) / 100.0


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
	return maxf(0.5, distance / (base_speed * multiplier))


func overload_ratio() -> float:
	return maxf(0.0, inventory.total_weight_kg() / maxf(settings.cargo_capacity_kg, 1.0) - 1.0)


func overload_speed_multiplier() -> float:
	var loss := overload_ratio() / 0.1 * maxf(0.0, settings.overload_speed_loss_percent_per_10_percent)
	return 1.0 - minf(loss, clampf(settings.overload_max_speed_loss_percent, 0.0, 99.0)) / 100.0


func overload_fuel_multiplier() -> float:
	return 1.0 + overload_ratio() / 0.1 * maxf(0.0, settings.overload_fuel_increase_percent_per_10_percent) / 100.0


func overload_wear_multiplier() -> float:
	return 1.0 + overload_ratio() / 0.1 * maxf(0.0, settings.overload_wear_increase_percent_per_10_percent) / 100.0


func drive_speed_multiplier() -> float:
	match drive_mode:
		DriveMode.ECONOMY: return maxf(0.01, settings.economy_speed_multiplier)
		DriveMode.FORCED: return maxf(0.01, settings.forced_speed_multiplier)
	return 1.0


func drive_fuel_multiplier() -> float:
	match drive_mode:
		DriveMode.ECONOMY: return maxf(0.01, settings.economy_fuel_multiplier)
		DriveMode.FORCED: return maxf(0.01, settings.forced_fuel_multiplier)
	return 1.0


func drive_wear_multiplier() -> float:
	match drive_mode:
		DriveMode.ECONOMY: return maxf(0.0, settings.economy_wear_multiplier)
		DriveMode.FORCED: return maxf(0.0, settings.forced_wear_multiplier)
	return 1.0
