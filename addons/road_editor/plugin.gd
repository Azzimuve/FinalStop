@tool
extends EditorPlugin

const MapRoad = preload("res://scripts/world/MapRoad.gd")
const MapPoint = preload("res://scripts/world/MapPoint.gd")
const MapCity = preload("res://scripts/world/MapCity.gd")
const WorldMapData = preload("res://scripts/WorldMapData.gd")
const ROAD_SCENE = preload("res://scenes/world/Road.tscn")
const POINT_SCENE = preload("res://scenes/world/RoadPoint.tscn")
const MapPanel = preload("res://addons/road_editor/MapPanel.gd")
const TOOLBAR_PATH := "res://addons/road_editor/Toolbar.tscn"
const PICK_RADIUS := 12.0
const ACCENT := Color(0.3, 0.88, 0.85)

var map_panel: MapPanel
var toolbar: Control
var mode_select: OptionButton
var surface_select: OptionButton
var width_input: SpinBox
var hint: Label
var mode: int = 0
var chain_start: Node2D
var selected_road: MapRoad
var selected_point: int = -1
var mouse_position := Vector2.ZERO
var drag_kind: String = ""
var drag_index: int = -1
var drag_curve_before: Curve2D
var drag_curve_work: Curve2D
var drag_node: Node2D
var drag_node_before := Vector2.ZERO


func _enter_tree() -> void:
	# При повторном включении плагина подхватываем обновлённую сцену панели.
	var toolbar_scene := ResourceLoader.load(TOOLBAR_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	toolbar = toolbar_scene.instantiate()
	mode_select = toolbar.get_node("Content/Tools/Mode")
	surface_select = toolbar.get_node("Content/Tools/Surface")
	width_input = toolbar.get_node("Content/Tools/Width")
	hint = toolbar.get_node("Content/Hint")
	mode_select.item_selected.connect(_set_mode)
	toolbar.get_node("Content/Tools/Apply").pressed.connect(_apply_settings)
	toolbar.get_node("Content/Tools/Straighten").pressed.connect(_straighten)
	toolbar.get_node("Content/Tools/DeletePoint").pressed.connect(_delete_curve_point)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_BOTTOM, toolbar)
	scene_changed.connect(_scene_changed)
	EditorInterface.get_selection().selection_changed.connect(_selection_changed)
	get_undo_redo().version_changed.connect(_history_changed)
	map_panel = MapPanel.new()
	map_panel.setup(self, toolbar)
	_scene_changed(EditorInterface.get_edited_scene_root())


func _exit_tree() -> void:
	if map_panel != null:
		map_panel.cleanup()
	_cancel_drag()
	EditorInterface.get_selection().selection_changed.disconnect(_selection_changed)
	get_undo_redo().version_changed.disconnect(_history_changed)
	remove_control_from_container(CONTAINER_CANVAS_EDITOR_BOTTOM, toolbar)
	toolbar.queue_free()


func _handles(object: Object) -> bool:
	return object is Node2D and _scope() != null


func _edit(object: Object) -> void:
	if object is MapRoad and _roads().has(object):
		selected_road = object
		_sync_settings()
	update_overlays()


func _scope() -> Node2D:
	var root := EditorInterface.get_edited_scene_root()
	return root as Node2D if root is MapCity or root is WorldMapData else null


func _scene_changed(_root: Node) -> void:
	_cancel_drag()
	chain_start = null
	selected_road = null
	selected_point = -1
	mode = 0
	mode_select.select(0)
	if map_panel != null:
		map_panel.scene_changed()
	toolbar.visible = _scope() != null
	if _scope() != null:
		width_input.value = 12.0 if _scope() is WorldMapData else 5.0
	_set_hint()
	update_overlays()


func _selection_changed() -> void:
	if map_panel != null:
		map_panel.refresh()
	_cancel_drag()
	selected_road = null
	selected_point = -1
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is MapRoad and _roads().has(node):
			selected_road = node
			_sync_settings()
			break
	update_overlays()


func _sync_settings() -> void:
	if is_instance_valid(selected_road):
		surface_select.select(selected_road.surface)
		width_input.value = selected_road.road_width


