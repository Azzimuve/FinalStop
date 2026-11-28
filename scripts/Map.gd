extends Node2D

const RoutePlanner = preload("res://scripts/map/RoutePlanner.gd")
const WaypointRouter = preload("res://scripts/map/WaypointRouter.gd")
const RouteGeometry = preload("res://scripts/map/RouteGeometry.gd")
const WorldMapData = preload("res://scripts/WorldMapData.gd")

signal waypoint_removed(index: int)
signal city_view_changed(city_id: String, city_name: String, interactive: bool)
signal location_selected(city_id: String, place_id: String, place_name: String, append: bool)
signal road_selected(passage: Dictionary, append: bool)

@export var world_zoom := Vector2(0.55, 0.55)
@export var city_zoom := Vector2(1.4, 1.4)
@export var min_zoom: float = 0.25
@export var max_zoom: float = 2.4
@export var detail_start: float = 0.85
@export var detail_full: float = 1.35
var target_zoom: float = 0.55
var detail_alpha: float = 0.0
var zoom_anchor := Vector2.ZERO
var zoom_cursor := Vector2.ZERO
@export var route_color := Color("#ca713a")
@export var route_dash_length := 16.0
@export var route_gap_length := 0.0

enum ViewMode {
	WORLD,
	CITY,
}

@onready var camera: Camera2D = $MapCamera
@onready var world: WorldMapData = $World
@onready var incident_marker: Node2D = $RoadIncidentMarker
@onready var incident_caption: Label = $RoadIncidentMarker/Caption
var incident_stop_id := ""
@onready var vehicle = $Vehicle

var routes: RoutePlanner = RoutePlanner.new()

var waypoint_router := WaypointRouter.new()
var waypoints: Array[Dictionary] = []
var custom_path: Dictionary = {}
var custom_finish: Dictionary = {}
var custom_display_anchors: Dictionary = {}
var route_editable := true

var current_city_id: String = ""
var current_location_id: String = ""
var viewing_city_id: String = ""
var selected_place_id: String = ""
var view_mode: ViewMode = ViewMode.WORLD
var active_route_points: Array[Vector2] = []
var route_checkpoints: Array[Dictionary] = []
var highway_midpoints: Dictionary[String, float] = {}
var active_route_destination_city_id: String = ""
var route_visible: bool = false
var trip_progress: float = 0.0
var local_route_points: Array[Vector2] = []
var local_checkpoints: Array[Dictionary] = []
var local_route_city_id: String = ""
var local_trip_progress: float = 0.0
var local_trip_active: bool = false
var trackpad_scroll_accumulator: float = 0.0
var route_selection_locked: bool = false

@export var camera_drag_threshold: float = 5.0
@export var camera_drag_response: float = 18.0
@export var camera_drag_sensitivity: float = 1.15
var camera_drag_target := Vector2.ZERO
var camera_drag_settling: bool = false
var camera_drag_pending: bool = false
var camera_drag_active: bool = false
var camera_press_position: Vector2
var camera_press_world_position: Vector2
var camera_press_camera_position: Vector2
var camera_transition: Tween
var camera_focus_city: String = ""
var arrival_focus_started: bool = false
var city_focus_from := PackedFloat64Array()
var departure_focus_distance: float = 0.0
var route_distance := 0.0
var vehicle_before_step := Vector2.ZERO
var movement_budget := 0.0
var vehicle_fold_delta := Vector2.ZERO
var departure_zoom: float = 1.4
# Расстояние от центра кадра до машины в пикселях логического viewport.
var tracking_offset := Vector2.ZERO
var has_tracking_offset := false
var last_camera_position := Vector2(INF, INF)
var last_camera_zoom := Vector2.ZERO
var last_viewport_size := Vector2.ZERO
var follow_idle_seconds: float = 0.0
@export var follow_zoom: float = 0.75
@export var follow_response: float = 1.5
## За сколько единиц пути до въезда камера начинает раскрывать город.
@export_range(0.0, 1000.0, 1.0, "or_greater") var city_approach_distance := 180.0
## Скорость автоматического изменения масштаба: меньше — плавнее.
@export_range(0.1, 5.0, 0.1) var follow_zoom_response: float = 1.0
var follow_traveling: bool = false
var follow_in_city: bool = false


