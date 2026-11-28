extends SceneTree

# Запуск из корня проекта: godot --headless --fixed-fps 60 --script scripts/tests/RouteRegression.gd
const STEP := 1.0 / 60.0
var game
var map
var failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		printerr(description)


func _click(point: Vector2, append := false) -> void:
	var screen: Vector2 = map.get_global_transform_with_canvas() * point
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = screen
		event.shift_pressed = append
		event.pressed = down
		root.push_input(event, true)


func _place(city: String, id: String) -> Vector2:
	var data: Dictionary = map.routes.cities_by_id[city]
	for place in data.places:
		if place.id == id:
			return data.position + place.position * map.detail_alpha
	return Vector2.INF


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	change_scene_to_file("res://scenes/tests/CustomRouteTest.tscn")
	await scene_changed
	game = current_scene.game
	map = game.map_view
	await process_frame
	game.set_process(false)
	map.set_process(false)
	map._process(STEP)

	var city := "nearby_settlement"
	var fuel := _place(city, "settlement_fuel_station")
	var delivery := _place(city, "settlement_delivery")
	var shop := _place(city, "settlement_shop")
	var off_road: Vector2 = map.routes.cities_by_id[city].position + Vector2(-75, -55)
	_click(off_road)
	_click(off_road, true)
	_check(not game.route_available, "Клик вне дороги не должен выбирать цель.")
	_click(fuel)
	_click(delivery, true)
	_click(shop, true)
	_check(game.route_target_location_id == "settlement_shop" and map.waypoints.size() == 2, "Shift должен продлевать маршрут.")
	_check(map.waypoints == [map.waypoint_router.location(city, "settlement_fuel_station"), map.waypoint_router.location(city, "settlement_delivery")], "Порядок остановок должен совпадать с порядком кликов.")
	_click(off_road)
	_click(off_road, true)
	_check(map.waypoints.size() == 2, "Клик вне дороги не должен менять существующий маршрут.")
	_click(delivery)
	_check(game.route_target_location_id == "settlement_delivery" and map.waypoints.is_empty(), "ЛКМ должен сбрасывать предыдущие точки.")

	game._on_travel_pressed()
	for frame in 12:
		game._process(STEP)
		map._process(STEP)
	game._on_pause_pressed()
	var position_before: Vector2 = map.vehicle.position
	var fuel_before: float = game.vehicle.fuel_liters
	var time_before: float = game.clock.total_minutes
	_click(_place(city, "settlement_fuel_station"), true)
	_check(game.travel_paused and map.waypoints.size() == 1, "На остановке можно продлить путь.")
	_click(_place(city, "settlement_shop"))
	_check(game.travel_paused and map.waypoints.is_empty(), "На остановке ЛКМ строит новый путь.")
	_check(position_before.distance_to(map.vehicle.position) < 0.01 and game.vehicle.fuel_liters == fuel_before and game.clock.total_minutes == time_before, "Редактирование должно сохранять позицию, горючее и время.")

	game._on_pause_pressed()
	for frame in 300:
		game._process(STEP)
		map._process(STEP)
		if not game._is_trip_active():
			break
	_check(game.current_location_id == "settlement_shop" and not game._is_trip_active(), "Поездка должна закончиться на последней выбранной точке.")

	_check_street_selection()
	_check_city_markers()
	_check_city_approaches()
	# Участок из гаража к западной развилке растягивается сильнее всего
	# на общей карте. В Даунтауне само сворачивание смещает дорогу вперёд.
	_check_exit("company_city", "company_garage", "northern_settlement", "northern_settlement_hotel", 0.55)
	_check_exit("city_3", "Sklad", "city_1", "Shop_Zalupki", 1.4)
	if failures.is_empty():
		print("PASS — маршруты по городам и точкам интереса, остановка и скорость выезда.")
	quit(int(not failures.is_empty()))


