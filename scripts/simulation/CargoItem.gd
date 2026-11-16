extends RefCounted

var item_id: String
var description: String = ""
var category: String = ""
var texture_path: String = ""
var properties: Dictionary = {}
var has_uses: bool = false
var title: String
var size: Vector2i
# Отрицательная цена означает, что предмет не участвует в торговле.
var price_credits: float = -1.0
var uses_remaining: int = 1
# Отрицательный вес означает, что данные ещё не заданы. Ноль — известный вес.
var weight_kg: float = -1.0


func _init(item_title: String, item_size: Vector2i, price: float = -1.0) -> void:
	title = item_title
	size = item_size
	price_credits = price


func can_use() -> bool:
	return has_uses and uses_remaining > 0 and (properties.has("fatigue_restore") or properties.has("satiety_restore") or properties.has("water_restore"))


func effects_text() -> String:
	var lines := PackedStringArray()
	if properties.has("fatigue_restore"):
		lines.append("Восстанавливает %s энергии" % str(properties.fatigue_restore))
	if properties.has("satiety_restore"):
		lines.append("Восстанавливает %s сытости" % str(properties.satiety_restore))
	if properties.has("water_restore"):
		lines.append("Восстанавливает %s запаса воды" % str(properties.water_restore))
	if properties.has("speed_bonus_percent"):
		lines.append("Скорость +%s%% (при установке)" % str(properties.speed_bonus_percent))
	return "\n".join(lines)
