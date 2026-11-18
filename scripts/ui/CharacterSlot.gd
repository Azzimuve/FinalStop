@tool
extends Control

@export var overlay_only: bool = false
@export var grid_color := Color(0.4, 0.52, 0.52)
func _draw() -> void:
	if not overlay_only:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.14, 0.15))
		draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0), Color(0.65, 0.78, 0.76), false, 2.0)
	else:
		draw_line(Vector2(size.x / 2.0, 2), Vector2(size.x / 2.0, size.y - 2), grid_color, 1.0)
		draw_line(Vector2(2, size.y / 2.0), Vector2(size.x - 2, size.y / 2.0), grid_color, 1.0)