func _check_street_selection() -> void:
	var city: Dictionary = map.routes.cities_by_id.nearby_settlement
	var towards_entry: Vector2 = city.position + Vector2(-75, -25)
	var near_shop: Vector2 = city.position + Vector2(22, -80)
	var near_fuel: Vector2 = city.position + Vector2(-48, 31)
	var fuel: Dictionary = map.waypoint_router.location(city.id, "settlement_fuel_station")
	var delivery: Dictionary = map.waypoint_router.location(city.id, "settlement_delivery")
	_click(near_shop, true)
	_check(game.route_target_location_id == "settlement_delivery" and map.waypoints.is_empty(), "Первый Shift-клик от магазина должен продолжить дорогу от машины до пункта доставки.")
	_click(_place(city.id, "settlement_fuel_station"))
	# Без магазина в конце этой улицы остаётся тупик.
	var shop_node: int = map.waypoint_router.junctions[[city.id, "settlement_shop_road"]]
	var shop: Dictionary = map.waypoint_router.destinations[shop_node]
	map.waypoint_router.destinations.erase(shop_node)
	var before_dead_end: Dictionary = map.custom_path
	_click(near_shop, true)
	_check(is_same(before_dead_end, map.custom_path) and game.route_target_location_id == "settlement_fuel_station", "Тупик без объекта должен сохранить прежний маршрут.")
	map.waypoint_router.destinations[shop_node] = shop

	_click(near_fuel, true)
	_check(game.route_target_location_id == "settlement_delivery" and map.waypoints == [fuel], "Shift от заправки должен провести через перекрёсток к пункту доставки, даже когда место клика ближе к заправке.")
	_check(map.custom_finish.edge == delivery.edge and is_equal_approx(map.custom_finish.offset, delivery.offset) and not map.custom_path.points.has(near_fuel), "Финиш должен стоять на объекте, координата клика не должна становиться остановкой.")
	_click(near_fuel, true)
	_check(game.route_target_location_id == "settlement_fuel_station" and map.waypoints.size() == 2, "При подходе с противоположной стороны та же дорога должна вести к заправке.")

	_click(_place(city.id, "settlement_fuel_station"))
	_click(towards_entry, true)
	_check(game.route_target_location_id == city.entry_location_id, "Ближайшей целью на улице может быть въезд в город.")
	_check(map.waypoints == [fuel], "Предыдущий финиш должен стать единственной промежуточной остановкой.")
	_click(_place(city.id, "settlement_delivery"), true)
	game._remove_waypoint(1)
	_check(map.waypoints == [fuel], "Удаление въезда должно убрать и проезд по связанной с ним дороге.")

	_click(near_shop)
	_check(game.route_target_location_id == "settlement_shop" and map.waypoints.size() == 1, "ЛКМ по дороге должен начать новый маршрут от машины.")
	_check(is_equal_approx(map.route_distance, 36.0), "Из магазина нужно проехать 18 единиц до места клика и вернуться в магазин.")
	_check(map.custom_path.points.has(near_shop), "Маршрут должен проходить по выбранному участку.")
	game._on_travel_pressed()
	for frame in 300:
		game._process(STEP)
		map._process(STEP)
		if game.local_trip.active and map.local_trip_progress > 0.6 and not map.waypoints.is_empty():
			game._on_pause_pressed()
			var before: Vector2 = map.vehicle.position
			_click(_place(city.id, "settlement_delivery"), true)
			_check(map.waypoints == [map.waypoint_router.location(city.id, "settlement_shop")] and before.distance_to(map.vehicle.position) < 0.01, "После остановки пройденный участок дороги должен остаться позади.")
			break
		if not game._is_trip_active():
			break
	_check(game.travel_paused, "Машина должна проехать точку клика и начать обратный путь.")
	if game.travel_paused:
		game._on_pause_pressed()
	for frame in 600:
		game._process(STEP)
		map._process(STEP)
		if not game._is_trip_active():
			break
	_check(not game._is_trip_active() and game.current_location_id == "settlement_delivery", "Продлённый маршрут должен закончиться у нового объекта.")

	_click(_place(city.id, "settlement_fuel_station"))
	_click(near_fuel, true)
	game._on_travel_pressed()
	var paused_after_road := false
	for frame in 1200:
		game._process(STEP)
		map._process(STEP)
		if not game.local_trip.active:
			break
		if map._travelled_distance() <= map.custom_path.exit_distances[-1] + 5.0:
			continue
		game._on_pause_pressed()
		var before: Vector2 = map.vehicle.position
		var remaining: float = map.route_distance - map._travelled_distance()
		_click(_place(city.id, "settlement_shop"), true)
		paused_after_road = true
		_check(before.distance_to(map.vehicle.position) < 0.01 and map.waypoints == [delivery], "На паузе пройденная дорога должна остаться позади, а её финиш остаться в плане.")
		_check(is_equal_approx(map.custom_path.waypoint_distances[0], remaining), "Машина должна доехать до пункта доставки без возврата к выбранной дороге.")
		game._on_pause_pressed()
		break
	_check(paused_after_road, "Машина должна проехать выбранную дорогу до остановки.")
	for frame in 1200:
		game._process(STEP)
		map._process(STEP)
		if not game._is_trip_active():
			break