func _history_changed() -> void:
	if map_panel != null:
		map_panel.refresh.call_deferred()
	if not is_instance_valid(selected_road) or not selected_road.is_inside_tree():
		selected_road = null
		selected_point = -1
	if not is_instance_valid(chain_start) or not chain_start.is_inside_tree():
		chain_start = null
	update_overlays()


func _set_mode(value: int) -> void:
	if map_panel != null:
		map_panel.cancel()
	_cancel_drag()
	mode = value
	mode_select.select(value)
	chain_start = null
	_set_hint()
	# Выбор корня включает обработку 2D-ввода даже в пустом выделении.
	if EditorInterface.get_selection().get_selected_nodes().is_empty() and _scope() != null:
		EditorInterface.get_selection().add_node(_scope())
	update_overlays()


func _set_hint(message: String = "") -> void:
	if not message.is_empty():
		hint.text = message
	elif mode == 1:
		hint.text = "ЛКМ: продолжить дорогу. Начните на выбранной дороге, чтобы вставить узел; курсор привязывается к линии. Esc / ПКМ: закончить цепочку."
	elif mode == 2:
		hint.text = "Тяните точки и направляющие; Shift: симметричные направляющие. Двойной щелчок по линии: добавить изгиб. Esc: закончить."
	else:
		hint.text = "Выбирайте дороги и точки на карте. Перемещение — инструментами Godot; покрытие и ширина — здесь или в Inspector."


func _canvas_transform() -> Transform2D:
	return EditorInterface.get_editor_viewport_2d().global_canvas_transform


func _screen_position(node: Node2D, local: Vector2 = Vector2.ZERO) -> Vector2:
	return _canvas_transform() * node.to_global(local)


func _local_position(node: Node2D, screen: Vector2) -> Vector2:
	return node.to_local(_canvas_transform().affine_inverse() * screen)


func _roads() -> Array[MapRoad]:
	var result: Array[MapRoad] = []
	var scope := _scope()
	if scope == null:
		return result
	var container := scope.get_node("Roads" if scope is WorldMapData else "Layout/Roads")
	for child in container.get_children():
		if child is MapRoad:
			result.append(child)
	return result


func _points() -> Array[MapPoint]:
	var result: Array[MapPoint] = []
	var scope := _scope()
	if scope == null:
		return result
	var containers: Array[Node] = []
	if scope is WorldMapData:
		containers.append(scope.get_node("Junctions"))
		for city in scope.get_node("Cities").get_children():
			if city is MapCity:
				result.append_array(city.get_entrance_points())
	else:
		containers.append(scope.get_node("Layout/Points"))
	for container in containers:
		for node in container.get_children():
			if node is MapPoint:
				result.append(node)
	return result


func _pick_point(screen: Vector2) -> MapPoint:
	var nearest: MapPoint
	var distance := PICK_RADIUS
	for point in _points():
		var candidate := _screen_position(point).distance_to(screen)
		if candidate < distance:
			distance = candidate
			nearest = point
	return nearest


func _pick_road(screen: Vector2) -> MapRoad:
	var nearest: MapRoad
	var distance := PICK_RADIUS
	for road in _roads():
		var points := road.path_points()
		for index in range(points.size() - 1):
			var a := _screen_position(road, points[index])
			var b := _screen_position(road, points[index + 1])
			var candidate := screen.distance_to(Geometry2D.get_closest_point_to_segment(screen, a, b))
			if candidate < distance:
				distance = candidate
				nearest = road
	return nearest


