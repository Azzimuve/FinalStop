extends Resource
class_name GameBalanceSettings

# Фактические игровые значения хранятся в resources/GameBalanceSettings.tres.
# Значения ниже служат начальными при создании нового ресурса.

@export_group("Топливо")
@export var fuel_tank_capacity_liters: float = 60.0
@export var fuel_consumption_liters_per_100_units: float = 0.5
@export var fuel_price_per_liter_credits: float = 15.0
@export var refuel_time_game_minutes: float = 5.0

@export_group("Выплаты за заказы")
@export var order_payment_per_100_distance_units: float = 50.0

@export_group("Ремонт автомобиля")
@export var vehicle_repair_cost_credits: float = 100.0
@export var vehicle_repair_time_game_minutes: float = 60.0
@export var vehicle_condition_loss_percent_per_10_km: float = 1.0

@export_group("Проверка автомобиля")
@export var vehicle_inspection_cost_credits: float = 50.0

@export_group("Торговля и улучшения")
@export var workshop_upgrade_cost_credits: float = 400.0
@export var upgraded_engine_price_credits: float = 600.0
@export var upgraded_engine_speed_multiplier: float = 1.2
@export var trader_buyback_multiplier: float = 0.5