func _check_city_markers() -> void:
	var north: Dictionary = map.routes.cities_by_id.northern_settlement
	var nearby: Dictionary = map.routes.cities_by_id.nearby_settlement
	map._cancel_camera_transition()
	map.camera.position = (north.position + nearby.position) * 0.5
	map.camera.zoom = map.world_zoom
	map.target_zoom = map.world_zoom.x
	map._process(STEP)
	var camera_position: Vector2 = map.camera.position

	_click(north.position + Vector2(29, 0))
	_check(not game.route_available, "Клик за краем значка города не должен выбирать цель.")
	var highway: Vector2 = nearby.position.lerp(north.position, 0.08)
	_click(highway)
	_check(game.route_target_location_id == "settlement_shop", "С трассы на свёрнутой карте должна выбираться и ближайшая городская точка интереса.")
	_check(map.waypoints.size() == 1 and map.waypoint_router.position(map.waypoints[0], map.world.display_route_point).distance_to(highway) < 0.05, "Проезд должен совпасть с видимой трассой при свёрнутом городе.")
	_click(nearby.position)
	_click(highway, true)
	_check(game.route_target_city_id == north.id and map.waypoints == [map.waypoint_router.location(nearby.id, nearby.entry_location_id)], "Shift по трассе у своего посёлка должен вести в следующий посёлок по выбранной трассе.")
	var highway_hit: Dictionary = map.waypoint_router.pick_road(map.to_global(highway))
	var distance_on_highway := 0.0
	for i in map.custom_path.segments.size():
		var arc: Dictionary = map.custom_path.segments[i]
		if map.custom_path.road_offsets[i] >= map.custom_path.waypoint_distances[0] and arc.edge == highway_hit.edge:
			_check(arc.end > arc.start, "На выбранной трассе не должно быть разворота.")
			distance_on_highway += arc.end - arc.start
	_check(is_equal_approx(distance_on_highway, map.waypoint_router.roads[highway_hit.edge].length), "Трассу нужно пройти целиком, даже когда есть другой путь.")
	_click(north.position)
	_check(game.route_available and game.route_target_city_id == north.id and game.route_target_location_id == north.entry_location_id, "ЛКМ по городу должен выбрать его въезд.")
	_click(nearby.position, true)
	_check(game.route_target_city_id == nearby.id and game.route_target_location_id == nearby.entry_location_id and map.waypoints == [map.waypoint_router.location(north.id, north.entry_location_id)], "Shift должен добавить город после прежнего финиша.")
	_click(north.position)
	_check(game.route_target_city_id == north.id and map.waypoints.is_empty(), "ЛКМ по городу должен заменить всю цепочку.")
	_check(not map._camera_transition_active() and map.target_zoom == map.world_zoom.x and map.camera.position == camera_position, "Выбор города должен сохранять общий вид.")

	game._on_travel_pressed()
	for frame in 2400:
		game._process(STEP)
		map._process(STEP)
		if not game._is_trip_active():
			break
	_check(not game._is_trip_active() and game.current_city_id == north.id and game.current_location_id == north.entry_location_id, "Поездка до города должна завершиться у назначенного въезда.")
	_check_parked_zoom()


