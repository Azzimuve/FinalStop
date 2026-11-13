extends Resource
class_name GameBalanceSettings

# Фактические игровые значения хранятся в resources/GameBalanceSettings.tres.
# Значения ниже служат начальными при создании нового ресурса.

@export_group("Потребности персонажа")
@export var needs_max_value: float = 100.0
@export var satiety_loss_per_hour: float = 4.0
@export var water_loss_per_hour: float = 6.0
@export var needs_sleep_loss_multiplier: float = 0.5
@export var needs_low_threshold: float = 30.0
@export var needs_critical_threshold: float = 10.0
@export var satiety_low_fatigue_penalty: float = 0.15
@export var satiety_critical_fatigue_penalty: float = 0.3
@export var satiety_empty_fatigue_penalty: float = 0.5
@export var water_low_fatigue_penalty: float = 0.25
@export var water_critical_fatigue_penalty: float = 0.5
@export var water_empty_fatigue_penalty: float = 1.0
@export var hotel_meal_cost_credits: float = 50.0
@export var hotel_meal_time_minutes: float = 30.0
@export var food_restore_amount: float = 40.0
@export var water_restore_amount: float = 50.0

@export_group("Топливо")
@export var fuel_tank_capacity_liters: float = 60.0
@export var fuel_consumption_liters_per_100_units: float = 0.5
@export var fuel_price_per_liter_credits: float = 15.0
@export var refuel_time_game_minutes: float = 5.0

@export_group("Режимы движения")
@export_range(0.01, 5.0) var economy_speed_multiplier: float = 0.8
@export_range(0.01, 5.0) var economy_fuel_multiplier: float = 0.8
@export_range(0.0, 5.0) var economy_wear_multiplier: float = 0.8
@export_range(0.01, 5.0) var forced_speed_multiplier: float = 1.2
@export_range(0.01, 5.0) var forced_fuel_multiplier: float = 1.3
@export_range(0.0, 5.0) var forced_wear_multiplier: float = 1.3

@export_group("Груз и перегруз")
@export_range(1.0, 100000.0) var cargo_capacity_kg: float = 4000.0
# Изменения за каждые 10% перегруза, применяются пропорционально.
@export_range(0.0, 100.0) var overload_speed_loss_percent_per_10_percent: float = 5.0
@export_range(0.0, 1000.0) var overload_fuel_increase_percent_per_10_percent: float = 10.0
@export_range(0.0, 1000.0) var overload_wear_increase_percent_per_10_percent: float = 10.0
@export_range(0.0, 99.0) var overload_max_speed_loss_percent: float = 80.0

@export_group("Выплаты за заказы")
@export var order_payment_per_100_distance_units: float = 50.0
@export_group("Срочные заказы")
@export_range(0.0, 100.0) var urgent_order_chance_percent: float = 30.0
@export_range(0.0, 100.0) var urgent_order_buffer_reduction_percent: float = 70.0
@export_range(0.0, 1000.0) var urgent_order_reward_bonus_percent: float = 30.0

@export_group("Ремонт автомобиля")
# Пробег от 100% до порога обслуживания, а не до полного износа.
@export_range(0.0, 99.0) var vehicle_service_condition_percent: float = 30.0
@export var wheel_service_distance_km: float = 1500.0
@export var engine_service_distance_km: float = 2500.0
@export var transmission_service_distance_km: float = 3000.0
@export var wheel_full_repair_cost_credits: float = 80.0
@export var engine_full_repair_cost_credits: float = 300.0
@export var transmission_full_repair_cost_credits: float = 240.0
@export var wheel_full_repair_time_minutes: float = 30.0
@export var engine_full_repair_time_minutes: float = 180.0
@export var transmission_full_repair_time_minutes: float = 120.0


@export_group("Проверка автомобиля")
@export var vehicle_inspection_cost_credits: float = 50.0

@export_group("Торговля и улучшения")
@export var workshop_upgrade_cost_credits: float = 400.0
@export var upgraded_engine_price_credits: float = 600.0
@export var upgraded_engine_speed_multiplier: float = 1.2
@export var trader_buyback_multiplier: float = 0.5


func service_distance_km(part_type: String) -> float:
	match part_type:
		"wheel": return wheel_service_distance_km
		"engine": return engine_service_distance_km
		"transmission": return transmission_service_distance_km
	return 0.0


func full_repair_cost(part_type: String) -> float:
	match part_type:
		"wheel": return wheel_full_repair_cost_credits
		"engine": return engine_full_repair_cost_credits
		"transmission": return transmission_full_repair_cost_credits
	return 0.0


func full_repair_time(part_type: String) -> float:
	match part_type:
		"wheel": return wheel_full_repair_time_minutes
		"engine": return engine_full_repair_time_minutes
		"transmission": return transmission_full_repair_time_minutes
	return 0.0
