@tool
extends Node2D

const MilitaryCheckpoint = preload("res://scripts/world/MilitaryCheckpoint.gd")

signal geometry_changed

## Название межгородского участка в эфире. Пустое поле исключает дорогу из сводок.
@export var radio_name := ""
@export_node_path("Node2D") var from_node: NodePath:
	set(value):
		from_node = value
		_invalidate_geometry()
		_queue_endpoint_binding()
@export_node_path("Node2D") var to_node: NodePath:
	set(value):
		to_node = value
		_invalidate_geometry()
		_queue_endpoint_binding()
@export_range(0.1, 50.0) var road_width: float = 5.0:
	set(value):
		road_width = value
		_draw_mesh = null
		queue_redraw()
@export var road_color := Color("#504d3b"):
	set(value):
		road_color = value
		queue_redraw()
@export var intercity: bool = false:
	set(value):
		intercity = value
		_draw_mesh = null
		queue_redraw()
@export_enum("Асфальт", "Грунт") var surface: int = 0:
	set(value):
		surface = value
		queue_redraw()
@export var dirt_color := Color("#8c7856"):
	set(value):
		dirt_color = value
		queue_redraw()
## Картографические ленты. По горизонтали — повтор вдоль дороги, по вертикали — от края до края.
@export var asphalt_skin: Texture2D = preload("res://resources/atlas/road_asphalt.svg"):
	set(value):
		asphalt_skin = value
		queue_redraw()
@export var dirt_skin: Texture2D = preload("res://resources/atlas/road_dirt.svg"):
	set(value):
		dirt_skin = value
		queue_redraw()
## Опорные точки и независимые направляющие редактируются инструментом «Дороги».
## Концы кривой привязаны к From Node и To Node.
@export var curve: Curve2D:
	set(value):
		if curve != null and curve.changed.is_connected(_invalidate_geometry):
			curve.changed.disconnect(_invalidate_geometry)
		curve = value
		if curve != null:
			curve.changed.connect(_invalidate_geometry)
		_invalidate_geometry()
@export_range(4, 64) var curve_steps: int = 24:
	set(value):
		curve_steps = value
		_invalidate_geometry()
var detail: float = 1.0:
	set(value):
		if detail == value:
			return
		detail = value
		_draw_mesh = null
		queue_redraw()

var _draw_mesh: ArrayMesh
var _draw_widths := Vector2(-1, -1)
var _geometry_dirty := true
var _cached_shape: Curve2D
var _cached_points: Array[Vector2] = []
var _cached_start := Vector2(INF, INF)
var _cached_finish := Vector2(INF, INF)
var _cached_length := 0.0
var _reference_cache_valid := false
var _reference_transform := Transform2D.IDENTITY
var _reference_points: Array[Vector2] = []
var _bound_endpoints: Array[Node2D] = []
var _binding_pending := false

func _enter_tree() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_notify_transform(true)
	if Engine.is_editor_hint():
		get_tree().tree_changed.connect(_queue_endpoint_binding)
	_queue_endpoint_binding()

func _exit_tree() -> void:
	if get_tree().tree_changed.is_connected(_queue_endpoint_binding):
		get_tree().tree_changed.disconnect(_queue_endpoint_binding)
	_disconnect_endpoints()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_endpoint_transform_changed()

func _queue_endpoint_binding() -> void:
	if not is_inside_tree() or _binding_pending:
		return
	_binding_pending = true
	_bind_endpoints.call_deferred()

func _disconnect_endpoints() -> void:
	for endpoint in _bound_endpoints:
		if not is_instance_valid(endpoint):
			continue
		for signal_name in ["map_transform_changed", "configuration_changed", "tree_exiting"]:
			if endpoint.has_signal(signal_name) and endpoint.is_connected(signal_name, _endpoint_transform_changed):
				endpoint.disconnect(signal_name, _endpoint_transform_changed)
	_bound_endpoints.clear()

func _bind_endpoints() -> void:
	_binding_pending = false
	if not is_inside_tree():
		return
	var next_endpoints: Array[Node2D] = []
	for endpoint in endpoints():
		if endpoint != null and not next_endpoints.has(endpoint):
			next_endpoints.append(endpoint)
	# Изменение чужой ветки дерева не требует пересчёта этой дороги.
	if next_endpoints == _bound_endpoints:
		# Новая соседняя трасса может превратить въезд в сквозной перекрёсток.
		queue_redraw()
		return
	_disconnect_endpoints()
	for endpoint in next_endpoints:
		_bound_endpoints.append(endpoint)
		for signal_name in ["map_transform_changed", "configuration_changed", "tree_exiting"]:
			if endpoint.has_signal(signal_name):
				endpoint.connect(signal_name, _endpoint_transform_changed)
	_invalidate_geometry()
	if Engine.is_editor_hint():
		update_configuration_warnings()

func _endpoint_transform_changed() -> void:
	# Проверка локальных концов при чтении кеша учитывает и общие
	# трансформации города, которые не меняют саму форму дороги.
	queue_redraw()
	geometry_changed.emit()