func _select_node(node: Node) -> void:
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(node)
	EditorInterface.edit_node(node)


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if _scope() == null or map_panel == null:
		return false
	if map_panel.handle_input(event):
		return true
	if is_instance_valid(map_panel.preview_copy):
		return false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and mode != 0:
		_cancel_drag()
		chain_start = null
		_set_mode(0)
		return true
	if event is InputEventMouseMotion:
		mouse_position = event.position
		if not drag_kind.is_empty():
			_drag_to(event.position, event.shift_pressed)
		update_overlays()
		return not drag_kind.is_empty()
	if not event is InputEventMouseButton:
		return false
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and mode != 0:
		_cancel_drag()
		chain_start = null
		_set_hint()
		update_overlays()
		return true
	# Колесо и средняя кнопка остаются у редактора для навигации.
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if not event.pressed:
		if not drag_kind.is_empty():
			_finish_drag()
			return true
		return mode != 0
	if event.alt_pressed or Input.is_key_pressed(KEY_SPACE):
		return false
	if mode == 1:
		if map_panel.connect_only and _pick_point(event.position) == null:
			_set_hint("Выберите существующий въезд или узел. Для новых развилок используйте «Рисовать».")
			return true
		var previous_start := chain_start
		_draw_next(event.position)
		if map_panel.connect_only and is_instance_valid(previous_start) and chain_start != previous_start:
			_set_mode(0)
		return true
	if mode == 2:
		if event.double_click:
			_insert_curve_point(event.position)
		elif not _begin_drag(event.position):
			var road := _pick_road(event.position)
			if road != null:
				_select_node(road)
		return true
	var point := _pick_point(event.position)
	if point != null:
		if _scope() is WorldMapData and point.get_parent() != _scope().get_node("Junctions"):
			_select_node(point)
			return true
		# После выбора стандартный инструмент Godot выполняет перемещение.
		if not EditorInterface.get_selection().get_selected_nodes().has(point):
			_select_node(point)
			return true
		return false
	var road := _pick_road(event.position)
	if road != null:
		_select_node(road)
		return true
	return false


func _unique_name(parent: Node, prefix: String) -> String:
	var index := 1
	while parent.has_node(prefix + str(index)):
		index += 1
	return prefix + str(index)


func _unique_point_id() -> String:
	var ids: Array[String] = []
	for point in _points():
		ids.append(point.point_id)
	var scope := _scope()
	if scope is WorldMapData:
		for city in scope.get_node("Cities").get_children():
			if city is MapCity:
				ids.append(city.city_id)
	else:
		for place in scope.get_node("Layout/Places").get_children():
			ids.append(str(place.get("place_id")))
	var prefix: String = "junction_" if scope is WorldMapData else str(scope.city_id) + "_road_"
	var index := 1
	while ids.has(prefix + str(index)):
		index += 1
	return prefix + str(index)


func _draw_next(screen: Vector2) -> void:
	var scope := _scope()
	var target := _pick_point(screen)
	if not is_instance_valid(chain_start) or not chain_start.is_inside_tree():
		chain_start = null
	if chain_start == null and target == null:
		var hit := _draw_road_hit(screen)
		if not hit.is_empty():
			chain_start = _split_road(hit)
			_set_hint()
			update_overlays()
			return
	if target == chain_start and target != null:
		return
	if chain_start != null and target != null:
		for road in _roads():
			var ends := road.endpoints()
			if ends.has(chain_start) and ends.has(target):
				_set_hint("Эти точки уже соединены. Выберите существующую дорогу для изменения формы.")
				return
		if scope is WorldMapData and chain_start.get_parent() == target.get_parent() and target.get_parent() != scope.get_node("Junctions"):
			_set_hint("Улицы внутри города рисуются в отдельной сцене этого города.")
			return
	var undo := get_undo_redo()
	var fresh := target == null
	if not fresh and chain_start == null:
		chain_start = target
		update_overlays()
		return
	undo.create_action("Нарисовать участок дороги", UndoRedo.MERGE_DISABLE, scope)
	var point_parent := scope.get_node("Junctions" if scope is WorldMapData else "Layout/Points")
	var roads_parent := scope.get_node("Roads" if scope is WorldMapData else "Layout/Roads")
	if fresh:
		target = POINT_SCENE.instantiate()
		target.name = _unique_name(point_parent, "Point")
		target.point_id = _unique_point_id()
		target.junction = scope is WorldMapData
		target.position = _local_position(point_parent, screen)
		undo.add_do_method(point_parent, "add_child", target, true)
		undo.add_do_property(target, "owner", scope)
		undo.add_do_reference(target)
	if chain_start != null:
		var road: MapRoad = ROAD_SCENE.instantiate()
		road.name = _unique_name(roads_parent, "Road")
		road.intercity = scope is WorldMapData
		road.surface = surface_select.selected
		road.road_width = width_input.value
		# Пути строятся относительно будущего узла дороги до его добавления.
		road.from_node = NodePath("../" + str(roads_parent.get_path_to(chain_start)))
		road.to_node = NodePath("../" + str(roads_parent.get_path_to(point_parent)) + "/" + str(target.name)) if fresh else NodePath("../" + str(roads_parent.get_path_to(target)))
		undo.add_do_method(roads_parent, "add_child", road, true)
		undo.add_do_property(road, "owner", scope)
		undo.add_do_reference(road)
		undo.add_undo_method(roads_parent, "remove_child", road)
	if fresh:
		undo.add_undo_method(point_parent, "remove_child", target)
	undo.commit_action()
	chain_start = target
	_set_hint()
	update_overlays()


