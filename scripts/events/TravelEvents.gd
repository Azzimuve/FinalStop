extends RefCounted

const DATA_PATH := "res://resources/travel_events.json"
var events: Array[Dictionary] = []
var interval_km: float = 10.0
var cooldown_km: float = 15.0
var base_chance: float = 20.0
var chance_step: float = 20.0
var chance: float = 20.0
var distance_to_check: float = 10.0
var active_event: Dictionary = {}
var resolved: bool = false


func load_data() -> void:
	events.clear()
	active_event = {}
	resolved = false
	var parser := JSON.new()
	var error := parser.parse(FileAccess.get_file_as_string(DATA_PATH))
	if error != OK or not parser.data is Dictionary:
		push_error("Travel events JSON: %s (line %d)" % [parser.get_error_message(), parser.get_error_line()])
		return
	var data: Dictionary = parser.data
	if not data.get("settings", {}) is Dictionary or not data.get("events") is Array:
		push_error("Travel events: settings must be an object, events must be an array")
		return
	var config: Dictionary = data.get("settings", {})
	for key in ["check_interval_km", "cooldown_km", "base_chance_percent", "failure_increase_percent"]:
		if config.has(key) and not _number(config[key]):
			push_error("Travel events: invalid numeric setting " + key)
			return
	interval_km = float(config.get("check_interval_km", 10.0))
	cooldown_km = float(config.get("cooldown_km", 15.0))
	base_chance = float(config.get("base_chance_percent", 20.0))
	chance_step = float(config.get("failure_increase_percent", 20.0))
	if interval_km <= 0.0 or cooldown_km < 0.0 or base_chance <= 0.0 or base_chance > 100.0 or chance_step < 0.0:
		push_error("Travel events: invalid settings")
		return
	var ids: Array[String] = []
	for entry in data.get("events", []):
		if not _valid_event(entry) or ids.has(str(entry.get("id", ""))):
			push_error("Travel events: invalid or duplicate event: %s" % str(entry))
			continue
		ids.append(entry.id)
		events.append(entry)
	chance = base_chance
	distance_to_check = interval_km


func _valid_event(entry: Variant) -> bool:
	if not entry is Dictionary:
		return false
	if not _known_keys(entry, ["id", "title", "description", "weight", "actions"]):
		return false
	for key in ["id", "title", "description"]:
		if not entry.get(key) is String or str(entry[key]).is_empty():
			return false
	if not _number(entry.get("weight", 1.0)) or float(entry.get("weight", 1.0)) <= 0.0:
		return false
	if not entry.get("actions") is Array or entry.actions.is_empty():
		return false
	var has_free_action := false
	for action in entry.actions:
		if not action is Dictionary or not action.get("text") is String:
			return false
		if not _known_keys(action, ["text", "minutes", "fuel_cost", "money_cost", "outcomes"]):
			return false
		for key in ["minutes", "fuel_cost", "money_cost"]:
			if not _number(action.get(key, 0.0)) or float(action.get(key, 0.0)) < 0.0:
				return false
		if float(action.get("fuel_cost", 0.0)) == 0.0 and float(action.get("money_cost", 0.0)) == 0.0:
			has_free_action = true
		if not action.get("outcomes") is Array or action.outcomes.is_empty():
			return false
		for outcome in action.outcomes:
			if not outcome is Dictionary or not outcome.get("text") is String:
				return false
			if not _number(outcome.get("weight", 1.0)) or float(outcome.get("weight", 1.0)) <= 0.0:
				return false
			if not _known_keys(outcome, ["text", "weight", "money", "fuel", "fatigue_restore"]):
				return false
			for key in ["money", "fuel", "fatigue_restore"]:
				if not _number(outcome.get(key, 0.0)) or float(outcome.get(key, 0.0)) < 0.0:
					return false
	return has_free_action


func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


func distance_limit_km() -> float:
	return INF if events.is_empty() else maxf(0.0, distance_to_check)


func advance_distance(km: float) -> bool:
	if events.is_empty() or not active_event.is_empty():
		return false
	distance_to_check -= maxf(0.0, km)
	if distance_to_check > 0.000001:
		return false
	distance_to_check = interval_km
	if randf() * 100.0 >= chance:
		chance = minf(100.0, chance + chance_step)
		return false
	active_event = _weighted_pick(events)
	resolved = false
	chance = base_chance
	distance_to_check = cooldown_km + interval_km
	return true


func can_choose(index: int, money: float, fuel: float) -> bool:
	if active_event.is_empty() or resolved or index < 0 or index >= active_event.actions.size():
		return false
	var action: Dictionary = active_event.actions[index]
	return money >= float(action.get("money_cost", 0.0)) and fuel >= float(action.get("fuel_cost", 0.0))


func resolve(index: int) -> Dictionary:
	resolved = true
	return _weighted_pick(active_event.actions[index].outcomes)


func finish() -> void:
	active_event = {}
	resolved = false


func _weighted_pick(entries: Array) -> Dictionary:
	var total := 0.0
	for entry in entries:
		total += float(entry.get("weight", 1.0))
	var roll := randf() * total
	for entry in entries:
		roll -= float(entry.get("weight", 1.0))
		if roll < 0.0:
			return entry
	return entries.back()


func _known_keys(data: Dictionary, allowed: Array) -> bool:
	for key in data:
		if not allowed.has(key):
			return false
	return true
