@tool
extends Control

@export var overlay_only: bool = false
@export var grid_color := Color(0.32, 0.30, 0.22, 0.28)
func _draw() -> void:
	if not overlay_only:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.75, 0.67, 0.51, 0.45))
		draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0), Color(0.33, 0.30, 0.24), false, 2.0)
	else:
		draw_line(Vector2(size.x / 2.0, 2), Vector2(size.x / 2.0, size.y - 2), grid_color, 1.0)
		draw_line(Vector2(2, size.y / 2.0), Vector2(size.x - 2, size.y / 2.0), grid_color, 1.0)
