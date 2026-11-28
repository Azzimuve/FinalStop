@tool
extends Node2D

const MapPoint = preload("res://scripts/world/MapPoint.gd")
const MapPlace = preload("res://scripts/world/MapPlace.gd")
const MapRoad = preload("res://scripts/world/MapRoad.gd")
@export var city_id: String = "":
	set(value):
		city_id = value
		_queue_editor_update()
@export var display_name: String = "Город":
	set(value):
		display_name = value
		_last_detail = -1.0
		_queue_editor_update()
@export_enum("city", "settlement") var city_type: String = "city"
@export_node_path("Node2D") var entry_node: NodePath:
	set(value):
		entry_node = value
		_queue_editor_update()
@onready var authored_layout_scale: Vector2 = $Layout.scale
@onready var authored_caption_position: Vector2 = $DetailCaption.position

var _editor_update_pending := false
var _watched_nodes: Array[Node] = []
var _last_detail := -1.0
var _last_current := false
var _last_selected_place := ""
var editor_preview := false
var _editor_compact := false

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		get_tree().tree_changed.connect(_queue_editor_update)

func _ready() -> void:
	_queue_editor_update()

func _exit_tree() -> void:
	if get_tree().tree_changed.is_connected(_queue_editor_update):
		get_tree().tree_changed.disconnect(_queue_editor_update)
	_disconnect_watched_nodes()

func _disconnect_watched_nodes() -> void:
	for node in _watched_nodes:
		if is_instance_valid(node) and node.is_connected("configuration_changed", _queue_editor_update):
			node.disconnect("configuration_changed", _queue_editor_update)
	_watched_nodes.clear()

func _queue_editor_update() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree() or _editor_update_pending:
		return
	_editor_update_pending = true
	_update_editor_view.call_deferred()

func _update_editor_view() -> void:
	_editor_update_pending = false
	if not is_inside_tree() or not is_node_ready() or editor_preview:
		return
	_disconnect_watched_nodes()
	for container_path in ["Layout/Points", "Layout/Places"]:
		for node in get_node(container_path).get_children():
			if node.has_signal("configuration_changed"):
				node.connect("configuration_changed", _queue_editor_update)
				_watched_nodes.append(node)
	$Marker.modulate.a = 0.0
	$Caption.modulate.a = 0.0
	$Caption.text = display_name
	$DetailCaption.text = display_name
	set_editor_compact(_editor_compact)
	update_configuration_warnings()

# Скрываем только отрисовку: исходные трансформации и visible не меняются
# и в сцену не попадает состояние предпросмотра.
func set_editor_compact(compact: bool) -> void:
	_editor_compact = compact
	if not Engine.is_editor_hint() or not is_node_ready() or editor_preview:
		return
	for path in ["Layout/Roads", "Layout/Places", "Layout/Points", "DetailCaption"]:
		var item := get_node(path) as CanvasItem
		RenderingServer.canvas_item_set_visible(item.get_canvas_item(), item.visible and not compact)
	for path in ["Marker", "Caption"]:
		var item := get_node(path) as CanvasItem
		RenderingServer.canvas_item_set_modulate(item.get_canvas_item(), Color(1, 1, 1, 1 if compact else 0))

func get_entrance_points() -> Array[MapPoint]:
	var points: Array[MapPoint] = []
	var entry := get_node_or_null(entry_node) as MapPoint
	if entry != null and is_ancestor_of(entry):
		points.append(entry)
	for point in $Layout/Points.get_children():
		if point is MapPoint and point.city_entrance and not points.has(point):
			points.append(point)
	# Ранее подключённые дороги тоже обозначают въезды, без миграции сцен.
	var world := get_parent().get_parent() if get_parent() != null else null
	if world != null and world.has_node("Roads"):
		for road in world.get_node("Roads").get_children():
			if road is MapRoad:
				for point in road.endpoints():
					if point is MapPoint and is_ancestor_of(point) and not points.has(point):
						points.append(point)
	return points

func get_data(reference: Node2D) -> Dictionary:
	var data := {"id": city_id, "name": display_name, "type": city_type, "marker": $Marker,
		"position": position, "entry_location_id": "", "entrances": {},
		"street_nodes": [], "street_roads": [], "places": []}
	var entry := get_node_or_null(entry_node) as MapPoint
	if entry != null:
		data.entry_location_id = entry.point_id
	for point in $Layout/Points.get_children():
		if point is MapPoint:
			data.street_nodes.append({"id": point.point_id, "position": reference.to_local(point.global_position) - reference.to_local(global_position)})
	for road in $Layout/Roads.get_children():
		if road is MapRoad:
			var ends: Array[Node2D] = road.endpoints()
			if ends[0] is MapPoint and ends[1] is MapPoint:
				data.street_roads.append({"from": ends[0].point_id, "to": ends[1].point_id,
					"scene": road, "points": road.path_points(reference), "checkpoints": road.checkpoints()})
	for place in $Layout/Places.get_children():
		if place is MapPlace:
			var point := place.get_node_or_null(place.road_node) as MapPoint
			if point != null:
				data.places.append({"id": place.place_id, "name": place.display_name, "marker": place.get_node("Marker"),
					"type": place.gameplay_type(), "position": reference.to_local(place.global_position) - reference.to_local(global_position),
					"road_node_id": point.point_id})
	return data

func set_view(detail: float, current: bool, selected_place: String) -> void:
	if detail == _last_detail and current == _last_current and selected_place == _last_selected_place:
		return
	_last_detail = detail
	_last_current = current
	_last_selected_place = selected_place
	$Layout.scale = authored_layout_scale * maxf(detail, 0.00001)
	$Layout.visible = detail > 0.0
	$Marker.modulate.a = 1.0 - smoothstep(0.0, 0.3, detail)
	$Marker.color = Color("#bf713b") if current else Color("#79795d")
	$Caption.text = display_name
	$Caption.modulate.a = $Marker.modulate.a
	var opacity := smoothstep(0.55, 0.95, detail)
	$DetailCaption.text = display_name + ("" if current else " — просмотр")
	$DetailCaption.position = authored_caption_position * detail
	$DetailCaption.modulate.a = opacity
	for place in $Layout/Places.get_children():
		if place is MapPlace:
			place.set_view(place.place_id == selected_place, current, opacity)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if city_id.is_empty():
		warnings.append("Укажите уникальный ID города.")
	var entry := get_node_or_null(entry_node) as MapPoint
	if entry == null or not is_ancestor_of(entry):
		warnings.append("В Entry Node выберите дорожную точку внутри этого города (Layout/Points).")
	var ids: Dictionary = {}
	for container_path in ["Layout/Points", "Layout/Places"]:
		var container := get_node_or_null(container_path)
		if container == null:
			continue
		for child in container.get_children():
			var id := ""
			if child is MapPoint:
				id = child.point_id
			elif child is MapPlace:
				id = child.place_id
			if not id.is_empty():
				if ids.has(id):
					warnings.append("Повторяющийся ID в городе: " + id)
				ids[id] = true
	return warnings
