extends Node

signal changed

@export_range(1, 1440, 1, "suffix:мин") var interval_minutes := 180
@export_range(0, 100, 1, "suffix:%") var chance_percent := 30
@export_range(1, 1440, 1, "suffix:мин") var lifetime_minutes := 180

var roads: Array[Dictionary] = []
var events: Array[Dictionary] = []
var road: Dictionary = {}
var event: Dictionary = {}
var expires_at := 0.0
var next_check := -1.0


func configure(highways: Array[Dictionary], definitions: Array[Dictionary]) -> void:
	for highway in highways:
		if not str(highway.get("radio_name", "")).is_empty() and highway.points.size() >= 2:
			roads.append(highway)
	for definition in definitions:
		if not str(definition.get("radio_message", "")).is_empty():
			events.append(definition)


func update_at(now: float) -> void:
	if next_check < 0.0:
		next_check = now + interval_minutes
	var previous_expiry := expires_at
	# После сна обрабатываем пропущенные интервалы и объявляем только ещё актуальную сводку.
	while next_check <= now:
		if next_check >= expires_at and not roads.is_empty() and not events.is_empty() and randf() * 100.0 < chance_percent:
			road = roads.pick_random()
			event = events.pick_random()
			expires_at = next_check + lifetime_minutes
		next_check += interval_minutes
	if not event.is_empty() and now >= expires_at:
		clear()
	elif previous_expiry != expires_at:
		changed.emit()


func clear() -> void:
	event = {}
	road = {}
	expires_at = 0.0
	changed.emit()
