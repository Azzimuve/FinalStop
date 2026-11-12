extends Node2D

const RoutePlanner = preload("res://scripts/map/RoutePlanner.gd")
const RouteGeometry = preload("res://scripts/map/RouteGeometry.gd")
const WorldMapData = preload("res://scripts/WorldMapData.gd")

signal city_view_changed(city_id: String, city_name: String, interactive: bool)
signal city_selected(city_id: String, city_name: String)
signal location_selected(city_id: String, place_id: String, place_name: String, route_available: bool)

const WORLD_ZOOM := Vector2(0.55, 0.55)
const CITY_ZOOM := Vector2(1.4, 1.4)
const MIN_ZOOM: float = 0.25
const MAX_ZOOM: float = 2.4
const DETAIL_START: float = 0.85
const DETAIL_FULL: float = 1.35
var target_zoom: float = 0.55
var detail_alpha: float = 0.0
var zoom_anchor := Vector2.ZERO
var zoom_cursor := Vector2.ZERO
const WORLD_BACKGROUND := Color(0.055, 0.078, 0.086)
const ROAD_COLOR := Color(0.20, 0.28, 0.29)
const ROUTE_COLOR := Color(0.96, 0.20, 0.18)
const CITY_COLOR := Color(0.76, 0.81, 0.78)
const CURRENT_CITY_COLOR := Color(0.48, 0.78, 0.65)
const PLACE_COLOR := Color(0.88, 0.83, 0.62)
const SELECTED_PLACE_COLOR := Color(0.96, 0.20, 0.18)
const PLAYER_MARKER_COLOR := Color(0.30, 0.86, 0.76)
const WORLD_MARKER_COLOR := Color(0.95, 0.40, 0.28)
const TRACKPAD_SCROLL_THRESHOLD := 8.0
const ROUTE_DASH_LENGTH := 16.0
const ROUTE_GAP_LENGTH := 12.0

enum ViewMode {
	WORLD,
	CITY,
}

@onready var camera: Camera2D = $MapCamera

var routes := RoutePlanner.new()

var current_city_id: String = ""
var current_location_id: String = ""
var viewing_city_id: String = ""
var selected_place_id: String = ""
var view_mode: ViewMode = ViewMode.WORLD
var active_route_ids: Array[String] = []
var active_route_points: Array[Vector2] = []
var active_route_destination_city_id: String = ""
var active_route_destination_location_id: String = ""
var route_visible: bool = false
var trip_progress: float = 0.0
var local_route_points: Array[Vector2] = []
var local_route_city_id: String = ""
var arrival_location_id: String = ""
var local_trip_progress: float = 0.0
var local_trip_active: bool = false
var trackpad_scroll_accumulator: float = 0.0
var route_selection_locked: bool = false

const CAMERA_DRAG_THRESHOLD: float = 5.0
const CAMERA_DRAG_RESPONSE: float = 18.0
const CAMERA_DRAG_SENSITIVITY: float = 1.15
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
var last_camera_position := Vector2(INF, INF)
var last_camera_zoom := Vector2.ZERO
var last_viewport_size := Vector2.ZERO
var follow_idle_seconds: float = 0.0
const FOLLOW_ZOOM: float = 0.75
const FOLLOW_RESPONSE: float = 1.5
var follow_traveling: bool = false
var follow_in_city: bool = false
var follow_position := Vector2.ZERO



func _ready() -> void:
	set_process_unhandled_input(true)
	camera.make_current()
	_show_world_view()


