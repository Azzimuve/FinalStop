extends RefCounted

var settings: GameBalanceSettings
var satiety: float
var water: float


func _init(balance: GameBalanceSettings) -> void:
	settings = balance
	refill()


func refill() -> void:
	satiety = settings.needs_max_value
	water = settings.needs_max_value


# Возвращает эквивалент минут расхода бодрости с учётом переходов порогов.
func advance(minutes: float, sleeping: bool = false) -> float:
	var hours := maxf(0.0, minutes) / 60.0
	var factor := maxf(0.0, settings.needs_sleep_loss_multiplier) if sleeping else 1.0
	var food_rate := maxf(0.0, settings.satiety_loss_per_hour) * factor
	var water_rate := maxf(0.0, settings.water_loss_per_hour) * factor
	var fatigue_hours := hours
	if not sleeping:
		fatigue_hours += _penalty_hours(satiety, food_rate, hours, settings.satiety_low_fatigue_penalty, settings.satiety_critical_fatigue_penalty, settings.satiety_empty_fatigue_penalty)
		fatigue_hours += _penalty_hours(water, water_rate, hours, settings.water_low_fatigue_penalty, settings.water_critical_fatigue_penalty, settings.water_empty_fatigue_penalty)
	satiety = maxf(0.0, satiety - hours * food_rate)
	water = maxf(0.0, water - hours * water_rate)
	return 0.0 if sleeping else fatigue_hours * 60.0


func _penalty_hours(value: float, rate: float, hours: float, low: float, critical: float, empty: float) -> float:
	return (
		_time_below(value, rate, hours, settings.needs_low_threshold) * low
		+ _time_below(value, rate, hours, settings.needs_critical_threshold) * (critical - low)
		+ _time_below(value, rate, hours, 0.0) * (empty - critical)
	)


func _time_below(value: float, rate: float, hours: float, threshold: float) -> float:
	if rate <= 0.0:
		return hours if value < threshold or (threshold == 0.0 and value == 0.0) else 0.0
	return clampf(hours - maxf(0.0, value - threshold) / rate, 0.0, hours)