func _invalidate_geometry() -> void:
	_geometry_dirty = true
	queue_redraw()
	geometry_changed.emit()

func endpoints() -> Array[Node2D]:
	return [get_node_or_null(from_node) as Node2D, get_node_or_null(to_node) as Node2D]

func effective_curve() -> Curve2D:
	_ensure_geometry()
	# Редактор меняет возвращённый ресурс: кеш нельзя отдавать для записи.
	return _cached_shape.duplicate()

func _build_effective_curve() -> Curve2D:
	var result: Curve2D = curve.duplicate() if curve != null and curve.point_count >= 2 else Curve2D.new()
	var ends := endpoints()
	if ends[0] == null or ends[1] == null:
		return result
	var start := to_local(ends[0].global_position)
	var finish := to_local(ends[1].global_position)
	if result.point_count < 2:
		result.add_point(start)
		result.add_point(finish)
	else:
		# При перемещении связанных узлов вся кривая следует за концами.
		var start_delta := start - result.get_point_position(0)
		var finish_delta := finish - result.get_point_position(result.point_count - 1)
		for index in range(result.point_count):
			var weight := float(index) / float(result.point_count - 1)
			result.set_point_position(index, result.get_point_position(index) + start_delta.lerp(finish_delta, weight))
	return result

func _ensure_geometry() -> void:
	var ends := endpoints()
	var start := to_local(ends[0].global_position) if ends[0] != null else Vector2(INF, INF)
	var finish := to_local(ends[1].global_position) if ends[1] != null else Vector2(INF, INF)
	if not _geometry_dirty and start.is_equal_approx(_cached_start) and finish.is_equal_approx(_cached_finish):
		return
	_geometry_dirty = false
	_draw_mesh = null
	_cached_start = start
	_cached_finish = finish
	_reference_cache_valid = false
	_cached_shape = _build_effective_curve()
	_cached_points.clear()
	_cached_length = 0.0
	if _cached_shape.point_count < 2:
		return
	# Постоянное число отсчётов позволяет совместить маршрут и дорогу
	# при раскрытии города и перемещении его въездов.
	var curved := curve != null and curve.point_count >= 2
	var steps := curve_steps if curved else 1
	for index in range(_cached_shape.point_count - 1):
		for step in range(steps):
			_cached_points.append(_cached_shape.sample(index, float(step) / steps))
	_cached_points.append(_cached_shape.get_point_position(_cached_shape.point_count - 1))
	for index in range(_cached_points.size() - 1):
		_cached_length += _cached_points[index].distance_to(_cached_points[index + 1])

func path_points(reference: Node2D = null) -> Array[Vector2]:
	_ensure_geometry()
	if reference != null:
		var relative_transform := reference.global_transform.affine_inverse() * global_transform
		if not _reference_cache_valid or relative_transform != _reference_transform:
			_reference_transform = relative_transform
			_reference_points.clear()
			for point in _cached_points:
				_reference_points.append(relative_transform * point)
			_reference_cache_valid = true
		return _reference_points.duplicate()
	return _cached_points.duplicate()

func closest_road_position(local_point: Vector2) -> Dictionary:
	_ensure_geometry()
	var best := INF
	var hit := {}
	var travelled := 0.0
	for i in range(_cached_points.size() - 1):
		var a := _cached_points[i]
		var b := _cached_points[i + 1]
		var length := a.distance_to(b)
		if length <= 0.0001:
			continue
		var snapped := Geometry2D.get_closest_point_to_segment(local_point, a, b)
		var distance := snapped.distance_squared_to(local_point)
		if distance < best:
			best = distance
			var along := a.distance_to(snapped)
			hit = {"point": snapped, "direction": a.direction_to(b), "distance_squared": distance,
				"fraction": (i + along / length) / (_cached_points.size() - 1),
				"along": travelled + along}
		travelled += length
	return hit

func pick(global_point: Vector2) -> Dictionary:
	if not is_visible_in_tree():
		return {}
	var hit := closest_road_position(to_local(global_point))
	if hit.is_empty() or hit.distance_squared > pow(maxf(road_width, 5.0) * 0.5, 2):
		return {}
	var widths := _endpoint_widths(endpoints())
	var transition := minf(60.0, _cached_length / 3.0) if intercity else 0.0
	var width := _width_at(hit.along, _cached_length, transition, widths.x, widths.y)
	return hit if hit.distance_squared <= width * width * 0.25 else {}

func checkpoints() -> Array[MilitaryCheckpoint]:
	var result: Array[MilitaryCheckpoint] = []
	for child in get_children():
		if child is MilitaryCheckpoint:
			result.append(child)
	return result

func _get_configuration_warnings() -> PackedStringArray:
	var ends := endpoints()
	if ends[0] == null or ends[1] == null or ends[0] == ends[1]:
		return ["Выберите два разных узла дороги в From Node и To Node."]
	return []

