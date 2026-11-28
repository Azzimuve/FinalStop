extends RefCounted

# Каждый якорь хранит индекс дороги и расстояние по её исходной кривой.
# Пересечение линий на экране не соединяет дороги без общего узла в сцене.
const EPS := 0.0001
const RoutePlanner = preload("res://scripts/map/RoutePlanner.gd")
const MapRoad = preload("res://scripts/world/MapRoad.gd")

class Road:
	var scene: MapRoad
	var points: Array[Vector2]
	var source_offsets := PackedFloat64Array()
	var offsets := PackedFloat64Array([0.0])
	var folded_points: Array[Vector2] = []
	var length := 0.0
	var knots := PackedFloat64Array()
	var pace := PackedFloat64Array([0.0])
	var start: int
	var finish: int
	var start_in_city: bool
	var finish_in_city: bool
	var city: String
	var highway: String
	var posts: Array[Dictionary] = []

	func sample(offset: float) -> int:
		return clampi(offsets.bsearch(offset) - 1, 0, points.size() - 2)

	func position_at(offset: float, display: Callable = Callable()) -> Vector2:
		var i := sample(offset)
		var a := points[i]
		var b := points[i + 1]
		if display.is_valid():
			a = display.call(a)
			b = display.call(b)
		if offset == offsets[i + 1]:
			return b
		return a.lerp(b, inverse_lerp(offsets[i], offsets[i + 1], offset))

	func folded_at(offset: float) -> Vector2:
		var i := sample(offset)
		return folded_points[i].lerp(folded_points[i + 1], inverse_lerp(offsets[i], offsets[i + 1], offset))

	func prepare_pace() -> void:
		var candidates := offsets.duplicate()
		# Собственный узел отличает параллельные дороги и отмечает середину для рации.
		candidates.append(length * 0.5)
		var start_span := 0.0
		var end_span := 0.0
		if city.is_empty():
			start_span = minf(length, points[0].distance_to(folded_points[0]))
			end_span = minf(length, points[-1].distance_to(folded_points[-1]))
			candidates.append_array(PackedFloat64Array([start_span * 0.5, start_span, length - end_span, length - end_span * 0.5]))
		candidates.sort()
		knots.append(0.0)
		for offset in candidates:
			var previous := knots[-1]
			if offset - previous <= EPS:
				continue
			var step := offset - previous
			if city.is_empty():
				var a := position_at(previous)
				var b := position_at(offset)
				var fa := folded_at(previous)
				var fb := folded_at(offset)
				step = maxf(step, fa.distance_to(fb))
				step = maxf(step, exit_length(a, b, fa, fb, previous, offset, start_span))
				step = maxf(step, exit_length(a, b, fa, fb, length - previous, length - offset, end_span))
			knots.append(offset)
			pace.append(pace[-1] + step)

	func pace_at(offset: float) -> float:
		var i := clampi(knots.bsearch(offset), 1, knots.size() - 1)
		return remap(offset, knots[i - 1], knots[i], pace[i - 1], pace[i])

	# Оцениваем также выезд из раскрытого города на уже свёрнутую карту.
	# Масштаб перехода задаёт реальное смещение въезда в сцене.
	func exit_length(a: Vector2, b: Vector2, folded_a: Vector2, folded_b: Vector2, from: float, to: float, span: float) -> float:
		if span <= EPS:
			return 0.0
		var start_pos := a.lerp(folded_a, clampf(from / span, 0.0, 1.0))
		var end_pos := b.lerp(folded_b, clampf(to / span, 0.0, 1.0))
		return start_pos.distance_to(end_pos)


var roads: Array[Road] = []
var junctions: Dictionary = {}
var locations: Dictionary = {}
var stops: Dictionary = {}
var connections: Array[Array] = []
var nearest_target: Array[Dictionary] = []
var destinations: Dictionary[int, Dictionary] = {}
var target_distance := PackedFloat64Array()


func configure(planner: RoutePlanner, folded_position: Callable) -> void:
	roads.clear()
	junctions.clear()
	locations.clear()
	stops.clear()
	for city in planner.cities:
		for street: Dictionary in city.street_roads:
			_add_road(street, [city.id, street.from], [city.id, street.to], city.id, folded_position)
	for highway in planner.roads:
		var start := ["", highway.from]
		var finish := ["", highway.to]
		if planner.cities_by_id.has(highway.from):
			start = [highway.from, highway.from_point]
		if planner.cities_by_id.has(highway.to):
			finish = [highway.to, highway.to_point]
		_add_road(highway, start, finish, "", folded_position)
	for city in planner.cities:
		for place: Dictionary in city.places:
			var key := [city.id, place.road_node_id]
			if locations.has(key):
				locations[[city.id, place.id]] = locations[key]
	_index_destinations(planner.cities)