func _apply_settings() -> void:
	if not is_instance_valid(selected_road):
		_set_hint("Сначала выберите дорогу на карте или в дереве сцены.")
		return
	var undo := get_undo_redo()
	undo.create_action("Изменить покрытие и ширину дороги", UndoRedo.MERGE_DISABLE, _scope())
	undo.add_do_property(selected_road, "surface", surface_select.selected)
	undo.add_do_property(selected_road, "road_width", width_input.value)
	undo.add_undo_property(selected_road, "surface", selected_road.surface)
	undo.add_undo_property(selected_road, "road_width", selected_road.road_width)
	undo.commit_action()


func _commit_curve(title: String, before: Curve2D, after: Curve2D) -> void:
	if not is_instance_valid(selected_road):
		return
	if after != null:
		after.resource_local_to_scene = true
	var undo := get_undo_redo()
	undo.create_action(title, UndoRedo.MERGE_DISABLE, _scope())
	undo.add_do_property(selected_road, "curve", after)
	undo.add_undo_property(selected_road, "curve", before)
	undo.commit_action()
	update_overlays()


func _straighten() -> void:
	if is_instance_valid(selected_road):
		_commit_curve("Выпрямить дорогу", selected_road.curve, null)
		selected_point = -1


func _delete_curve_point() -> void:
	if not is_instance_valid(selected_road):
		return
	var shape := selected_road.effective_curve()
	if selected_point <= 0 or selected_point >= shape.point_count - 1:
		_set_hint("Выберите внутреннюю круглую точку в режиме «Форма». Концы дороги связаны с дорожными узлами.")
		return
	shape.remove_point(selected_point)
	_commit_curve("Удалить изгиб дороги", selected_road.curve, shape)
	selected_point = -1


func _handle_position(shape: Curve2D, index: int, incoming: bool) -> Vector2:
	var anchor := shape.get_point_position(index)
	var offset := shape.get_point_in(index) if incoming else shape.get_point_out(index)
	if offset.length_squared() > 0.0001:
		return _screen_position(selected_road, anchor + offset)
	# Нулевые направляющие тоже доступны для перетаскивания.
	var neighbor := maxi(0, index - 1) if incoming else mini(shape.point_count - 1, index + 1)
	var direction := (_screen_position(selected_road, shape.get_point_position(neighbor)) - _screen_position(selected_road, anchor)).normalized()
	return _screen_position(selected_road, anchor) + direction * 28.0


func _begin_drag(screen: Vector2) -> bool:
	if not is_instance_valid(selected_road) or not selected_road.is_inside_tree():
		return false
	var shape := selected_road.effective_curve()
	for index in range(shape.point_count):
		if _screen_position(selected_road, shape.get_point_position(index)).distance_to(screen) <= 9.0:
			selected_point = index
			drag_kind = "point"
			if index == 0 or index == shape.point_count - 1:
				drag_node = selected_road.endpoints()[0 if index == 0 else 1]
				if drag_node == null or drag_node.owner != _scope():
					drag_kind = ""
					_set_hint("Этот конец находится во вложенной сцене. Переместите дорожную точку в сцене города.")
					return true
				drag_kind = "endpoint"
				drag_node_before = drag_node.position
			_start_curve_drag(shape, index)
			return true
	for index in range(shape.point_count):
		for incoming in [true, false]:
			if (incoming and index == 0) or (not incoming and index == shape.point_count - 1):
				continue
			if _handle_position(shape, index, incoming).distance_to(screen) <= 9.0:
				selected_point = index
				drag_kind = "in" if incoming else "out"
				_start_curve_drag(shape, index)
				return true
	return false


