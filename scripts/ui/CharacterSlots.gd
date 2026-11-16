extends Control

const CELL: float = 28.0
const SLOT_SIZE: float = CELL * 2.0
const GAP: float = 8.0


func _ready() -> void:
	custom_minimum_size = Vector2(SLOT_SIZE * 3.0 + GAP * 2.0, SLOT_SIZE)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	for index in range(3):
		var origin := Vector2(index * (SLOT_SIZE + GAP), 0)
		# Рамка и фон целиком внутри элемента, без обрезаемой обводки.
		draw_rect(Rect2(origin, Vector2.ONE * SLOT_SIZE), Color(0.65, 0.78, 0.76))
		draw_rect(Rect2(origin + Vector2.ONE * 2.0, Vector2.ONE * (SLOT_SIZE - 4.0)), Color(0.10, 0.14, 0.15))
		if index == 0:
			# Игрок — часть отображения, не предмет, который можно перенести.
			draw_rect(Rect2(origin + Vector2.ONE * 2.0, Vector2.ONE * (SLOT_SIZE - 4.0)), Color(0.3, 0.65, 0.55))
		var grid_color := Color(0.4, 0.52, 0.52)
		draw_line(origin + Vector2(CELL, 2), origin + Vector2(CELL, SLOT_SIZE - 2), grid_color, 1.0)
		draw_line(origin + Vector2(2, CELL), origin + Vector2(SLOT_SIZE - 2, CELL), grid_color, 1.0)
