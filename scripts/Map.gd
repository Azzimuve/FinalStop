extends Node2D

const RoutePlanner = preload("res://scripts/map/RoutePlanner.gd")
const RouteGeometry = preload("res://scripts/map/RouteGeometry.gd")
const WorldMapData = preload("res://scripts/WorldMapData.gd")

signal city_view_changed(city_id: String, city_name: String, interactive: bool)
signal city_selected(city_id: String, city_name: String)
signal location_selected(city_id: String, place_id: String, place_name: String, route_available: bool)

const WORLD_ZOOM := Vector2(0.55, 0.55)
const CITY_ZOOM := Vector2(1.4, 1.4)
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
var local_trip_progress: float = 0.0
var local_trip_active: bool = false
var trackpad_scroll_accumulator: float = 0.0
var route_selection_locked: bool = false

const CAMERA_DRAG_THRESHOLD: float = 5.0
var camera_drag_pending: bool = false
var camera_drag_active: bool = false
var camera_press_position: Vector2
var camera_press_world_position: Vector2
var camera_press_camera_position: Vector2



func _ready() -> void:
	set_process_unhandled_input(true)
	camera.make_current()
	_show_world_view()


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
	active_route_points.clear()
	trip_progress = 0.0
	if active_route_ids.is_empty():
		active_route_destination_city_id = ""
		active_route_destination_location_id = ""
		queue_redraw()
		return false
	active_route_destination_city_id = destination_city_id
	var destination_city: Dictionary = routes.cities_by_id[destination_city_id]
	active_route_destination_location_id = destination_location_id
	if active_route_destination_location_id.is_empty():
		active_route_destination_location_id = destination_city["entry_location_id"]

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
		for road_node_id in active_route_ids:
			_append_route_point(routes.world_position_for_node(road_node_id))

	queue_redraw()
	return not active_route_ids.is_empty() and active_route_points.size() > 1


func _append_route_point(point: Vector2) -> void:
	if active_route_points.is_empty() or active_route_points[-1].distance_to(point) > 0.01:
		active_route_points.append(point)


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
	queue_redraw()


func set_local_trip_progress(progress: float) -> void:
	if local_route_points.size() < 2:
		return
	local_trip_active = true
	local_trip_progress = clampf(progress, 0.0, 1.0)
	queue_redraw()


func get_local_route_distance() -> float:
	return RouteGeometry.length(local_route_points)


func set_local_route(city_id: String, start_location_id: String, destination_location_id: String) -> bool:
	if not routes.cities_by_id.has(city_id):
		return false
	var city: Dictionary = routes.cities_by_id[city_id]
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
			camera.position = camera_press_camera_position - (event.position - camera_press_position) / camera.zoom
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
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and view_mode == ViewMode.WORLD:
		if _zoom_into_city_at(local_position):
			get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and view_mode == ViewMode.CITY:
		_show_world_view()
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		camera_drag_pending = true
		camera_drag_active = false
		camera_press_position = event.position
		camera_press_world_position = local_position
		camera_press_camera_position = camera.position
		get_viewport().set_input_as_handled()


func _handle_pan_gesture(event: InputEventPanGesture) -> void:
	if absf(event.delta.y) < 0.1:
		return

	trackpad_scroll_accumulator += event.delta.y
	if trackpad_scroll_accumulator <= -TRACKPAD_SCROLL_THRESHOLD:
		trackpad_scroll_accumulator = 0.0
		if view_mode == ViewMode.WORLD and _zoom_into_city_at(_event_to_local(event.position)):
			get_viewport().set_input_as_handled()
	elif trackpad_scroll_accumulator >= TRACKPAD_SCROLL_THRESHOLD:
		trackpad_scroll_accumulator = 0.0
		if view_mode == ViewMode.CITY:
			_show_world_view()
			get_viewport().set_input_as_handled()


func _handle_magnify_gesture(event: InputEventMagnifyGesture) -> void:
	if event.factor > 1.001 and view_mode == ViewMode.WORLD:
		if _zoom_into_city_at(_event_to_local(event.position)):
			get_viewport().set_input_as_handled()
	elif event.factor < 0.999 and view_mode == ViewMode.CITY:
		_show_world_view()
		get_viewport().set_input_as_handled()