func _ready() -> void:
	routes.configure(world.read_graph())
	$RoutePins.draw.connect(_draw_route_pins)
	set_process_unhandled_input(true)
	camera.make_current()
	_show_world_view()
	waypoint_router.configure(routes, world.display_route_point)


func _process(delta: float) -> void:
	var automatic_zoom_applied := false
	if follow_traveling:
		follow_idle_seconds += delta
		if follow_idle_seconds >= 2.0 and not camera_drag_pending and not camera_drag_settling and not _camera_transition_active():
			if not has_tracking_offset:
				tracking_offset = (vehicle.position - camera.position) * camera.zoom
				has_tracking_offset = true
			var departing_city := trip_progress * route_distance < departure_focus_distance
			var desired_zoom := minf(follow_zoom, departure_zoom)
			if follow_in_city or arrival_focus_started:
				desired_zoom = city_zoom.x
			elif departing_city:
				desired_zoom = departure_zoom
			target_zoom = desired_zoom
			var zoom := lerpf(camera.zoom.x, desired_zoom, 1.0 - exp(-follow_zoom_response * delta))
			if not follow_in_city and not arrival_focus_started and zoom < camera.zoom.x:
				# Даже с максимального приближения переход через диапазон сворачивания занимает время.
				zoom = maxf(zoom, camera.zoom.x - (detail_full - detail_start) * follow_zoom_response * delta)
			zoom = _limit_follow_zoom(zoom)
			camera.zoom = Vector2.ONE * zoom
			var next_detail := smoothstep(detail_start, detail_full, zoom)
			if next_detail != detail_alpha:
				detail_alpha = next_detail
				_refresh_visuals()
			var recenter_step := tracking_offset.length() * (1.0 - exp(-follow_response * delta))
			tracking_offset = tracking_offset.move_toward(Vector2.ZERO, minf(recenter_step, vehicle.base_speed * zoom * delta))
			camera.position = vehicle.position - tracking_offset / camera.zoom
			automatic_zoom_applied = true
			zoom_anchor = camera.position
			zoom_cursor = get_viewport_rect().size / 2.0
			camera.force_update_scroll()
	if not automatic_zoom_applied:
		has_tracking_offset = false
	if camera_drag_settling and not _camera_transition_active():
		camera.position = camera.position.lerp(camera_drag_target, 1.0 - exp(-camera_drag_response * delta))
		if camera.position.distance_to(camera_drag_target) * camera.zoom.x < 0.1:
			camera.position = camera_drag_target
			camera_drag_settling = false
		zoom_anchor = camera.position
		zoom_cursor = get_viewport_rect().size / 2.0
		camera.force_update_scroll()
	# Ручной зум не должен повторно ускорять автоматическое сворачивание.
	if not automatic_zoom_applied and not _camera_transition_active() and absf(camera.zoom.x - target_zoom) > 0.0001:
		var zoom := lerpf(camera.zoom.x, target_zoom, 1.0 - exp(-12.0 * delta))
		camera.zoom = Vector2.ONE * zoom
		if not camera_drag_pending:
			camera.position = zoom_anchor - (zoom_cursor - get_viewport_rect().size / 2.0) / zoom
		camera.force_update_scroll()
	var viewport_size := get_viewport_rect().size
	if camera.position == last_camera_position and camera.zoom == last_camera_zoom and viewport_size == last_viewport_size:
		return
	last_camera_position = camera.position
	last_camera_zoom = camera.zoom
	last_viewport_size = viewport_size
	detail_alpha = smoothstep(detail_start, detail_full, camera.zoom.x)
	var previous_city := viewing_city_id
	var nearest_distance := INF
	for city in routes.cities:
		var distance: float = camera.position.distance_squared_to(city["position"])
		if distance < nearest_distance:
			nearest_distance = distance
			viewing_city_id = city["id"]
	var next_mode := ViewMode.CITY if detail_alpha >= 0.5 and not viewing_city_id.is_empty() else ViewMode.WORLD
	if next_mode != view_mode or (next_mode == ViewMode.CITY and previous_city != viewing_city_id):
		view_mode = next_mode
		if view_mode == ViewMode.CITY:
			var city: Dictionary = routes.cities_by_id[viewing_city_id]
			city_view_changed.emit(viewing_city_id, city["name"], viewing_city_id == current_city_id)
		else:
			city_view_changed.emit("", "Общий вид", false)
	_refresh_visuals()


