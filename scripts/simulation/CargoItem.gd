extends RefCounted

var title: String
var size: Vector2i
# Отрицательная цена означает, что предмет не участвует в торговле.
var price_credits: float = -1.0
var uses_remaining: int = 1


func _init(item_title: String, item_size: Vector2i, price: float = -1.0) -> void:
	title = item_title
	size = item_size
	price_credits = price