func _process(delta: float) -> void:
	if follow_traveling:
		follow_idle_seconds += delta
		if follow_idle_seconds >= 2.0 and not camera_drag_pending and not camera_drag_settling and not _camera_transition_active():
			camera.position = camera.position.lerp(follow_position, 1.0 - exp(-FOLLOW_RESPONSE * delta))
			# Подъезд уже раскрывает город до смены участка поездки.
			# Слежение продолжает этот переход, сохраняя городской масштаб.
			var follow_zoom := CITY_ZOOM.x if follow_in_city or arrival_focus_started else FOLLOW_ZOOM
			target_zoom = follow_zoom
			camera.zoom = camera.zoom.lerp(Vector2.ONE * follow_zoom, 1.0 - exp(-2.5 * delta))
			zoom_anchor = camera.position
			zoom_cursor = get_viewport_rect().size / 2.0
			camera.force_update_scroll()
	if camera_drag_settling and not _camera_transition_active():
		camera.position = camera.position.lerp(camera_drag_target, 1.0 - exp(-CAMERA_DRAG_RESPONSE * delta))
		if camera.position.distance_to(camera_drag_target) * camera.zoom.x < 0.1:
			camera.position = camera_drag_target
			camera_drag_settling = false
		zoom_anchor = camera.position
		zoom_cursor = get_viewport_rect().size / 2.0
		camera.force_update_scroll()
	if not _camera_transition_active() and absf(camera.zoom.x - target_zoom) > 0.0001:
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
	detail_alpha = smoothstep(DETAIL_START, DETAIL_FULL, camera.zoom.x)
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
	queue_redraw()


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
	target_zoom = clampf(target_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if camera.zoom.x < DETAIL_START or viewing_city_id.is_empty():
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
		queue_redraw()


func set_route(
	start_city_id: String,
	destination_city_id: String,
	start_location_id: String = "",
	destination_location_id: String = ""
) -> bool:
	active_route_ids = routes.find_route(start_city_id, destination_city_id)
	arrival_focus_started = false
	active_route_points.clear()
	trip_progress = 0.0
	if active_route_ids.is_empty():
		active_route_destination_city_id = ""
		active_route_destination_location_id = ""
		queue_redraw()
		return false
	active_route_destination_city_id = destination_city_id
	arrival_location_id = routes.arrival_location(start_city_id, destination_city_id)
	active_route_destination_location_id = destination_location_id
	if active_route_destination_location_id.is_empty():
		active_route_destination_location_id = arrival_location_id

	if start_city_id == destination_city_id:
		var city: Dictionary = routes.cities_by_id[start_city_id]
		var route_start_id := start_location_id
		if route_start_id.is_empty():
			route_start_id = city["entry_location_id"]
		var route_finish_id := destination_location_id
		if route_finish_id.is_empty():
			route_finish_id = city["entry_location_id"]
		active_route_points = routes.build_local_route(city, route_start_id, route_finish_id)
	else:
		local_route_points.clear()
		active_route_points = routes.build_intercity_route(start_city_id, start_location_id, destination_city_id)

	queue_redraw()
	return not active_route_ids.is_empty() and active_route_points.size() > 1


func set_route_visible(visible: bool) -> void:
	route_visible = visible
	queue_redraw()


func clear_route() -> void:
	active_route_ids.clear()
	active_route_points.clear()
	active_route_destination_city_id = ""
	active_route_destination_location_id = ""
	route_visible = false
	trip_progress = 0.0
	queue_redraw()


func set_route_selection_locked(locked: bool) -> void:
	route_selection_locked = locked


func set_trip_progress(progress: float) -> void:
	trip_progress = clampf(progress, 0.0, 1.0)
	if active_route_points.size() > 1:
		var displayed := _displayed_remaining_route()
		follow_position = displayed[0] if not displayed.is_empty() else _displayed_route_point(active_route_points[-1])
	if route_selection_locked and not arrival_focus_started and not active_route_destination_city_id.is_empty():
		var distance := RouteGeometry.length(active_route_points)
		var approach_distance := minf(180.0, distance * 0.25)
		if distance > 0.0 and distance * (1.0 - trip_progress) <= approach_distance:
			arrival_focus_started = true
			_focus_city(active_route_destination_city_id)
	queue_redraw()


func set_local_trip_progress(progress: float) -> void:
	if local_route_points.size() < 2:
		return
	local_trip_active = true
	local_trip_progress = clampf(progress, 0.0, 1.0)
	var origin: Vector2 = routes.cities_by_id[local_route_city_id]["position"]
	follow_position = origin.lerp(RouteGeometry.position_at(local_route_points, local_trip_progress), detail_alpha)
	queue_redraw()


func get_local_route_distance() -> float:
	return RouteGeometry.length(local_route_points)


func set_local_route(city_id: String, start_location_id: String, destination_location_id: String) -> bool:
	if not routes.cities_by_id.has(city_id):
		return false
	var city: Dictionary = routes.cities_by_id[city_id]
	local_route_city_id = city_id
	selected_place_id = destination_location_id
	local_route_points = routes.build_local_route(city, start_location_id, destination_location_id)
	local_trip_active = false
	local_trip_progress = 0.0
	queue_redraw()
	return local_route_points.size() > 1


func clear_local_route() -> void:
	selected_place_id = ""
	local_route_points.clear()
	local_trip_active = false
	local_trip_progress = 0.0
	queue_redraw()


# Начало жеста принимается только вне UI, продолжение — даже над панелями.
func _input(event: InputEvent) -> void:
	if not camera_drag_pending:
		return
	if event is InputEventMouseMotion:
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			camera_drag_pending = false
			camera_drag_active = false
			return
		if event.position.distance_to(camera_press_position) >= CAMERA_DRAG_THRESHOLD:
			camera_drag_active = true
		if camera_drag_active:
			follow_idle_seconds = 0.0
			_cancel_camera_transition()
			camera_drag_target = camera_press_camera_position - (event.position - camera_press_position) * CAMERA_DRAG_SENSITIVITY / camera.zoom
			camera_drag_settling = true
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		camera_drag_pending = false
		if not camera_drag_active:
			if view_mode == ViewMode.WORLD:
				_select_city_at(camera_press_world_position)
			else:
				_select_place_at(camera_press_world_position)
		camera_drag_active = false
		get_viewport().set_input_as_handled()


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


func _select_city_at(local_position: Vector2) -> bool:
	if route_selection_locked:
		return false
	var city_id := _find_city_at(local_position)
	if city_id.is_empty() or city_id == current_city_id:
		return false
	var city: Dictionary = routes.cities_by_id[city_id]
	city_selected.emit(city_id, city["name"])
	queue_redraw()
	return true


func _select_place_at(local_position: Vector2) -> bool:
	if route_selection_locked or detail_alpha < 0.75:
		return false
	# Выбор зависит от места клика: одновременно могут быть видны два города.
	for candidate in routes.cities:
		for place in candidate["places"]:
			if local_position.distance_to(candidate["position"] + place["position"] * detail_alpha) <= 24.0:
				viewing_city_id = candidate["id"]
	var city: Dictionary = routes.cities_by_id[viewing_city_id]
	local_route_city_id = viewing_city_id
	var city_origin: Vector2 = city["position"]
	var start_location_id := current_location_id
	if viewing_city_id != current_city_id:
		start_location_id = routes.arrival_location(current_city_id, viewing_city_id)
	for place in city["places"]:
		var place_position: Vector2 = city_origin + place["position"] * detail_alpha
		if local_position.distance_to(place_position) <= 24.0:
			if viewing_city_id == current_city_id:
				var current_node_id := routes.node_id_for_location(city, current_location_id)
				var place_node_id := routes.node_id_for_location(city, place["id"])
				if current_node_id == place_node_id:
					selected_place_id = ""
					local_route_points.clear()
					local_trip_active = false
					local_trip_progress = 0.0
					location_selected.emit(viewing_city_id, place["id"], place["name"], false)
					queue_redraw()
					return true
			selected_place_id = place["id"]
			local_route_points = routes.build_local_route(city, start_location_id, place["id"])
			local_trip_active = false
			local_trip_progress = 0.0
			location_selected.emit(
				viewing_city_id,
				place["id"],
				place["name"],
				local_route_points.size() > 1
			)
			queue_redraw()
			return true
	return false


func _draw() -> void:
	draw_rect(
		Rect2(camera.position - get_viewport_rect().size / camera.zoom, get_viewport_rect().size / camera.zoom * 2.0),
		WORLD_BACKGROUND
	)
	_draw_world()
	if detail_alpha > 0.0 and not viewing_city_id.is_empty():
		for city in routes.cities:
			_draw_city(city["id"])


func _draw_world() -> void:
	var displayed_route: Array[Vector2] = []
	if route_visible and active_route_points.size() > 1:
		displayed_route = _displayed_remaining_route()
	for road in routes.roads:
		var start := routes.road_endpoint(road["from"], road["to"])
		var finish := routes.road_endpoint(road["to"], road["from"])
		var start_is_city := routes.cities_by_id.has(road["from"])
		var finish_is_city := routes.cities_by_id.has(road["to"])
		# На общей карте дорога доходит под маркер; при приближении — до въезда.
		if start_is_city:
			start = routes.world_position_for_node(road["from"]).lerp(start, detail_alpha)
		if finish_is_city:
			finish = routes.world_position_for_node(road["to"]).lerp(finish, detail_alpha)
		var direction := start.direction_to(finish)
		var transition := minf(60.0, start.distance_to(finish) / 3.0)
		var inner_start := start + direction * transition
		var inner_finish := finish - direction * transition
		var street_width := lerpf(12.0, 5.0, detail_alpha)
		_draw_road_segment(start, inner_start, street_width if start_is_city else 12.0, 12.0, ROAD_COLOR)
		_draw_road_segment(inner_start, inner_finish, 12.0, 12.0, ROAD_COLOR)
		_draw_road_segment(inner_finish, finish, 12.0, street_width if finish_is_city else 12.0, ROAD_COLOR)

	if route_visible and active_route_points.size() > 1:
		_draw_dashed_route(displayed_route)

	for city in routes.cities:
		var city_position: Vector2 = city["position"]
		var is_current: bool = city["id"] == current_city_id
		var color := CURRENT_CITY_COLOR if is_current else CITY_COLOR
		var marker_alpha := 1.0 - smoothstep(0.0, 0.3, detail_alpha)
		draw_circle(city_position, 20.0, Color(color, marker_alpha))
		draw_circle(city_position, 8.0, Color(WORLD_BACKGROUND, marker_alpha))
		_draw_text(
			city_position + Vector2(-80.0, 48.0),
			city["name"],
			24,
			Color(CITY_COLOR, marker_alpha)
		)

	for junction in routes.road_junctions:
		var junction_position: Vector2 = junction["position"]
		draw_circle(junction_position, 8.0, ROAD_COLOR)
		draw_circle(junction_position, 3.0, WORLD_BACKGROUND)

	if route_visible and active_route_points.size() > 1:
		var marker_position := displayed_route[0] if not displayed_route.is_empty() else _displayed_route_point(active_route_points[-1])
		draw_rect(
			Rect2(marker_position - Vector2(10.0, 10.0), Vector2(20.0, 20.0)),
			WORLD_MARKER_COLOR
		)


func _displayed_route_point(point: Vector2) -> Vector2:
	# Уличные узлы схлопываются в маркер города на общем масштабе.
	for city in routes.cities:
		var origin: Vector2 = city["position"]
		for node in city["street_nodes"]:
			if point.distance_squared_to(origin + node["position"]) < 0.0001:
				return origin.lerp(point, detail_alpha)
	return point


func _displayed_remaining_route() -> Array[Vector2]:
	var result: Array[Vector2] = []
	var remaining_distance := RouteGeometry.length(active_route_points) * trip_progress
	for index in range(active_route_points.size() - 1):
		var start := active_route_points[index]
		var finish := active_route_points[index + 1]
		var length := start.distance_to(finish)
		if length <= 0.0001:
			continue
		if remaining_distance > length:
			remaining_distance -= length
			continue
		if result.is_empty():
			result.append(_displayed_route_point(start).lerp(_displayed_route_point(finish), remaining_distance / length))
		result.append(_displayed_route_point(finish))
		remaining_distance = 0.0
	return result


func _draw_city(city_id: String) -> void:
	if not routes.cities_by_id.has(city_id):
		return

	var city: Dictionary = routes.cities_by_id[city_id]
	var origin: Vector2 = city["position"]
	var interactive := city_id == current_city_id
	var places_alpha := smoothstep(0.55, 0.95, detail_alpha)
	var street_width := 5.0 * detail_alpha

	for street_road in city["street_roads"]:
		var start := origin + routes.street_node_position(city, street_road["from"]) * detail_alpha
		var finish := origin + routes.street_node_position(city, street_road["to"]) * detail_alpha
		_draw_road_segment(start, finish, street_width, street_width, ROAD_COLOR)

	# Подъезд заканчивается в центре маркера, даже если здание смещено от узла.
	for place in city["places"]:
		var road_position := origin + routes.street_node_position(city, place["road_node_id"]) * detail_alpha
		var place_position: Vector2 = origin + place["position"] * detail_alpha
		_draw_road_segment(road_position, place_position, street_width, street_width, ROAD_COLOR)

	if (
		route_visible
		and active_route_ids.size() > 1
		and city_id == active_route_destination_city_id
	):
		var destination_city_route := routes.build_local_route(
			city,
			arrival_location_id,
			active_route_destination_location_id
		)
		_draw_dashed_route(_fold_city_points(destination_city_route, origin), places_alpha)

	if local_route_points.size() > 1 and local_route_city_id == city_id:
		var progress := local_trip_progress if local_trip_active else 0.0
		_draw_dashed_route(_fold_city_points(RouteGeometry.remaining_points(local_route_points, progress), origin), places_alpha)

	for place in city["places"]:
		var place_position: Vector2 = origin + place["position"] * detail_alpha
		var place_color := PLACE_COLOR
		var half_size := Vector2(7.0, 7.0)
		if place["id"] == selected_place_id:
			place_color = SELECTED_PLACE_COLOR
			half_size = Vector2(10.0, 10.0)
		elif not interactive:
			place_color = CITY_COLOR
		draw_rect(Rect2(place_position - half_size * detail_alpha, half_size * 2.0 * detail_alpha), Color(place_color, places_alpha))
		_draw_text(
			place_position + Vector2(12.0, 5.0),
			place["name"],
			12,
			Color(CITY_COLOR, places_alpha)
		)

	if interactive:
		var player_position := routes.position_for_location(city, current_location_id)
		if local_trip_active:
			player_position = RouteGeometry.position_at(local_route_points, local_trip_progress)
		player_position = origin.lerp(player_position, detail_alpha)
		draw_circle(player_position, 11.0, Color(PLAYER_MARKER_COLOR, places_alpha))
		draw_circle(player_position, 4.0, Color(WORLD_BACKGROUND, places_alpha))

	var city_name := str(city["name"])
	if not interactive:
		city_name += " — просмотр"
	_draw_text(origin + Vector2(-70.0, -105.0) * detail_alpha, city_name, 16, Color(CURRENT_CITY_COLOR, places_alpha))


func _fold_city_points(points: Array[Vector2], origin: Vector2) -> Array[Vector2]:
	var folded: Array[Vector2] = []
	for point in points:
		folded.append(origin.lerp(point, detail_alpha))
	return folded


func _draw_road_segment(start: Vector2, finish: Vector2, start_width: float, finish_width: float, color: Color) -> void:
	if start.is_equal_approx(finish):
		return
	var normal := start.direction_to(finish).orthogonal()
	draw_colored_polygon(PackedVector2Array([
		start + normal * start_width / 2.0,
		finish + normal * finish_width / 2.0,
		finish - normal * finish_width / 2.0,
		start - normal * start_width / 2.0,
	]), color)
	# Круглые окончания одновременно закрывают стыки соседних участков.
	draw_circle(start, start_width / 2.0, color, true, -1.0, true)
	draw_circle(finish, finish_width / 2.0, color, true, -1.0, true)


func _draw_dashed_route(points: Array[Vector2], opacity: float = 1.0) -> void:
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
			var dash_end := minf(distance + ROUTE_DASH_LENGTH, segment_length)
			draw_line(
				start + direction * distance,
				start + direction * dash_end,
				Color(ROUTE_COLOR, opacity),
				3.5,
				true
			)
			distance += ROUTE_DASH_LENGTH + ROUTE_GAP_LENGTH


func _draw_text(position: Vector2, text: String, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _show_world_view() -> void:
	view_mode = ViewMode.WORLD
	viewing_city_id = ""
	selected_place_id = ""
	local_route_points.clear()
	local_trip_active = false
	local_trip_progress = 0.0
	trackpad_scroll_accumulator = 0.0
	camera.position = WorldMapData.WORLD_CENTER
	camera.zoom = WORLD_ZOOM
	target_zoom = WORLD_ZOOM.x
	zoom_anchor = camera.position
	zoom_cursor = get_viewport_rect().size / 2.0
	city_view_changed.emit("", "Общий вид", false)
	queue_redraw()


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
	queue_redraw()


func _camera_transition_active() -> bool:
	return camera_transition != null and camera_transition.is_running()


func set_follow_traveling(traveling: bool, in_city: bool = false) -> void:
	if traveling != follow_traveling:
		follow_idle_seconds = 2.0 if traveling else 0.0
		if traveling:
			_cancel_camera_transition()
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
	target_zoom = CITY_ZOOM.x
	zoom_anchor = destination
	zoom_cursor = get_viewport_rect().size / 2.0
	camera_transition = create_tween().set_parallel(true)
	camera_transition.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	camera_transition.tween_property(camera, "position", destination, 1.8)
	camera_transition.tween_property(camera, "zoom", CITY_ZOOM, 1.8)


func _find_city_at(local_position: Vector2) -> String:
	for city in routes.cities:
		var city_position: Vector2 = city["position"]
		if local_position.distance_to(city_position) <= 40.0:
			return city["id"]
	return ""