# Сворачивание может сдвинуть всю улицу вместе с машиной. Подбираем шаг
# автозума так, чтобы сумма движения и сдвига карты укладывалась в шаг поездки.
func _limit_follow_zoom(zoom: float) -> float:
	if custom_path.is_empty() or is_zero_approx(zoom - camera.zoom.x):
		return zoom
	var motion: Vector2 = vehicle.position - vehicle_before_step
	var limit := maxf(motion.length(), movement_budget) + 0.0001
	var detail := smoothstep(detail_start, detail_full, zoom)
	if (motion + vehicle_fold_delta * (detail - detail_alpha)).length() <= limit:
		return zoom
	var allowed := camera.zoom.x
	var excess := zoom
	for i in 12:
		var middle := (allowed + excess) * 0.5
		detail = smoothstep(detail_start, detail_full, middle)
		if (motion + vehicle_fold_delta * (detail - detail_alpha)).length() <= limit:
			allowed = middle
		else:
			excess = middle
	return allowed


func _record_travel_step(previous: float, progress: float) -> void:
	vehicle_before_step = vehicle.position
	movement_budget = 0.0
	vehicle_fold_delta = Vector2.ZERO
	if custom_path.is_empty():
		return
	var road: PackedFloat64Array = custom_path.road_offsets
	var pace: PackedFloat64Array = custom_path.pace_offsets
	var distance := progress * route_distance
	var i := clampi(road.bsearch(distance), 1, road.size() - 1)
	arrival_focus_started = distance >= city_focus_from[i - 1]
	var weight := inverse_lerp(road[i - 1], road[i], distance)
	var deltas: Array[Vector2] = custom_path.fold_deltas
	vehicle_fold_delta = deltas[i - 1].lerp(deltas[i], weight)
	var before := previous * route_distance
	var j := clampi(road.bsearch(before), 1, road.size() - 1)
	movement_budget = lerpf(pace[i - 1], pace[i], weight) - remap(before, road[j - 1], road[j], pace[j - 1], pace[j])


func _request_zoom(factor: float, cursor: Vector2) -> void:
	follow_idle_seconds = 0.0
	camera_drag_settling = false
	# Обычные шаги колеса накапливаются в целевом масштабе.
	# Сбрасываем его к текущему только при прерывании автоперехода.
	if _camera_transition_active():
		_cancel_camera_transition()
	camera_focus_city = ""
	zoom_cursor = cursor
	zoom_anchor = _event_to_local(cursor)
	target_zoom = clampf(target_zoom * factor, min_zoom, max_zoom)
	if camera.zoom.x < detail_start or viewing_city_id.is_empty():
		var nearest := ""
		var distance := INF
		for city in routes.cities:
			var candidate: float = zoom_anchor.distance_to(city["position"])
			if candidate < distance:
				distance = candidate
				nearest = city["id"]
		viewing_city_id = nearest
	get_viewport().set_input_as_handled()


func set_current_location(city_id: String, location_id: String, open_city_view: bool = true) -> void:
	if routes.road_stops.has(city_id):
		current_city_id = city_id
		current_location_id = location_id
		clear_local_route()
		return
	if not routes.cities_by_id.has(city_id):
		push_warning("Unknown city ID: %s" % city_id)
		return
	var city: Dictionary = routes.cities_by_id[city_id]
	if routes.node_id_for_location(city, location_id).is_empty():
		push_warning("Unknown location ID: %s" % location_id)
		return

	current_city_id = city_id
	current_location_id = location_id
	clear_local_route()
	if open_city_view:
		_show_city_view(city_id)
	else:
		_refresh_visuals()


func set_route_visible(visible: bool) -> void:
	route_visible = visible
	_refresh_visuals()