func _start_curve_drag(shape: Curve2D, index: int) -> void:
	drag_index = index
	drag_curve_before = selected_road.curve
	drag_curve_work = shape


func _drag_to(screen: Vector2, mirror: bool = false) -> void:
	if not is_instance_valid(selected_road):
		_cancel_drag()
		return
	var local := _local_position(selected_road, screen)
	match drag_kind:
		"endpoint":
			drag_node.position = _local_position(drag_node.get_parent(), screen)
		"point":
			drag_curve_work.set_point_position(drag_index, local)
		"in":
			drag_curve_work.set_point_in(drag_index, local - drag_curve_work.get_point_position(drag_index))
			if mirror:
				drag_curve_work.set_point_out(drag_index, -drag_curve_work.get_point_in(drag_index))
		"out":
			drag_curve_work.set_point_out(drag_index, local - drag_curve_work.get_point_position(drag_index))
			if mirror:
				drag_curve_work.set_point_in(drag_index, -drag_curve_work.get_point_out(drag_index))
	if drag_kind != "endpoint":
		selected_road.curve = drag_curve_work
	update_overlays()


func _finish_drag() -> void:
	if drag_kind == "endpoint" and is_instance_valid(drag_node):
		var position_after := drag_node.position
		drag_node.position = drag_node_before
		if not position_after.is_equal_approx(drag_node_before):
			var undo := get_undo_redo()
			undo.create_action("Переместить дорожную точку", UndoRedo.MERGE_DISABLE, _scope())
			undo.add_do_property(drag_node, "position", position_after)
			undo.add_undo_property(drag_node, "position", drag_node_before)
			undo.commit_action()
	elif is_instance_valid(selected_road) and selected_road.curve == drag_curve_work:
		selected_road.curve = drag_curve_before
		_commit_curve("Изменить изгиб дороги", drag_curve_before, drag_curve_work)
	drag_kind = ""
	drag_node = null
	drag_curve_work = null
	drag_curve_before = null


func _cancel_drag() -> void:
	if drag_kind == "endpoint" and is_instance_valid(drag_node):
		drag_node.position = drag_node_before
	elif not drag_kind.is_empty() and is_instance_valid(selected_road):
		selected_road.curve = drag_curve_before
	drag_kind = ""
	drag_node = null
	drag_curve_work = null
	drag_curve_before = null


func _curve_hit(road: MapRoad, screen: Vector2) -> Dictionary:
	var shape := road.effective_curve()
	var segment := -1
	var fraction := 0.5
	var distance := PICK_RADIUS
	for index in range(shape.point_count - 1):
		for step in range(48):
			var a := _screen_position(road, shape.sample(index, float(step) / 48.0))
			var b := _screen_position(road, shape.sample(index, float(step + 1) / 48.0))
			var closest := Geometry2D.get_closest_point_to_segment(screen, a, b)
			var candidate := screen.distance_to(closest)
			if candidate < distance:
				distance = candidate
				segment = index
				var within := 0.0 if a.is_equal_approx(b) else a.distance_to(closest) / a.distance_to(b)
				fraction = (step + within) / 48.0
	if segment < 0:
		return {}
	# Уточняем попадание по самой кривой, а не по её отрезкам отображения.
	var low := maxf(0.0, fraction - 1.0 / 48.0)
	var high := minf(1.0, fraction + 1.0 / 48.0)
	for iteration in range(16):
		var left := lerpf(low, high, 1.0 / 3.0)
		var right := lerpf(low, high, 2.0 / 3.0)
		if _screen_position(road, shape.sample(segment, left)).distance_squared_to(screen) < _screen_position(road, shape.sample(segment, right)).distance_squared_to(screen):
			high = right
		else:
			low = left
	fraction = (low + high) / 2.0
	# Используем уже существующую опорную точку, если курсор попал в неё.
	for endpoint in [0.0, 1.0]:
		if _screen_position(road, shape.sample(segment, endpoint)).distance_to(screen) <= 0.5:
			fraction = endpoint
			break
	var snapped := _screen_position(road, shape.sample(segment, fraction))
	if snapped.distance_to(screen) > PICK_RADIUS:
		return {}
	return {"shape": shape, "segment": segment, "fraction": fraction, "screen": snapped}


