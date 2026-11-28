extends RefCounted

const RouteGeometry = preload("res://scripts/map/RouteGeometry.gd")

var cities: Array[Dictionary] = []
var cities_by_id: Dictionary = {}
var road_junctions: Array[Dictionary] = []
var road_junctions_by_id: Dictionary = {}
var roads: Array[Dictionary] = []
var road_stops: Dictionary = {}
var midpoint_segments: Dictionary = {}
var _roads_with_stops: Array[Dictionary] = []
# Геометрия карты неизменна в течение сессии; поиск улиц выполняется один раз
# для каждой пары узлов. Выдаём копии, чтобы очистка маршрута не меняла кеш.
var local_route_cache: Dictionary = {}


func configure(graph: Dictionary) -> void:
	cities.assign(graph.cities)
	road_junctions.assign(graph.junctions)
	roads.assign(graph.roads)
	cities_by_id.clear()
	road_junctions_by_id.clear()
	local_route_cache.clear()
	for city in cities:
		cities_by_id[city["id"]] = city
	for junction in road_junctions:
		road_junctions_by_id[junction["id"]] = junction
	road_stops.clear()
	midpoint_segments.clear()
	_roads_with_stops.assign(roads)
	for road in roads:
		if not str(road.get("radio_name", "")).is_empty():
			_add_road_stop(road)


static func road_stop_id(road: Dictionary) -> String:
	return "road_stop/" + str(road.id)


func _add_road_stop(road: Dictionary) -> void:
	var points: Array[Vector2] = road.points
	var halfway := RouteGeometry.length(points) * 0.5
	if halfway <= 0.0:
		return
	var remaining := halfway
	for i in range(1, points.size()):
		var length := points[i - 1].distance_to(points[i])
		if remaining > length or length == 0.0:
			remaining -= length
			continue
		var weight := remaining / length
		var middle := points[i - 1].lerp(points[i], weight)
		var id := road_stop_id(road)
		road_stops[id] = {"position": middle, "road": road}
		midpoint_segments[middle] = {"a": points[i - 1], "b": points[i], "weight": weight}
		# Две половины нужны только при выборе остановки. Обычные рейсы используют целые дороги.
		var first := points.slice(0, i)
		_append_unique(first, [middle])
		var second: Array[Vector2] = [middle]
		_append_unique(second, points.slice(i))
		var posts: Array[Dictionary] = []
		_edge_points([road], road.from, road.to, [], posts)
		var left := {"from": road.from, "to": id, "points": first, "id": road.id, "crossings": []}
		var right := {"from": id, "to": road.to, "points": second, "id": road.id, "crossings": []}
		for stop in posts:
			if stop.distance <= halfway:
				left.crossings.append(stop)
			if stop.distance >= halfway:
				right.crossings.append({"post": stop.post, "distance": stop.distance - halfway})
		_roads_with_stops.append(left)
		_roads_with_stops.append(right)
		break


func entrance_for(city_id: String, neighbor_id: String) -> String:
	if road_stops.has(neighbor_id):
		var road: Dictionary = road_stops[neighbor_id].road
		neighbor_id = road.to if road.from == city_id else road.from
	return cities_by_id[city_id]["entrances"][neighbor_id]


func arrival_location(start_city_id: String, destination_city_id: String) -> String:
	if road_stops.has(destination_city_id):
		return destination_city_id
	var path := find_route(start_city_id, destination_city_id)
	if path.size() < 2:
		return cities_by_id[destination_city_id]["entry_location_id"]
	return entrance_for(destination_city_id, path[-2])


func road_endpoint(node_id: String, neighbor_id: String) -> Vector2:
	if cities_by_id.has(node_id):
		return position_for_location(cities_by_id[node_id], entrance_for(node_id, neighbor_id))
	return world_position_for_node(node_id)


func build_intercity_route(start_city_id: String, start_location_id: String, destination_city_id: String, crossings: Array[Dictionary] = [], record_highway: Callable = Callable()) -> Array[Vector2]:
	var path := find_route(start_city_id, destination_city_id)
	var points: Array[Vector2] = []
	if path.size() < 2:
		return points
	if road_stops.has(start_city_id):
		points.append(world_position_for_node(start_city_id))
	else:
		var city: Dictionary = cities_by_id[start_city_id]
		points.append(position_for_location(city, start_location_id))
		_append_city_section(points, crossings, city, start_location_id, entrance_for(start_city_id, path[1]))
	for index in range(path.size() - 1):
		var departure := road_endpoint(path[index], path[index + 1])
		if points[-1].distance_to(departure) > 0.01:
			points.append(departure)
		var section := _edge_points(_roads_with_stops, path[index], path[index + 1], points, crossings, record_highway)
		if section.is_empty():
			section.append(road_endpoint(path[index + 1], path[index]))
		_append_unique(points, section)
		if index + 2 < path.size() and cities_by_id.has(path[index + 1]):
			var through_city: Dictionary = cities_by_id[path[index + 1]]
			_append_city_section(points, crossings, through_city, entrance_for(path[index + 1], path[index]), entrance_for(path[index + 1], path[index + 2]))
	return points