func clear_route() -> void:
	custom_path = {}
	city_focus_from.clear()
	arrival_focus_started = false
	custom_finish = {}
	custom_display_anchors.clear()
	waypoints.clear()
	highway_midpoints.clear()
	active_route_points.clear()
	route_checkpoints.clear()
	active_route_destination_city_id = ""
	route_visible = false
	trip_progress = 0.0
	_refresh_visuals()


func set_route_selection_locked(locked: bool) -> void:
	route_selection_locked = locked


func set_trip_progress(progress: float) -> void:
	_record_travel_step(trip_progress, progress)
	trip_progress = clampf(progress, 0.0, 1.0)
	_refresh_visuals()


func set_local_trip_progress(progress: float) -> void:
	if local_route_points.size() < 2:
		return
	local_trip_active = true
	_record_travel_step(local_trip_progress, progress)
	local_trip_progress = clampf(progress, 0.0, 1.0)
	_refresh_visuals()


func clear_local_route() -> void:
	local_checkpoints.clear()
	selected_place_id = ""
	local_route_points.clear()
	local_trip_active = false
	local_trip_progress = 0.0
	_refresh_visuals()


# Начало жеста принимается только вне UI, продолжение — даже над панелями.
func _input(event: InputEvent) -> void:
	if not camera_drag_pending:
		return
	if event is InputEventMouseMotion:
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			camera_drag_pending = false
			camera_drag_active = false
			return
		if event.position.distance_to(camera_press_position) >= camera_drag_threshold:
			camera_drag_active = true
		if camera_drag_active:
			follow_idle_seconds = 0.0
			_cancel_camera_transition()
			camera_drag_target = camera_press_camera_position - (event.position - camera_press_position) * camera_drag_sensitivity / camera.zoom
			camera_drag_settling = true
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		camera_drag_pending = false
		if not camera_drag_active and route_editable:
			_route_click(camera_press_world_position, event.shift_pressed)
		camera_drag_active = false
		get_viewport().set_input_as_handled()


