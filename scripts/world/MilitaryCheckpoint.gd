@tool
extends Node2D

enum StopDirection { ENTRY, EXIT, BOTH }

## Положение на линии дороги от From Node (0) к To Node (1).
@export_range(0, 1, 0.001) var road_position := 0.5:
	set(value):
		road_position = clampf(value, 0.0, 1.0)
		_align_marker()
## Стрелка в редакторе показывает въезд. Разверните её, если въезд ведёт к From Node.
@export var reverse_entry := false:
	set(value):
		reverse_entry = value
		_align_marker()
@export_enum("Только въезд", "Только выезд", "В обе стороны") var stop_direction: int = StopDirection.ENTRY
@export_range(0, 100, 1, "suffix:%") var inspection_chance := 20
@export var inspection_event: Dictionary
@export var clearance_event: Dictionary
## Назначьте только посту первого грузового рейса.
@export var tutorial_checkpoint := false

func _enter_tree() -> void:
	var road := get_parent()
	if road.has_signal("geometry_changed"):
		road.connect("geometry_changed", _align_marker)
	_align_marker()

func _exit_tree() -> void:
	var road := get_parent()
	if road.has_signal("geometry_changed") and road.is_connected("geometry_changed", _align_marker):
		road.disconnect("geometry_changed", _align_marker)

func _align_marker() -> void:
	if not is_inside_tree() or not get_parent().has_method("path_points"):
		return
	var points: Array[Vector2] = get_parent().path_points()
	if points.size() < 2:
		return
	var offset := road_position * (points.size() - 1)
	var index := mini(floori(offset), points.size() - 2)
	position = points[index].lerp(points[index + 1], offset - index)
	var arrow := get_node_or_null("EntryArrow") as Node2D
	if arrow != null:
		arrow.visible = Engine.is_editor_hint()
		arrow.rotation = (points[index + 1] - points[index]).angle() + (PI if reverse_entry else 0.0)

func stops_for(entering: bool) -> bool:
	return stop_direction == StopDirection.BOTH or (stop_direction == StopDirection.ENTRY) == entering

func roll_event() -> Dictionary:
	return inspection_event if randi_range(1, 100) <= inspection_chance else clearance_event