func _add_road(data: Dictionary, start: Array, finish: Array, city: String, folded_position: Callable) -> void:
	var road := Road.new()
	road.scene = data.get("scene")
	road.city = city
	road.highway = str(data.id) if not str(data.get("radio_name", "")).is_empty() else ""
	for point: Vector2 in data.points:
		if not road.points.is_empty():
			var length := point.distance_to(road.points[-1])
			if length <= EPS:
				road.source_offsets.append(road.length)
				continue
			road.length += length
			road.offsets.append(road.length)
		road.points.append(point)
		road.source_offsets.append(road.length)
	if road.points.size() < 2:
		return
	for point in road.points:
		road.folded_points.append(folded_position.call(point))
	road.prepare_pace()
	for key: Array in [start, finish]:
		if not junctions.has(key):
			junctions[key] = junctions.size()
	road.start = junctions[start]
	road.finish = junctions[finish]
	road.start_in_city = not str(start[0]).is_empty()
	road.finish_in_city = not str(finish[0]).is_empty()
	var index := roads.size()
	roads.append(road)
	locations[start] = {"edge": index, "offset": 0.0}
	locations[finish] = {"edge": index, "offset": road.length}
	if not road.highway.is_empty():
		stops["road_stop/" + road.highway] = {"edge": index, "offset": road.length * 0.5}
	# Посты задаются долей числа отсчётов, включая совпадающие точки кривой.
	for post in data.checkpoints:
		var sample: float = post.road_position * (data.points.size() - 1)
		var segment := mini(floori(sample), data.points.size() - 2)
		var offset := 0.0
		for i in range(segment):
			offset += data.points[i].distance_to(data.points[i + 1])
		offset += data.points[segment].distance_to(data.points[segment + 1]) * (sample - segment)
		road.posts.append({"offset": offset, "post": post})


func location(city: String, place: String) -> Dictionary:
	return stops.get(city, locations.get([city, place], {}))


# Расстояния до ближайшей цели считаем один раз по связям узлов сцены.
# От места клика попасть в эту сеть можно только через один из концов дороги.
func _index_destinations(cities: Array[Dictionary]) -> void:
	destinations.clear()
	nearest_target.clear()
	nearest_target.resize(junctions.size())
	target_distance.resize(junctions.size())
	target_distance.fill(INF)
	var pending: Array[int] = []
	for city in cities:
		for place in city.places:
			_add_destination(city.id, place.road_node_id, place.id, place.name, pending)
	for city in cities:
		_add_destination(city.id, city.entry_location_id, city.entry_location_id, city.name, pending)

	connections.clear()
	for node in junctions.size():
		connections.append([])
	for road in roads:
		connections[road.start].append(road)
		connections[road.finish].append(road)
	var cursor := 0
	while cursor < pending.size():
		var node := pending[cursor]
		cursor += 1
		for road: Road in connections[node]:
			var neighbor := road.finish if road.start == node else road.start
			var distance := target_distance[node] + road.length
			if distance < target_distance[neighbor]:
				target_distance[neighbor] = distance
				nearest_target[neighbor] = nearest_target[node]
				pending.append(neighbor)


func _add_destination(city: String, node: String, place: String, label: String, pending: Array[int]) -> void:
	var index: int = junctions.get([city, node], -1)
	if index >= 0 and target_distance[index] > 0.0:
		target_distance[index] = 0.0
		nearest_target[index] = {"city": city, "place": place, "name": label}
		destinations[index] = nearest_target[index]
		pending.append(index)


func pick_road(global_point: Vector2) -> Dictionary:
	var closest := INF
	var anchor := {}
	for i in roads.size():
		var road := roads[i]
		if not is_instance_valid(road.scene):
			continue
		var hit := road.scene.pick(global_point)
		if hit.is_empty():
			continue
		var distance := road.scene.to_global(hit.point).distance_squared_to(global_point)
		if distance >= closest:
			continue
		closest = distance
		var sample: float = clampf(hit.fraction, 0.0, 1.0) * (road.source_offsets.size() - 1)
		var segment := mini(floori(sample), road.source_offsets.size() - 2)
		var offset := lerpf(road.source_offsets[segment], road.source_offsets[segment + 1], sample - segment)
		anchor = {"edge": i, "offset": offset, "road_passage": true}
	return anchor