func _event_to_local(viewport_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_position


func _zoom_into_city_at(local_position: Vector2) -> bool:
	if view_mode != ViewMode.WORLD:
		return false
	var city_id := _find_city_at(local_position)
	if city_id.is_empty():
		return false
	_show_city_view(city_id)
	return true


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
	if route_selection_locked:
		return false
	var city: Dictionary = routes.cities_by_id[viewing_city_id]
	var city_origin: Vector2 = city["position"]
	var start_location_id := current_location_id
	if viewing_city_id != current_city_id:
		start_location_id = city["entry_location_id"]
	for place in city["places"]:
		var place_position: Vector2 = city_origin + place["position"]
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
		Rect2(Vector2(-100.0, -100.0), Vector2(1400.0, 900.0)),
		WORLD_BACKGROUND
	)
	if view_mode == ViewMode.WORLD:
		_draw_world()
	else:
		_draw_city(viewing_city_id)


func _draw_world() -> void:
	for road in routes.roads:
		var start := routes.world_position_for_node(road["from"])
		var finish := routes.world_position_for_node(road["to"])
		draw_line(start, finish, ROAD_COLOR, 12.0, true)

	if route_visible and active_route_points.size() > 1:
		_draw_dashed_route(RouteGeometry.remaining_points(active_route_points, trip_progress))

	for city in routes.cities:
		var city_position: Vector2 = city["position"]
		var is_current: bool = city["id"] == current_city_id
		var color := CURRENT_CITY_COLOR if is_current else CITY_COLOR
		draw_circle(city_position, 20.0, color)
		draw_circle(city_position, 8.0, WORLD_BACKGROUND)
		_draw_text(
			city_position + Vector2(-80.0, 48.0),
			city["name"],
			24,
			CITY_COLOR
		)

	for junction in routes.road_junctions:
		var junction_position: Vector2 = junction["position"]
		draw_circle(junction_position, 8.0, ROAD_COLOR)
		draw_circle(junction_position, 3.0, WORLD_BACKGROUND)

	if route_visible and active_route_points.size() > 1:
		draw_rect(
			Rect2(RouteGeometry.position_at(active_route_points, trip_progress) - Vector2(10.0, 10.0), Vector2(20.0, 20.0)),
			WORLD_MARKER_COLOR
		)


func _draw_city(city_id: String) -> void:
	if not routes.cities_by_id.has(city_id):
		return

	var city: Dictionary = routes.cities_by_id[city_id]
	var origin: Vector2 = city["position"]
	var interactive := city_id == current_city_id

	for street_road in city["street_roads"]:
		var start := origin + routes.street_node_position(city, street_road["from"])
		var finish := origin + routes.street_node_position(city, street_road["to"])
		draw_line(start, finish, ROAD_COLOR, 5.0, true)

	if (
		route_visible
		and active_route_ids.size() > 1
		and city_id == active_route_destination_city_id
	):
		var destination_city_route := routes.build_local_route(
			city,
			city["entry_location_id"],
			active_route_destination_location_id
		)
		_draw_dashed_route(destination_city_route)

	if local_route_points.size() > 1:
		var progress := local_trip_progress if local_trip_active else 0.0
		_draw_dashed_route(RouteGeometry.remaining_points(local_route_points, progress))

	for place in city["places"]:
		var place_position: Vector2 = origin + place["position"]
		var place_color := PLACE_COLOR
		var half_size := Vector2(7.0, 7.0)
		if place["id"] == selected_place_id:
			place_color = SELECTED_PLACE_COLOR
			half_size = Vector2(10.0, 10.0)
		elif not interactive:
			place_color = CITY_COLOR
		draw_rect(Rect2(place_position - half_size, half_size * 2.0), place_color)
		_draw_text(
			place_position + Vector2(12.0, 5.0),
			place["name"],
			12,
			CITY_COLOR
		)

	if interactive or local_trip_active:
		var player_position := routes.position_for_location(city, current_location_id)
		if local_trip_active:
			player_position = RouteGeometry.position_at(local_route_points, local_trip_progress)
		draw_circle(player_position, 11.0, PLAYER_MARKER_COLOR)
		draw_circle(player_position, 4.0, WORLD_BACKGROUND)

	var city_name := str(city["name"])
	if not interactive:
		city_name += " — просмотр"
	_draw_text(origin + Vector2(-70.0, -105.0), city_name, 16, CURRENT_CITY_COLOR)


func _draw_dashed_route(points: Array[Vector2]) -> void:
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
				ROUTE_COLOR,
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
	camera.position = city["position"] + Vector2(-100.0, 0.0)
	camera.zoom = CITY_ZOOM
	city_view_changed.emit(
		city_id,
		city["name"],
		city_id == current_city_id
	)
	queue_redraw()


func _find_city_at(local_position: Vector2) -> String:
	for city in routes.cities:
		var city_position: Vector2 = city["position"]
		if local_position.distance_to(city_position) <= 40.0:
			return city["id"]
	return ""
