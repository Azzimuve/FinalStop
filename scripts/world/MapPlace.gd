@tool
extends Node2D

signal map_transform_changed
signal configuration_changed

const MapPoint = preload("res://scripts/world/MapPoint.gd")
var editor_preview := false
var _editor_update_pending := false

# Стабильные значения сохраняются в сценах. Назначение точки выбирается
# одним полем; мастерская является отдельным типом, а не флагом гаража.
const OBJECT_TYPES := {
	0: "", 1: "store", 2: "workshop", 3: "fuel_station", 4: "warehouse",
	5: "company_office", 6: "garage", 7: "stop", 8: "delivery_point", 9: "hotel",
}

@export var place_id: String = "":
	set(value):
		place_id = value
		_update_editor_view()
		configuration_changed.emit()
@export var display_name: String = "Точка интереса":
	set(value):
		display_name = value
		_update_editor_view()
@export_enum("Не задано:0", "Магазин:1", "Мастерская:2", "Заправка:3", "Склад:4", "Офис компании:5", "Гараж:6", "Автостанция:7", "Пункт доставки:8", "Отель:9") var object_type: int = 0
@export_node_path("Node2D") var road_node: NodePath:
	set(value):
		road_node = value
		# Переносим только при назначении в редакторе: загрузка сцены
		# должна сохранять размещение, заданное автором.
		if Engine.is_editor_hint() and is_inside_tree():
			if not road_node.is_empty():
				var point := get_node_or_null(road_node) as MapPoint
				if is_instance_valid(point):
					global_position = point.global_position
			update_configuration_warnings()
@export var marker_color := Color("#777a52"):
	set(value):
		marker_color = value
		_update_editor_view()

func _enter_tree() -> void:
	set_notify_transform(true)
	if Engine.is_editor_hint() and not get_tree().tree_changed.is_connected(_queue_editor_update):
		get_tree().tree_changed.connect(_queue_editor_update)

func _exit_tree() -> void:
	if get_tree().tree_changed.is_connected(_queue_editor_update):
		get_tree().tree_changed.disconnect(_queue_editor_update)

func _ready() -> void:
	_update_editor_view()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		map_transform_changed.emit()

func gameplay_type() -> String:
	return OBJECT_TYPES.get(object_type, "")

func _queue_editor_update() -> void:
	if not Engine.is_editor_hint() or editor_preview or _editor_update_pending or not is_inside_tree():
		return
	_editor_update_pending = true
	_update_editor_view.call_deferred()

func _update_editor_view() -> void:
	_editor_update_pending = false
	if Engine.is_editor_hint() and not editor_preview and is_node_ready() and is_inside_tree():
		$Caption.text = display_name
		$Marker.color = marker_color
		update_configuration_warnings()

func set_view(selected: bool, interactive: bool, opacity: float) -> void:
	$Caption.text = display_name
	$Marker.color = Color("#c5733a") if selected else (marker_color if interactive else Color("#79795d"))
	$Marker.scale = Vector2.ONE * (10.0 / 7.0 if selected else 1.0)
	modulate.a = opacity

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if place_id.is_empty():
		warnings.append("Укажите уникальный ID точки интереса.")
	if road_node.is_empty() or not get_node_or_null(road_node) is MapPoint:
		warnings.append("Выберите дорожную точку RoadPoint в Road Node.")
	return warnings