func _draw_road_hit(screen: Vector2) -> Dictionary:
	if is_instance_valid(chain_start) and chain_start.is_inside_tree():
		return {}
	if not is_instance_valid(selected_road) or not selected_road.is_inside_tree() or selected_road.owner != _scope():
		return {}
	for endpoint in selected_road.endpoints():
		if endpoint == null or _screen_position(endpoint).distance_to(screen) <= PICK_RADIUS:
			return {}
	return _curve_hit(selected_road, screen)


func _split_shape(shape: Curve2D, segment: int, fraction: float) -> int:
	if fraction <= 0.0001:
		return segment
	if fraction >= 0.9999:
		return segment + 1
	# Разделение Безье сохраняет форму дороги при вставке опорной точки.
	var p0 := shape.get_point_position(segment)
	var p1 := p0 + shape.get_point_out(segment)
	var p3 := shape.get_point_position(segment + 1)
	var p2 := p3 + shape.get_point_in(segment + 1)
	var a := p0.lerp(p1, fraction)
	var b := p1.lerp(p2, fraction)
	var c := p2.lerp(p3, fraction)
	var d := a.lerp(b, fraction)
	var e := b.lerp(c, fraction)
	var middle := d.lerp(e, fraction)
	shape.set_point_out(segment, a - p0)
	shape.set_point_in(segment + 1, c - p3)
	shape.add_point(middle, d - middle, e - middle, segment + 1)
	return segment + 1


func _curve_section(shape: Curve2D, first: int, last: int) -> Curve2D:
	var result := Curve2D.new()
	result.resource_local_to_scene = true
	result.bake_interval = shape.bake_interval
	for index in range(first, last + 1):
		result.add_point(shape.get_point_position(index), shape.get_point_in(index), shape.get_point_out(index))
	result.set_point_in(0, Vector2.ZERO)
	result.set_point_out(result.point_count - 1, Vector2.ZERO)
	return result


func _split_road(hit: Dictionary) -> MapPoint:
	var road := selected_road
	var scope := _scope()
	var shape: Curve2D = hit.shape
	var split := _split_shape(shape, hit.segment, hit.fraction)
	if split <= 0 or split >= shape.point_count - 1:
		return null
	var point_parent := scope.get_node("Junctions" if scope is WorldMapData else "Layout/Points")
	var roads_parent := road.get_parent()
	var point: MapPoint = POINT_SCENE.instantiate()
	point.name = _unique_name(point_parent, "Point")
	point.point_id = _unique_point_id()
	point.junction = scope is WorldMapData
	point.position = point_parent.to_local(road.to_global(shape.get_point_position(split)))
	var point_path := NodePath("../" + str(roads_parent.get_path_to(point_parent)) + "/" + str(point.name))
	var continuation: MapRoad = ROAD_SCENE.instantiate()
	continuation.name = _unique_name(roads_parent, "Road")
	continuation.transform = road.transform
	continuation.road_width = road.road_width
	continuation.road_color = road.road_color
	continuation.intercity = road.intercity
	continuation.surface = road.surface
	continuation.dirt_color = road.dirt_color
	continuation.curve_steps = road.curve_steps
	continuation.from_node = point_path
	continuation.to_node = road.to_node
	continuation.curve = _curve_section(shape, split, shape.point_count - 1)
	var undo := get_undo_redo()
	undo.create_action("Вставить дорожный узел", UndoRedo.MERGE_DISABLE, scope)
	undo.add_do_method(point_parent, "add_child", point, true)
	undo.add_do_property(point, "owner", scope)
	undo.add_do_reference(point)
	undo.add_do_property(road, "to_node", point_path)
	undo.add_do_property(road, "curve", _curve_section(shape, 0, split))
	undo.add_do_method(roads_parent, "add_child", continuation, true)
	undo.add_do_property(continuation, "owner", scope)
	undo.add_do_reference(continuation)
	for post in road.checkpoints():
		undo.add_do_method(self, "_move_split_checkpoint", post, road, continuation, post.position, scope)
		undo.add_undo_method(self, "_attach_checkpoint", post, road, post.road_position, scope)
	undo.add_undo_property(road, "to_node", road.to_node)
	undo.add_undo_property(road, "curve", road.curve)
	undo.add_undo_method(roads_parent, "remove_child", continuation)
	undo.add_undo_method(point_parent, "remove_child", point)
	undo.commit_action()
	selected_point = -1
	return point


