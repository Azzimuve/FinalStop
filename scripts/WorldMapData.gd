extends Node2D

const MapCity = preload("res://scripts/world/MapCity.gd")
const MapPoint = preload("res://scripts/world/MapPoint.gd")
const MapRoad = preload("res://scripts/world/MapRoad.gd")
@export var start_city_id: String = "company_city"
@export var start_location_id: String = "company_start"
@export var world_center := Vector2(640, 360)
var _road_geometry: Dictionary = {}
var _displayed_points: Dictionary = {}
var _geometry_reference: Node2D
var _display_geometry_dirty := true
var _last_detail := -1.0
var _last_current_city := ""
var _last_selected_place := ""

# Снимок графа берётся из сохранённых узлов. Геометрия здесь не создаётся.
func read_graph() -> Dictionary:
	var reference: Node2D = get_parent() as Node2D if get_parent() is Node2D else self
	_geometry_reference = reference
	for road: MapRoad in _road_geometry:
		if is_instance_valid(road) and road.geometry_changed.is_connected(_invalidate_display_geometry):
			road.geometry_changed.disconnect(_invalidate_display_geometry)
	_road_geometry.clear()
	_displayed_points.clear()
	_display_geometry_dirty = true
	_last_detail = -1.0
	var data := {"cities": [], "junctions": [], "roads": []}
	var by_id: Dictionary = {}
	for city in $Cities.get_children():
		if city is MapCity:
			var entry: Dictionary = city.get_data(reference)
			entry.position = reference.to_local(city.global_position)
			data.cities.append(entry)
			by_id[city.city_id] = entry
			for road in city.get_node("Layout/Roads").get_children():
				if road is MapRoad:
					_road_geometry[road] = road.path_points(reference)
	for point in $Junctions.get_children():
		if point is MapPoint:
			data.junctions.append({"id": point.point_id, "position": reference.to_local(point.global_position)})
	for road in $Roads.get_children():
		if not road is MapRoad:
			continue
		var ends: Array[Node2D] = road.endpoints()
		if not ends[0] is MapPoint or not ends[1] is MapPoint:
			push_error("У дороги %s не выбраны узлы." % road.name)
			continue
		var ids: Array[String] = []
		for point in ends:
			var city := _city_of(point)
			ids.append(city.city_id if city != null else point.point_id)
		var points: Array[Vector2] = road.path_points(reference)
		data.roads.append({"from": ids[0], "to": ids[1], "from_point": ends[0].point_id, "to_point": ends[1].point_id,
			"scene": road, "points": points, "checkpoints": road.checkpoints(),
			"id": String(road.name), "radio_name": road.radio_name.strip_edges()})
		_road_geometry[road] = points
		for index in range(2):
			if by_id.has(ids[index]):
				by_id[ids[index]].entrances[ids[1 - index]] = ends[index].point_id
	for road: MapRoad in _road_geometry:
		road.geometry_changed.connect(_invalidate_display_geometry)
	return data

func _city_of(node: Node) -> MapCity:
	var parent := node.get_parent()
	while parent != null and parent != self:
		if parent is MapCity:
			return parent
		parent = parent.get_parent()
	return null

func set_view(detail: float, current_city: String, selected_place: String) -> void:
	var detail_changed := detail != _last_detail
	if detail_changed or current_city != _last_current_city or selected_place != _last_selected_place:
		for city in $Cities.get_children():
			if city is MapCity:
				city.set_view(detail, city.city_id == current_city, selected_place)
		_last_current_city = current_city
		_last_selected_place = selected_place
	if detail_changed:
		for road in $Roads.get_children():
			if road is MapRoad:
				road.detail = detail
		_last_detail = detail
		_display_geometry_dirty = true
	if not _display_geometry_dirty:
		return
	_displayed_points.clear()
	for road: MapRoad in _road_geometry:
		if not is_instance_valid(road) or not road.is_inside_tree():
			continue
		var original: Array[Vector2] = _road_geometry[road]
		var displayed := road.path_points(_geometry_reference)
		for index in range(mini(original.size(), displayed.size())):
			_displayed_points[original[index]] = displayed[index]
	_display_geometry_dirty = false

func _invalidate_display_geometry() -> void:
	_display_geometry_dirty = true

func display_route_point(point: Vector2) -> Vector2:
	return _displayed_points.get(point, point)