func destination_from(passage: Dictionary) -> Dictionary:
	var road := roads[int(passage.edge)]
	var via_start: float = passage.offset + target_distance[road.start]
	var via_finish: float = road.length - passage.offset + target_distance[road.finish]
	if is_inf(minf(via_start, via_finish)):
		return {}
	return nearest_target[road.start if via_start <= via_finish else road.finish]


func position(anchor: Dictionary, display: Callable = Callable()) -> Vector2:
	return roads[anchor.edge].position_at(anchor.offset, display)


# Для продления выбираем сторону дороги по пути от прежнего финиша к клику.
# После выезда с неё ищем цель по сети, закрыв обратный въезд.
func destination_ahead(origin: Dictionary, hit: Dictionary, incoming: Dictionary) -> Dictionary:
	if origin.is_empty():
		return {}
	var visits := PackedInt64Array()
	var arcs := {}
	var lanes: Array[PackedInt64Array] = []
	var graph := _make_graph([origin, hit], visits, arcs, lanes)
	var road := roads[int(hit.edge)]
	var lane := lanes[int(hit.edge)]
	var start_index := lane.find(visits[0])
	if start_index >= 0 and visits[0] != visits[1]:
		return _nearest_ahead(road, start_index < lane.find(visits[1]), visits[0])
	var approach := graph.get_id_path(visits[0], visits[1])
	if approach.is_empty():
		return {}
	var arrival := incoming
	if approach.size() > 1:
		arrival = arcs[Vector2i(approach[-2], approach[-1])]
	if arrival.get("edge", -1) == hit.edge:
		return _nearest_ahead(road, arrival.end > arrival.start, visits[0])
	if visits[1] == road.start or visits[1] == road.finish:
		return _nearest_ahead(road, visits[1] == road.start, visits[0])
	# Машина уже стоит в месте клика и ещё не двигалась по этой дороге.
	var forward := _nearest_ahead(road, true, visits[0])
	var backward := _nearest_ahead(road, false, visits[0])
	if forward.is_empty():
		return backward
	if backward.is_empty() or road.length - hit.offset + forward.distance <= hit.offset + backward.distance:
		return forward
	return backward


func _nearest_ahead(road: Road, forward: bool, origin_id: int) -> Dictionary:
	var entrance := road.start if forward else road.finish
	var exit_node := road.finish if forward else road.start
	var frontier: Array[int] = [exit_node]
	var distances: Dictionary[int, float] = {}
	distances[exit_node] = 0.0
	while not frontier.is_empty():
		var closest := 0
		for i in range(1, frontier.size()):
			if distances[frontier[i]] < distances[frontier[closest]]:
				closest = i
		var node: int = frontier.pop_at(closest)
		if node != origin_id and destinations.has(node):
			return {"target": destinations[node], "forward": forward, "distance": distances[node]}
		for next_road: Road in connections[node]:
			var other := next_road.finish if next_road.start == node else next_road.start
			var distance := distances[node] + next_road.length
			if other == entrance or distance >= distances.get(other, INF):
				continue
			distances[other] = distance
			if not frontier.has(other):
				frontier.append(other)
	return {}


func _make_graph(anchors: Array[Dictionary], visits: PackedInt64Array, arcs: Dictionary, lanes: Array[PackedInt64Array]) -> AStar2D:
	var graph := AStar2D.new()
	visits.resize(anchors.size())
	var next_id := junctions.size()
	for index in roads.size():
		var road := roads[index]
		var nodes := PackedInt64Array()
		var offsets := road.knots.duplicate()
		for anchor in anchors:
			if anchor.edge == index:
				offsets.append(anchor.offset)
		offsets.sort()
		var previous_id := -1
		var previous_offset := -1.0
		for offset in offsets:
			if previous_id >= 0 and offset - previous_offset <= EPS:
				continue
			var id := next_id
			if offset <= EPS:
				id = road.start
			elif offset >= road.length - EPS:
				id = road.finish
			else:
				next_id += 1
			if not graph.has_point(id):
				graph.add_point(id, road.position_at(offset))
			nodes.append(id)
			for i in anchors.size():
				if anchors[i].edge == index and absf(anchors[i].offset - offset) <= EPS:
					visits[i] = id
			if previous_id >= 0:
				graph.connect_points(previous_id, id)
				arcs[Vector2i(previous_id, id)] = {"edge": index, "start": previous_offset, "end": offset}
				arcs[Vector2i(id, previous_id)] = {"edge": index, "start": offset, "end": previous_offset}
			previous_id = id
			previous_offset = offset
		lanes.append(nodes)
	return graph