# Сквозная трасса остаётся широкой даже на узле, принадлежащем городу.
# Городские улицы задают свою ширину отдельно в Inspector.
func _is_narrow_city_access(endpoint: Node2D) -> bool:
	if endpoint.get("junction"):
		return false
	var ancestor := endpoint.get_parent()
	while ancestor != null and not ancestor.has_method("get_entrance_points"):
		ancestor = ancestor.get_parent()
	if ancestor == null:
		return false
	for sibling in get_parent().get_children():
		if sibling == self or not is_instance_of(sibling, get_script()):
			continue
		if sibling.intercity and endpoint in sibling.endpoints():
			return false
	return true

func _endpoint_widths(ends: Array[Node2D]) -> Vector2:
	var start_width := road_width
	var finish_width := road_width
	if intercity:
		if _is_narrow_city_access(ends[0]):
			start_width = lerpf(road_width, 5.0, detail)
		if _is_narrow_city_access(ends[1]):
			finish_width = lerpf(road_width, 5.0, detail)
	return Vector2(start_width, finish_width)

func _draw() -> void:
	var ends := endpoints()
	if ends[0] == null or ends[1] == null:
		return
	_ensure_geometry()
	if _cached_length <= 0.0001:
		return
	var widths := _endpoint_widths(ends)
	if _draw_mesh == null or _draw_widths != widths:
		_draw_mesh = _build_draw_mesh(widths.x, widths.y)
		_draw_widths = widths
	draw_mesh(_draw_mesh, null, Transform2D.IDENTITY, road_color if surface == 0 else dirt_color)
	var skin := asphalt_skin if surface == 0 else dirt_skin
	if skin != null:
		draw_mesh(_draw_mesh, skin)

# Один меш на дорогу вместо тысяч отдельных полигонов и кругов.
# Отсчёты кривой и граф маршрутов остаются прежними; дополнительные
# вершины нужны только на границах сужения у въездов.
func _build_draw_mesh(start_width: float, finish_width: float) -> ArrayMesh:
	var points := PackedVector2Array([_cached_points[0]])
	var distances := PackedFloat32Array([0.0])
	var total := _cached_length
	var transition := minf(60.0, total / 3.0) if intercity else 0.0
	var travelled := 0.0
	for index in range(_cached_points.size() - 1):
		var start := _cached_points[index]
		var finish := _cached_points[index + 1]
		var length := start.distance_to(finish)
		if length <= 0.0001:
			continue
		for boundary in [transition, total - transition]:
			if boundary > travelled + 0.0001 and boundary < travelled + length - 0.0001:
				points.append(start.lerp(finish, (boundary - travelled) / length))
				distances.append(boundary)
		travelled += length
		points.append(finish)
		distances.append(travelled)
	var widths := PackedFloat32Array()
	for distance in distances:
		widths.append(_width_at(distance, total, transition, start_width, finish_width))
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# Одна непрерывная лента. Длина повтора привязана к длине пути, а не к числу точек кривой.
	var repeat_length := maxf(road_width * 4.0, 4.0)
	for i in points.size():
		var before := points[maxi(i - 1, 0)].direction_to(points[i])
		var after := points[i].direction_to(points[mini(i + 1, points.size() - 1)])
		var tangent := (before + after).normalized()
		if tangent.is_zero_approx():
			tangent = after if not after.is_zero_approx() else before
		var normal := tangent.orthogonal()
		var edge := normal * widths[i] * 0.5 / maxf(absf(tangent.dot(after if i + 1 < points.size() else before)), 0.5)
		var u := distances[i] / repeat_length
		vertices.append(points[i] + edge)
		vertices.append(points[i] - edge)
		uvs.append(Vector2(u, 0))
		uvs.append(Vector2(u, 1))
		if i > 0:
			var v := 2 * i
			indices.append_array(PackedInt32Array([v - 2, v, v - 1, v, v + 1, v - 1]))
	# Полукруги добавляются только на концах. В поворотах разметка следует общей кромке.
	const CAP_STEPS := 12
	for i: int in [0, points.size() - 1]:
		var neighbor := 1 if i == 0 else i - 1
		var outward := points[neighbor].direction_to(points[i])
		var normal := outward.orthogonal() * (-1.0 if i == 0 else 1.0)
		var center := vertices.size()
		var u := distances[i] / repeat_length
		vertices.append(points[i])
		uvs.append(Vector2(u, 0.5))
		for step in range(CAP_STEPS + 1):
			var angle := PI * float(step) / CAP_STEPS
			var delta := (normal * cos(angle) + outward * sin(angle)) * widths[i] * 0.5
			vertices.append(points[i] + delta)
			uvs.append(Vector2(u + delta.dot(outward) * (-1.0 if i == 0 else 1.0) / repeat_length, (1.0 - cos(angle)) * 0.5))
			if step > 0:
				indices.append_array(PackedInt32Array([center, center + step, center + step + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _width_at(distance: float, total: float, transition: float, start_width: float, finish_width: float) -> float:
	if transition <= 0.0:
		return road_width
	if distance < transition:
		return lerpf(start_width, road_width, distance / transition)
	if distance > total - transition:
		return lerpf(finish_width, road_width, (total - distance) / transition)
	return road_width
