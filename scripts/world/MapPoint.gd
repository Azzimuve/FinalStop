@tool
extends Node2D

signal map_transform_changed
signal configuration_changed

@export var point_id: String = "":
	set(value):
		if point_id == value:
			return
		point_id = value
		update_configuration_warnings()
		configuration_changed.emit()
@export var junction: bool = false:
	set(value):
		junction = value
		queue_redraw()
		configuration_changed.emit()
## Дополнительный въезд, доступный для соединения с трассой в World.
@export var city_entrance: bool = false:
	set(value):
		city_entrance = value
		queue_redraw()
		configuration_changed.emit()
@export var entrance_name: String = "":
	set(value):
		entrance_name = value
		configuration_changed.emit()

# Только временная копия для предпросмотра редактора.
var editor_preview := false

func _enter_tree() -> void:
	set_notify_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		map_transform_changed.emit()

func _draw() -> void:
	if junction:
		draw_circle(Vector2.ZERO, 8.0, Color(0.20, 0.28, 0.29))
		draw_circle(Vector2.ZERO, 3.0, Color(0.055, 0.078, 0.086))
	elif Engine.is_editor_hint() and not editor_preview:
		draw_circle(Vector2.ZERO, 3.0, Color(0.3, 0.86, 0.76))

func _get_configuration_warnings() -> PackedStringArray:
	return ["Укажите уникальный ID узла дороги."] if point_id.is_empty() else []
