extends RefCounted

const CargoItem = preload("res://scripts/simulation/CargoItem.gd")
const VehiclePart = preload("res://scripts/simulation/VehiclePart.gd")
const PATH := "res://resources/items.json"
static var definitions: Dictionary = {}
static var loaded: bool = false


static func create(id: String) -> CargoItem:
	if not loaded:
		_load_catalog()
	if not definitions.has(id):
		push_error("Unknown item ID: " + id)
		return null
	var data: Dictionary = definitions[id]
	var dimensions := Vector2i(int(data.width), int(data.height))
	var item: CargoItem
	if data.has("slot_type"):
		var part := VehiclePart.new(data.get("model", data.name), {}, dimensions)
		part.slot_type = data.slot_type
		part.parameters["speed_multiplier"] = 1.0 + float(data.properties.get("speed_bonus_percent", 0.0)) / 100.0
		item = part
	else:
		item = CargoItem.new(data.name, dimensions)
	item.item_id = id
	item.title = data.name
	item.description = data.description
	item.category = data.category
	item.texture_path = data.texture_path
	item.weight_kg = -1.0 if data.weight_kg == null else float(data.weight_kg)
	item.price_credits = -1.0 if data.price == null else float(data.price)
	item.has_uses = data.quantity != null
	item.uses_remaining = int(data.quantity) if item.has_uses else 1
	item.properties = data.properties.duplicate(true)
	return item


static func _load_catalog() -> void:
	loaded = true
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(PATH)) != OK or not json.data is Dictionary:
		push_error("Item catalog JSON: " + json.get_error_message())
		return
	if not json.data.get("items") is Array:
		push_error("Item catalog must contain an items array")
		return
	for data in json.data.items:
		if not _valid(data):
			push_error("Invalid item definition: " + str(data))
			continue
		if definitions.has(data.id):
			push_error("Duplicate item ID: " + data.id)
			continue
		definitions[data.id] = data


static func _valid(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for key in ["id", "name", "description", "category", "texture_path"]:
		if not data.get(key) is String:
			return false
	if data.id.is_empty() or data.name.is_empty():
		return false
	for key in ["width", "height"]:
		if not _number(data.get(key)) or data[key] < 1 or float(data[key]) != floorf(data[key]):
			return false
	for key in ["weight_kg", "price", "quantity"]:
		if not data.has(key):
			return false
		if data[key] != null and (not _number(data[key]) or data[key] < 0):
			return false
	if data.quantity != null and (data.quantity < 1 or float(data.quantity) != floorf(data.quantity)):
		return false
	if not data.get("properties") is Dictionary:
		return false
	for key in data.properties:
		if key not in ["fatigue_restore", "satiety_restore", "water_restore", "speed_bonus_percent"]:
			return false
		if not _number(data.properties[key]) or data.properties[key] < 0:
			return false
	if data.has("slot_type") and data.slot_type not in ["wheel", "engine", "transmission"]:
		return false
	if data.has("model") and not data.model is String:
		return false
	if data.properties.has("speed_bonus_percent") and data.get("slot_type", "") != "engine":
		return false
	for key in ["fatigue_restore", "satiety_restore", "water_restore"]:
		if data.properties.has(key) and data.quantity == null:
			return false
	return true


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