func _leg_path(graph: AStar2D, lanes: Array[PackedInt64Array], start: int, end: int, target: Dictionary) -> PackedInt64Array:
	if not target.has("via_edge"):
		return graph.get_id_path(start, end)
	var road_nodes := lanes[int(target.via_edge)].duplicate()
	if not target.forward:
		road_nodes.reverse()
	var index := road_nodes.find(start)
	var path: PackedInt64Array
	if index >= 0:
		path = road_nodes.slice(index)
	else:
		path = graph.get_id_path(start, road_nodes[0])
		if path.is_empty():
			return path
		path.append_array(road_nodes.slice(1))
	graph.set_point_disabled(road_nodes[0], true)
	var onward := graph.get_id_path(road_nodes[-1], end)
	graph.set_point_disabled(road_nodes[0], false)
	if onward.is_empty():
		return onward
	path.append_array(onward.slice(1))
	return path


func build(anchors: Array[Dictionary]) -> Dictionary:
	if anchors.size() < 2 or anchors.has({}):
		return {}
	var visits := PackedInt64Array()
	var arcs := {}
	var lanes: Array[PackedInt64Array] = []
	var graph := _make_graph(anchors, visits, arcs, lanes)
	var points: Array[Vector2] = [graph.get_point_position(visits[0])]
	var segments: Array[Dictionary] = []
	var fold_deltas: Array[Vector2] = []
	var crossings: Array[Dictionary] = []
	var midpoints := {}
	var waypoint_distances := PackedFloat64Array()
	var exit_distances := PackedFloat64Array()
	var distance := 0.0
	var road_offsets := PackedFloat64Array([0.0])
	var pace_offsets := PackedFloat64Array([0.0])
	var first_highway := INF
	for leg in range(1, visits.size()):
		var target := anchors[leg]
		var path := _leg_path(graph, lanes, visits[leg - 1], visits[leg], target)
		if path.is_empty():
			return {}
		var via: int = target.get("via_edge", -1)
		var exit_node := -1
		if via >= 0:
			exit_node = roads[via].finish if target.forward else roads[via].start
		var exit_distance := distance if path[0] == exit_node else INF
		for i in range(1, path.size()):
			var arc: Dictionary = arcs[Vector2i(path[i - 1], path[i])]
			var road := roads[int(arc.edge)]
			if road.city.is_empty():
				first_highway = minf(first_highway, distance)
			var forward: bool = arc.end > arc.start
			var entering_road: bool = not segments.is_empty() and segments[-1].edge != arc.edge
			for stop in road.posts:
				if _crosses(arc, stop.offset) or (entering_road and is_equal_approx(arc.start, stop.offset)):
					crossings.append({"post": stop.post, "forward": forward, "distance": distance + absf(stop.offset - arc.start)})
			if not road.highway.is_empty() and _crosses(arc, road.length * 0.5):
				if not midpoints.has(road.highway):
					midpoints[road.highway] = []
				midpoints[road.highway].append(distance + absf(road.length * 0.5 - arc.start))
			points.append(graph.get_point_position(path[i]))
			segments.append(arc)
			var length := absf(arc.end - arc.start)
			distance += length
			if arc.edge == via and path[i] == exit_node:
				exit_distance = distance
			road_offsets.append(distance)
			if fold_deltas.is_empty():
				fold_deltas.append(points[-2] - road.folded_at(arc.start))
			fold_deltas.append(points[-1] - road.folded_at(arc.end))
			pace_offsets.append(pace_offsets[-1] + absf(road.pace_at(arc.end) - road.pace_at(arc.start)))
		if leg < visits.size() - 1:
			waypoint_distances.append(distance)
		exit_distances.append(exit_distance)
	return {"points": points, "segments": segments, "distance": distance, "crossings": crossings,
		"fold_deltas": fold_deltas, "road_offsets": road_offsets, "pace_offsets": pace_offsets,
		"midpoints": midpoints, "waypoint_distances": waypoint_distances, "exit_distances": exit_distances, "first_highway": first_highway}


func _crosses(arc: Dictionary, offset: float) -> bool:
	if arc.start < arc.end:
		return arc.start < offset and offset <= arc.end
	return arc.end <= offset and offset < arc.start