func _append_city_section(points: Array[Vector2], crossings: Array[Dictionary], city: Dictionary, start: String, finish: String) -> void:
	var local_stops: Array[Dictionary] = []
	var section := build_local_route(city, start, finish, local_stops)
	if not local_stops.is_empty():
		var offset := RouteGeometry.length(points)
		for stop in local_stops:
			crossings.append({"post": stop.post, "forward": stop.forward, "distance": offset + stop.distance})
	points.append_array(section)


func get_route_distance(start_city_id: String, start_location_id: String, destination_city_id: String, destination_location_id: String) -> float:
	if start_city_id == destination_city_id:
		return _distance_between_locations(start_city_id, start_location_id, destination_city_id, destination_location_id)
	var points := build_intercity_route(start_city_id, start_location_id, destination_city_id)
	if points.is_empty():
		return 0.0
	return RouteGeometry.length(points) + _distance_between_locations(destination_city_id, arrival_location(start_city_id, destination_city_id), destination_city_id, destination_location_id)


func build_local_route(city: Dictionary, start_location_id: String, destination_place_id: String, crossings: Array[Dictionary] = []) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var start_node_id := node_id_for_location(city, start_location_id)
	var destination_node_id := node_id_for_location(city, destination_place_id)
	if start_node_id.is_empty() or destination_node_id.is_empty() or start_node_id == destination_node_id:
		return result
	var cache_key := "%s/%s/%s" % [city["id"], start_node_id, destination_node_id]
	if local_route_cache.has(cache_key):
		result.assign(local_route_cache[cache_key].points)
		crossings.append_array(local_route_cache[cache_key].crossings)
		return result

	var stops: Array[Dictionary] = []
	var node_ids := _find_node_path(city["street_roads"], start_node_id, destination_node_id)
	for index in range(node_ids.size() - 1):
		var section := _edge_points(city["street_roads"], node_ids[index], node_ids[index + 1], result, stops)
		if section.is_empty():
			section.assign([city["position"] + street_node_position(city, node_ids[index]),
				city["position"] + street_node_position(city, node_ids[index + 1])])
		_append_unique(result, section)
	local_route_cache[cache_key] = {"points": result.duplicate(), "crossings": stops}
	crossings.append_array(stops)
	return result


func _edge_points(edges: Array, from_id: String, to_id: String, prefix: Array[Vector2], crossings: Array[Dictionary], record_highway: Callable = Callable()) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for edge: Dictionary in edges:
		var forward: bool = edge.from == from_id and edge.to == to_id
		if not forward and not (edge.to == from_id and edge.from == to_id):
			continue
		points.assign(edge.get("points", []))
		if not forward:
			points.reverse()
		if edge.has("crossings"):
			var start := RouteGeometry.length(prefix)
			var length := RouteGeometry.length(points)
			if record_highway.is_valid():
				record_highway.call(edge.id, start if road_stops.has(from_id) else start + length)
			for stop in edge.crossings:
				crossings.append({"post": stop.post, "forward": forward,
					"distance": start + (stop.distance if forward else length - stop.distance)})
			break
		if record_highway.is_valid() and points.size() >= 2 and not str(edge.get("radio_name", "")).is_empty():
			record_highway.call(edge.id, RouteGeometry.length(prefix) + 0.5 * RouteGeometry.length(points))
		var posts: Array = edge.get("checkpoints", [])
		if points.size() >= 2 and not posts.is_empty():
			var offset := RouteGeometry.length(prefix)
			for post in posts:
				var fraction: float = post.road_position if forward else 1.0 - post.road_position
				var sample := fraction * (points.size() - 1)
				var segment := mini(floori(sample), points.size() - 2)
				var distance := offset + RouteGeometry.length(points.slice(0, segment + 1))
				distance += points[segment].distance_to(points[segment + 1]) * (sample - segment)
				crossings.append({"post": post, "forward": forward, "distance": distance})
		break
	return points


func _append_unique(target: Array[Vector2], points: Array[Vector2]) -> void:
	for point in points:
		if target.is_empty() or not target[-1].is_equal_approx(point):
			target.append(point)


func _distance_between_locations(start_city_id: String, start_location_id: String, destination_city_id: String, destination_location_id: String) -> float:
	if start_city_id != destination_city_id or not cities_by_id.has(start_city_id):
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
	if road_stops.has(start_city_id) or road_stops.has(destination_city_id):
		return _find_node_path(_roads_with_stops, start_city_id, destination_city_id)
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
	if road_stops.has(node_id):
		return road_stops[node_id].position
	if cities_by_id.has(node_id):
		return cities_by_id[node_id]["position"]
	if road_junctions_by_id.has(node_id):
		return road_junctions_by_id[node_id]["position"]
	push_warning("Unknown world road node: %s" % node_id)
	return Vector2.ZERO