func _move_split_checkpoint(post: Node2D, first_road: MapRoad, second_road: MapRoad, previous_position: Vector2, scope: Node) -> void:
	var first := first_road.closest_road_position(previous_position)
	var second := second_road.closest_road_position(previous_position)
	if not second.is_empty() and (first.is_empty() or second.distance_squared < first.distance_squared):
		_attach_checkpoint(post, second_road, second.fraction, scope)
	elif not first.is_empty():
		_attach_checkpoint(post, first_road, first.fraction, scope)


func _attach_checkpoint(post: MapRoad.MilitaryCheckpoint, road: MapRoad, fraction: float, scope: Node) -> void:
	if post.get_parent() != road:
		post.reparent(road, false)
		post.owner = scope
	post.road_position = fraction


func _insert_curve_point(screen: Vector2) -> void:
	if not is_instance_valid(selected_road):
		return
	var hit := _curve_hit(selected_road, screen)
	if hit.is_empty():
		return
	var shape: Curve2D = hit.shape
	var index := _split_shape(shape, hit.segment, hit.fraction)
	_commit_curve("Добавить изгиб дороги", selected_road.curve, shape)
	selected_point = index


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if _scope() == null or map_panel == null:
		return
	map_panel.draw_overlay(overlay)
	if is_instance_valid(map_panel.preview_copy):
		return
	if mode == 1:
		var snapped := _pick_point(mouse_position)
		var finish := _screen_position(snapped) if snapped != null else mouse_position
		if snapped == null:
			var hit := _draw_road_hit(mouse_position)
			if not hit.is_empty():
				finish = hit.screen
		for point in _points():
			overlay.draw_circle(_screen_position(point), 5.0, ACCENT)
		overlay.draw_circle(finish, 9.0, ACCENT, false, 2.0)
		if is_instance_valid(chain_start) and chain_start.is_inside_tree():
			overlay.draw_dashed_line(_screen_position(chain_start), finish, ACCENT, 2.0, 7.0)
	if not is_instance_valid(selected_road) or not selected_road.is_inside_tree():
		return
	var points := selected_road.path_points()
	for index in range(points.size() - 1):
		overlay.draw_line(_screen_position(selected_road, points[index]), _screen_position(selected_road, points[index + 1]), ACCENT, 2.0, true)
	if mode != 2:
		return
	var shape := selected_road.effective_curve()
	for index in range(shape.point_count):
		var anchor := _screen_position(selected_road, shape.get_point_position(index))
		for incoming in [true, false]:
			if (incoming and index == 0) or (not incoming and index == shape.point_count - 1):
				continue
			var handle := _handle_position(shape, index, incoming)
			overlay.draw_line(anchor, handle, Color(0.95, 0.7, 0.3), 1.0, true)
			overlay.draw_rect(Rect2(handle - Vector2(4, 4), Vector2(8, 8)), Color(0.95, 0.7, 0.3))
		overlay.draw_circle(anchor, 6.0, Color.WHITE if index == selected_point else ACCENT)