func _route_click(point: Vector2, append: bool) -> void:
	if not route_editable or _select_incident_at(point, append):
		return
	if view_mode == ViewMode.CITY:
		if _select_place_at(point, append):
			return
	elif _select_city_at(point, append):
		return
	var passage := waypoint_router.pick_road(to_global(point))
	if not passage.is_empty():
		road_selected.emit(passage, append)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventPanGesture:
		_handle_pan_gesture(event)
	elif event is InputEventMagnifyGesture:
		_handle_magnify_gesture(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return

	var local_position := _event_to_local(event.position)
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_request_zoom(1.3, event.position)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_request_zoom(1.0 / 1.3, event.position)
	elif event.button_index == MOUSE_BUTTON_RIGHT and route_editable:
		for i in range(waypoints.size() - 1, -1, -1):
			if _waypoint_pin_visible(i) and local_position.distance_to(waypoint_router.position(waypoints[i], world.display_route_point)) * camera.zoom.x <= 12.0:
				waypoint_removed.emit(i)
				get_viewport().set_input_as_handled()
				break
	elif event.button_index == MOUSE_BUTTON_LEFT:
		follow_idle_seconds = 0.0
		camera_drag_settling = false
		camera_drag_pending = true
		camera_drag_active = false
		camera_press_position = event.position
		camera_press_world_position = local_position
		camera_press_camera_position = camera.position
		get_viewport().set_input_as_handled()


func _handle_pan_gesture(event: InputEventPanGesture) -> void:
	_request_zoom(exp(-event.delta.y * 0.04), event.position)


func _handle_magnify_gesture(event: InputEventMagnifyGesture) -> void:
	_request_zoom(event.factor, event.position)


func _event_to_local(viewport_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_position


func _select_place_at(point: Vector2, append := false) -> bool:
	if not route_editable or detail_alpha < 0.75:
		return false
	var hit: Dictionary = {}
	var hit_city := ""
	var closest := INF
	var world_point := to_global(point)
	for city in routes.cities:
		for place in city.places:
			var marker: Polygon2D = place.marker
			var distance := marker.global_position.distance_squared_to(world_point)
			if distance < closest and _marker_contains(marker, world_point):
				hit = place
				hit_city = city.id
				closest = distance
	if hit.is_empty():
		return false
	location_selected.emit(hit_city, hit.id, hit.name, append)
	return true


func set_road_incident(road: Dictionary, title: String) -> void:
	incident_stop_id = "" if road.is_empty() else routes.road_stop_id(road)
	incident_marker.visible = routes.road_stops.has(incident_stop_id)
	incident_caption.text = title
	_refresh_visuals()


func _select_incident_at(map_position: Vector2, append := false) -> bool:
	if not route_editable or not incident_marker.visible:
		return false
	var hit := incident_marker.to_local(to_global(map_position))
	if hit.length() > 15.0 and not incident_caption.get_rect().has_point(hit):
		return false
	location_selected.emit(incident_stop_id, incident_stop_id, incident_caption.text, append)
	return true


func _refresh_visuals() -> void:
	world.set_view(detail_alpha, current_city_id, selected_place_id)
	var in_city := routes.cities_by_id.has(current_city_id)
	var on_highway := routes.road_stops.has(current_city_id)
	if incident_marker.visible:
		incident_marker.position = _displayed_route_point(routes.world_position_for_node(incident_stop_id))
		incident_marker.scale = Vector2.ONE / camera.zoom.x
	vehicle.get_node("CityMarker").position = Vector2.ZERO
	vehicle.get_node("WorldMarker").visible = on_highway or (route_visible and active_route_points.size() > 1)
	vehicle.get_node("CityMarker").visible = in_city and not (route_visible and active_route_points.size() > 1)
	if in_city:
		var city: Dictionary = routes.cities_by_id[current_city_id]
		var player_position := routes.position_for_location(city, current_location_id)
		if local_trip_active:
			player_position = RouteGeometry.position_at(local_route_points, local_trip_progress)
		vehicle.position = Vector2(city.position).lerp(player_position, detail_alpha)
		vehicle.get_node("CityMarker").modulate.a = smoothstep(0.55, 0.95, detail_alpha)
	elif on_highway:
		vehicle.position = _displayed_route_point(routes.world_position_for_node(current_city_id))
	if route_visible and active_route_points.size() > 1:
		var displayed := _displayed_remaining_route()
		vehicle.position = displayed[0] if not displayed.is_empty() else _displayed_route_point(active_route_points[-1])
	queue_redraw()
	$RoutePins.queue_redraw()


var lesson_city := ""
var lesson_place := ""

func guide_to(city_id: String, place_id: String) -> void:
	if city_id != lesson_city or place_id != lesson_place:
		lesson_city = city_id
		lesson_place = place_id
		queue_redraw()

func _draw() -> void:
	if routes.cities_by_id.has(lesson_city):
		var city: Dictionary = routes.cities_by_id[lesson_city]
		for place in city.places:
			if place.id == lesson_place:
				draw_arc(city.position + place.position * detail_alpha, 17.0 / camera.zoom.x, 0, TAU, 40, Color.GOLD, 2.5 / camera.zoom.x, true)
				break
	if route_visible and active_route_points.size() > 1:
		_draw_route_line(_displayed_remaining_route())
	for city in routes.cities:
		var origin: Vector2 = city.position
		var opacity := smoothstep(0.55, 0.95, detail_alpha)
		if local_route_points.size() > 1 and local_route_city_id == city.id:
			var progress := local_trip_progress if local_trip_active else 0.0
			_draw_route_line(_fold_city_points(RouteGeometry.remaining_points(local_route_points, progress), origin), opacity)


func _draw_route_pins() -> void:
	var pins: Node2D = $RoutePins
	var font := preload("res://resources/fonts/PTSansNarrow-Bold.ttf")
	var number := 0
	for i in waypoints.size():
		if not _waypoint_pin_visible(i):
			continue
		number += 1
		var center := waypoint_router.position(waypoints[i], world.display_route_point)
		pins.draw_set_transform(center, 0.0, Vector2.ONE / camera.zoom.x)
		pins.draw_circle(Vector2.ZERO, 10.0, Color("#172326"), true, -1, true)
		pins.draw_arc(Vector2.ZERO, 10.0, 0, TAU, 30, Color("#f6ce7e"), 2.0, true)
		pins.draw_string(font, Vector2(-11, 5), str(number), HORIZONTAL_ALIGNMENT_CENTER, 22, 13)
	if not custom_finish.is_empty():
		var center := waypoint_router.position(custom_finish, world.display_route_point)
		pins.draw_set_transform(center, 0.0, Vector2.ONE / camera.zoom.x)
		pins.draw_arc(Vector2.ZERO, 11.0, 0, TAU, 32, Color.WHITE, 2.0, true)
		pins.draw_circle(Vector2.ZERO, 3.0, route_color, true, -1, true)


func route_origin(in_trip: bool, local: bool) -> Dictionary:
	if not in_trip:
		return waypoint_router.location(current_city_id, current_location_id)
	var progress := local_trip_progress if local else trip_progress
	var distance := progress * route_distance
	var offsets: PackedFloat64Array = custom_path.road_offsets
	var index := clampi(offsets.bsearch(distance) - 1, 0, offsets.size() - 2)
	var weight := clampf(inverse_lerp(offsets[index], offsets[index + 1], distance), 0.0, 1.0)
	var arc: Dictionary = custom_path.segments[index]
	return {"edge": arc.edge, "offset": lerpf(arc.start, arc.end, weight)}


func install_custom_route(plan: Dictionary, via: Array[Dictionary], finish: Dictionary, city: String, place: String, local: bool) -> void:
	var continue_city_view := route_selection_locked and arrival_focus_started
	custom_path = plan
	custom_finish = finish
	waypoints = via
	_index_city_approaches(plan, continue_city_view)
	custom_display_anchors.clear()
	for i in plan.segments.size():
		var arc: Dictionary = plan.segments[i]
		custom_display_anchors[plan.points[i]] = {"edge": arc.edge, "offset": arc.start}
		var last: Vector2 = plan.points[i + 1]
		custom_display_anchors[last] = {"edge": arc.edge, "offset": arc.end}
	active_route_points.clear()
	local_route_points.clear()
	local_checkpoints.clear()
	route_checkpoints.clear()
	highway_midpoints.clear()
	for id: String in plan.midpoints:
		highway_midpoints[id] = plan.midpoints[id][0]
	active_route_destination_city_id = city
	selected_place_id = place
	route_distance = plan.distance
	trip_progress = 0.0
	local_trip_progress = 0.0
	local_trip_active = local and route_selection_locked
	route_visible = not local
	arrival_focus_started = false
	departure_focus_distance = 0.0 if is_inf(plan.first_highway) else plan.first_highway
	if local:
		local_route_city_id = city
		local_route_points.assign(plan.points)
		local_checkpoints.assign(plan.crossings)
	else:
		active_route_points.assign(plan.points)
		route_checkpoints.assign(plan.crossings)
	_refresh_visuals()


func _index_city_approaches(plan: Dictionary, continue_city_view: bool) -> void:
	var offsets: PackedFloat64Array = plan.road_offsets
	var stops := PackedFloat64Array()
	for i in waypoints.size():
		if not waypoints[i].get("road_passage", false):
			stops.append(plan.waypoint_distances[i])
	city_focus_from.resize(plan.segments.size())
	city_focus_from.fill(INF)
	var highway_start := 0
	for i in plan.segments.size():
		var arc: Dictionary = plan.segments[i]
		var road := waypoint_router.roads[int(arc.edge)]
		if not road.city.is_empty():
			if offsets[i] >= plan.first_highway or continue_city_view:
				city_focus_from[i] = offsets[i]
			highway_start = i + 1
			continue
		var enters_city: bool = (road.start_in_city and arc.end <= WaypointRouter.EPS) or (road.finish_in_city and arc.end >= road.length - WaypointRouter.EPS)
		if not enters_city:
			continue
		var entry := offsets[i + 1]
		if i + 1 < plan.segments.size() and not stops.has(entry):
			var next_road := waypoint_router.roads[int(plan.segments[i + 1].edge)]
			if next_road.city.is_empty():
				continue
		# Отсчитываем подъезд от въезда, в том числе при перестроении в пути.
		var first_arc: Dictionary = plan.segments[highway_start]
		var first_road := waypoint_router.roads[int(first_arc.edge)]
		var before_start: float = first_arc.start if first_arc.end > first_arc.start else first_road.length - first_arc.start
		var approach := entry - minf(city_approach_distance, (entry - offsets[highway_start] + before_start) * 0.5)
		for j in range(highway_start, i + 1):
			city_focus_from[j] = approach
		highway_start = i + 1


func finish_intercity_arrival(city: String, place: String) -> void:
	var following := follow_traveling and follow_idle_seconds >= 2.0 and not camera_drag_pending and not camera_drag_settling
	set_follow_traveling(false)
	set_current_location(city, place, false)
	if not following or not routes.cities_by_id.has(city) or is_equal_approx(camera.zoom.x, city_zoom.x):
		return
	_cancel_camera_transition()
	var screen_offset: Vector2 = (vehicle.position - camera.position) * camera.zoom
	target_zoom = city_zoom.x
	camera_transition = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	camera_transition.tween_method(_zoom_at_parked_vehicle.bind(screen_offset), camera.zoom.x, target_zoom, 1.8)


func _zoom_at_parked_vehicle(zoom: float, screen_offset: Vector2) -> void:
	camera.zoom = Vector2.ONE * zoom
	detail_alpha = smoothstep(detail_start, detail_full, zoom)
	_refresh_visuals()
	camera.position = vehicle.position - screen_offset / zoom
	camera.force_update_scroll()


func next_highway_midpoint(id: String, travelled: float) -> float:
	if custom_path.is_empty():
		return highway_midpoints.get(id, INF)
	for distance: float in custom_path.midpoints.get(id, []):
		if distance >= travelled - WaypointRouter.EPS:
			return distance
	return INF


func _waypoint_pin_visible(index: int) -> bool:
	return not waypoints[index].get("road_passage", false) and waypoint_pending(index)


func waypoint_pending(index: int) -> bool:
	return not route_selection_locked or custom_path.waypoint_distances[index] > _travelled_distance() + WaypointRouter.EPS


func remaining_anchor(index: int) -> Dictionary:
	var anchor := custom_finish if index == waypoints.size() else waypoints[index]
	if route_selection_locked and anchor.has("via_edge") and _travelled_distance() + WaypointRouter.EPS >= custom_path.exit_distances[index]:
		anchor = anchor.duplicate()
		anchor.erase("via_edge")
		anchor.erase("forward")
	return anchor


func _travelled_distance() -> float:
	var progress := local_trip_progress if local_trip_active else trip_progress
	return progress * custom_path.distance


func _displayed_route_point(point: Vector2) -> Vector2:
	if custom_display_anchors.has(point):
		return waypoint_router.position(custom_display_anchors[point], world.display_route_point)
	# Все отсчёты кривой следуют за геометрией сцены при раскрытии города.
	if routes.midpoint_segments.has(point):
		var segment: Dictionary = routes.midpoint_segments[point]
		return world.display_route_point(segment.a).lerp(world.display_route_point(segment.b), segment.weight)
	return world.display_route_point(point)


func _displayed_route() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for point in active_route_points:
		points.append(_displayed_route_point(point))
	return points


func _displayed_remaining_route() -> Array[Vector2]:
	var displayed := _displayed_route()
	# На деформированной дороге машина и пост должны оставаться на одном отрезке.
	var travelled := trip_progress * route_distance
	for end in range(1, active_route_points.size()):
		var length := active_route_points[end - 1].distance_to(active_route_points[end])
		if length > 0.0 and travelled <= length:
			var remaining: Array[Vector2] = displayed.slice(end - 1)
			remaining[0] = displayed[end - 1].lerp(displayed[end], travelled / length)
			return remaining
		travelled -= length
	return [displayed[-1]]


func _fold_city_points(points: Array[Vector2], origin: Vector2) -> Array[Vector2]:
	var folded: Array[Vector2] = []
	for point in points:
		folded.append(origin.lerp(point, detail_alpha))
	return folded


func _draw_route_line(points: Array[Vector2], opacity: float = 1.0) -> void:
	if points.size() < 2:
		return
	if route_gap_length <= 0.0 or route_dash_length <= 0.0:
		draw_polyline(PackedVector2Array(points), Color(route_color, opacity), 3.5 / camera.zoom.x, true)
		return
	for index in range(points.size() - 1):
		var start := points[index]
		var finish := points[index + 1]
		var segment := finish - start
		var segment_length := segment.length()
		if segment_length <= 0.0:
			continue

		var direction := segment / segment_length
		var distance := 0.0
		while distance < segment_length:
			var dash_end := minf(distance + route_dash_length, segment_length)
			draw_line(
				start + direction * distance,
				start + direction * dash_end,
				Color(route_color, opacity),
				3.5,
				true
			)
			distance += route_dash_length + route_gap_length


func _show_world_view() -> void:
	view_mode = ViewMode.WORLD
	viewing_city_id = ""
	selected_place_id = ""
	local_route_points.clear()
	local_trip_active = false
	local_trip_progress = 0.0
	trackpad_scroll_accumulator = 0.0
	camera.position = world.world_center
	camera.zoom = world_zoom
	target_zoom = world_zoom.x
	zoom_anchor = camera.position
	zoom_cursor = get_viewport_rect().size / 2.0
	city_view_changed.emit("", "Общий вид", false)
	_refresh_visuals()


func _show_city_view(city_id: String) -> void:
	if not routes.cities_by_id.has(city_id):
		return

	view_mode = ViewMode.CITY
	viewing_city_id = city_id
	selected_place_id = ""
	local_route_points.clear()
	local_trip_active = false
	local_trip_progress = 0.0
	var city: Dictionary = routes.cities_by_id[city_id]
	_focus_city(city_id)
	city_view_changed.emit(
		city_id,
		city["name"],
		city_id == current_city_id
	)
	_refresh_visuals()


func _camera_transition_active() -> bool:
	return camera_transition != null and camera_transition.is_running()


func set_follow_traveling(traveling: bool, in_city: bool = false) -> void:
	if traveling != follow_traveling:
		# Событие в дороге может остановить поездку посреди сворачивания.
		# Оставшаяся цель автозума не должна перейти быстрому ручному зуму.
		if not traveling and has_tracking_offset:
			target_zoom = camera.zoom.x
		has_tracking_offset = false
		follow_idle_seconds = 2.0 if traveling else 0.0
		if traveling:
			# Выезд сохраняет выбранный масштаб и может только отдалять камеру.
			departure_zoom = minf(camera.zoom.x, target_zoom)
			_cancel_camera_transition()
			if not get_viewport_rect().has_point(vehicle.get_global_transform_with_canvas().origin):
				camera.position = vehicle.position
				camera.force_update_scroll()
			tracking_offset = (vehicle.position - camera.position) * camera.zoom
			has_tracking_offset = true
	follow_traveling = traveling
	follow_in_city = in_city


func _cancel_camera_transition() -> void:
	if camera_transition != null:
		camera_transition.kill()
	camera_focus_city = ""
	target_zoom = camera.zoom.x


func _focus_city(city_id: String) -> void:
	camera_drag_settling = false
	var destination: Vector2 = routes.cities_by_id[city_id]["position"] + Vector2(-100.0, 0.0)
	if camera_focus_city == city_id:
		if _camera_transition_active() or camera.position.distance_to(destination) < 0.1:
			return
	_cancel_camera_transition()
	camera_focus_city = city_id
	target_zoom = city_zoom.x
	zoom_anchor = destination
	zoom_cursor = get_viewport_rect().size / 2.0
	camera_transition = create_tween().set_parallel(true)
	camera_transition.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	camera_transition.tween_property(camera, "position", destination, 1.8)
	camera_transition.tween_property(camera, "zoom", city_zoom, 1.8)


func _marker_contains(marker: Polygon2D, world_point: Vector2) -> bool:
	return marker.is_visible_in_tree() and marker.modulate.a > 0.0 and Geometry2D.is_point_in_polygon(marker.to_local(world_point), marker.polygon)


func _select_city_at(point: Vector2, append: bool) -> bool:
	var world_point := to_global(point)
	for city in routes.cities:
		if _marker_contains(city.marker, world_point):
			location_selected.emit(city.id, city.entry_location_id, city.name, append)
			return true
	return false