func _check_parked_zoom() -> void:
	var screen_offset: Vector2 = (map.vehicle.position - map.camera.position) * map.camera.zoom
	for frame in 150:
		if map._camera_transition_active():
			map.camera_transition.custom_step(STEP)
		map._process(STEP)
	var after: Vector2 = (map.vehicle.position - map.camera.position) * map.camera.zoom
	_check(is_equal_approx(map.camera.zoom.x, map.city_zoom.x) and after.distance_to(screen_offset) < 0.1, "После прибытия камера должна завершить приближение, сохранив машину на месте в кадре.")


func _check_city_approaches() -> void:
	game._on_location_selected("nearby_settlement", "settlement_shop", "Магазин")
	game._on_location_selected("city_1", "Shop_Zalupki", "Магазин в Нижних залупках", true)
	game._on_travel_pressed()
	var plan: Dictionary = map.custom_path
	var opened_at_entry := false
	var folded_after_exit := false
	var took_bypass := false
	var focused_on_bypass := false
	for frame in 3600:
		game._process(STEP)
		map._process(STEP)
		if not game._is_trip_active():
			break
		var distance: float = map.trip_progress * map.route_distance
		var index := clampi(plan.road_offsets.bsearch(distance) - 1, 0, plan.segments.size() - 1)
		var road = map.waypoint_router.roads[plan.segments[index].edge]
		if road.city == "nearby_settlement" and distance <= plan.waypoint_distances[0]:
			if not opened_at_entry:
				_check(map.detail_alpha >= 0.75, "При въезде в промежуточный посёлок улицы должны уже быть видны.")
			opened_at_entry = true
		if road.highway == "Highway2" and map.detail_alpha < 0.05:
			folded_after_exit = true
		if road.highway == "Road4":
			took_bypass = true
			focused_on_bypass = focused_on_bypass or map.arrival_focus_started
	_check(opened_at_entry and folded_after_exit, "Маршрут должен раскрыть промежуточный город и вернуть общий вид на следующей трассе.")
	_check(took_bypass and not focused_on_bypass, "Проезд мимо въезда в Даунтаун по трассе должен сохранить общий вид.")
	_check(not game._is_trip_active() and game.current_location_id == "Shop_Zalupki", "После проезда через города машина должна доехать до конечного магазина.")
	_check_parked_zoom()


func _check_exit(city: String, place: String, destination_city: String, destination: String, zoom: float) -> void:
	game.intercity_trip.active = false
	map.set_route_selection_locked(false)
	map.set_follow_traveling(false)
	map.route_editable = true
	game.current_city_id = city
	game.current_location_id = place
	map.set_current_location(city, place, false)
	map.clear_route()
	map._cancel_camera_transition()
	map.camera.position = map.routes.cities_by_id[city].position
	map.camera.zoom = Vector2.ONE * zoom
	map.target_zoom = zoom
	map._process(STEP)
	game._on_location_selected(destination_city, destination, destination)
	game._on_travel_pressed()
	var peak := 0.0
	var min_detail: float = map.detail_alpha
	for frame in 2400:
		var before: Vector2 = map.vehicle.position
		game._process(STEP)
		map._process(STEP)
		if map.arrival_focus_started or not game.intercity_trip.active:
			break
		peak = maxf(peak, before.distance_to(map.vehicle.position) / STEP)
		min_detail = minf(min_detail, map.detail_alpha)
	_check(min_detail < 0.05, "До подъезда к финишу город должен успеть свернуться.")
	_check(peak > 0.0 and peak <= game.vehicle.base_speed + 0.2, "Скачок скорости на выезде из %s: %.2f" % [city, peak])
