extends RefCounted

const WorldMapData = preload("res://scripts/WorldMapData.gd")
const RouteGeometry = preload("res://scripts/map/RouteGeometry.gd")

var cities: Array[Dictionary] = WorldMapData.get_cities()
var cities_by_id: Dictionary = {}
var road_junctions: Array[Dictionary] = WorldMapData.get_road_junctions()
var road_junctions_by_id: Dictionary = {}
var roads: Array[Dictionary] = WorldMapData.get_roads()
# Геометрия карты неизменна в течение сессии; поиск улиц выполняется один раз
# для каждой пары узлов. Выдаём копии, чтобы очистка маршрута не меняла кеш.
var local_route_cache: Dictionary = {}


func _init() -> void:
	for city in cities:
		cities_by_id[city["id"]] = city
	for junction in road_junctions:
		road_junctions_by_id[junction["id"]] = junction


func entrance_for(city_id: String, neighbor_id: String) -> String:
	return cities_by_id[city_id]["entrances"][neighbor_id]


func arrival_location(start_city_id: String, destination_city_id: String) -> String:
	var path := find_route(start_city_id, destination_city_id)
	if path.size() < 2:
		return cities_by_id[destination_city_id]["entry_location_id"]
	return entrance_for(destination_city_id, path[-2])


func road_endpoint(node_id: String, neighbor_id: String) -> Vector2:
	if cities_by_id.has(node_id):
		return position_for_location(cities_by_id[node_id], entrance_for(node_id, neighbor_id))
	return world_position_for_node(node_id)


func build_intercity_route(start_city_id: String, start_location_id: String, destination_city_id: String) -> Array[Vector2]:
	var path := find_route(start_city_id, destination_city_id)
	var points: Array[Vector2] = []
	if path.size() < 2:
		return points
	var city: Dictionary = cities_by_id[start_city_id]
	points.append(position_for_location(city, start_location_id))
	points.append_array(build_local_route(city, start_location_id, entrance_for(start_city_id, path[1])))
	for index in range(path.size() - 1):
		var departure := road_endpoint(path[index], path[index + 1])
		if points[-1].distance_to(departure) > 0.01:
			points.append(departure)
		points.append(road_endpoint(path[index + 1], path[index]))
		if index + 2 < path.size() and cities_by_id.has(path[index + 1]):
			var through_city: Dictionary = cities_by_id[path[index + 1]]
			points.append_array(build_local_route(through_city, entrance_for(path[index + 1], path[index]), entrance_for(path[index + 1], path[index + 2])))
	return points


func get_route_distance(start_city_id: String, start_location_id: String, destination_city_id: String, destination_location_id: String) -> float:
	if start_city_id == destination_city_id:
		return _distance_between_locations(start_city_id, start_location_id, destination_city_id, destination_location_id)
	var points := build_intercity_route(start_city_id, start_location_id, destination_city_id)
	if points.is_empty():
		return 0.0
	return RouteGeometry.length(points) + _distance_between_locations(destination_city_id, arrival_location(start_city_id, destination_city_id), destination_city_id, destination_location_id)


func build_local_route(city: Dictionary, start_location_id: String, destination_place_id: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var start_node_id := node_id_for_location(city, start_location_id)
	var destination_node_id := node_id_for_location(city, destination_place_id)
	if start_node_id.is_empty() or destination_node_id.is_empty() or start_node_id == destination_node_id:
		return result
	var cache_key := "%s/%s/%s" % [city["id"], start_node_id, destination_node_id]
	if local_route_cache.has(cache_key):
		result.assign(local_route_cache[cache_key])
		return result

	var node_ids := _find_node_path(city["street_roads"], start_node_id, destination_node_id)
	var origin: Vector2 = city["position"]
	for node_id in node_ids:
		result.append(origin + street_node_position(city, node_id))
	local_route_cache[cache_key] = result.duplicate()
	return result


func _distance_between_locations(start_city_id: String, start_location_id: String, destination_city_id: String, destination_location_id: String) -> float:
	if start_city_id != destination_city_id:
		return 0.0
	var city: Dictionary = cities_by_id[start_city_id]
	var route_start := start_location_id
	if route_start.is_empty():
		route_start = city["entry_location_id"]
	var route_end := destination_location_id
	if route_end.is_empty():
		route_end = city["entry_location_id"]
	return RouteGeometry.length(build_local_route(city, route_start, route_end))


func node_id_for_location(city: Dictionary, location_id: String) -> String:
	for node in city["street_nodes"]:
		if node["id"] == location_id:
			return location_id
	for place in city["places"]:
		if place["id"] == location_id:
			return place["road_node_id"]
	return ""


func street_node_position(city: Dictionary, node_id: String) -> Vector2:
	for node in city["street_nodes"]:
		if node["id"] == node_id:
			return node["position"]
	return Vector2.ZERO


func position_for_location(city: Dictionary, location_id: String) -> Vector2:
	var node_id := node_id_for_location(city, location_id)
	return city["position"] + street_node_position(city, node_id)


func find_route(start_city_id: String, destination_city_id: String) -> Array[String]:
	if not cities_by_id.has(start_city_id) or not cities_by_id.has(destination_city_id):
		return []
	return _find_node_path(roads, start_city_id, destination_city_id)


func _find_node_path(edges: Array, start_id: String, destination_id: String) -> Array[String]:
	# Поиск в ширину: сохраняем выбор пути по числу участков, как в прототипе.
	var result: Array[String] = []
	var queue: Array[String] = [start_id]
	var previous: Dictionary = {start_id: ""}
	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		if current_id == destination_id:
			break
		for road in edges:
			var next_id := ""
			if road["from"] == current_id:
				next_id = road["to"]
			elif road["to"] == current_id:
				next_id = road["from"]
			if not next_id.is_empty() and not previous.has(next_id):
				previous[next_id] = current_id
				queue.append(next_id)

	if not previous.has(destination_id):
		return result

	var cursor := destination_id
	while not cursor.is_empty():
		result.push_front(cursor)
		cursor = previous[cursor]
	return result


func world_position_for_node(node_id: String) -> Vector2:
	if cities_by_id.has(node_id):
		return cities_by_id[node_id]["position"]
	if road_junctions_by_id.has(node_id):
		return road_junctions_by_id[node_id]["position"]
	push_warning("Unknown world road node: %s" % node_id)
	return WorldMapData.WORLD_CENTER
