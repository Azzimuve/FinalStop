@tool
extends RefCounted

const MapCity = preload("res://scripts/world/MapCity.gd")
const MapPoint = preload("res://scripts/world/MapPoint.gd")
const MapRoad = preload("res://scripts/world/MapRoad.gd")
const MapPlace = preload("res://scripts/world/MapPlace.gd")
const WorldData = preload("res://scripts/WorldMapData.gd")
const POINT_SCENE = preload("res://scenes/world/RoadPoint.tscn")
const PLACE_SCENE = preload("res://scenes/world/PointOfInterest.tscn")
const TEMPLATE_PATH := "res://scenes/world/CityTemplate.tscn"

var plugin: EditorPlugin
var toolbar: Control
var dialog: ConfirmationDialog
var name_input: LineEdit
var preview_toggle: CheckButton
var detail_slider: HSlider
var placement := ""
var placement_name := ""
var connect_only := false
var pending_entrance_path := ""
var preview_source: Node2D
var preview_copy: Node2D
var preview_cities: Array[MapCity] = []
var preview_roads: Array[MapRoad] = []

func setup(editor_plugin: EditorPlugin, control: Control) -> void:
	plugin = editor_plugin
	toolbar = control
	dialog = toolbar.get_node("NameDialog")
	name_input = toolbar.get_node("NameDialog/Fields/Name")
	preview_toggle = toolbar.get_node("Content/Preview/Enabled")
	detail_slider = toolbar.get_node("Content/Preview/Detail")
	toolbar.get_node("Content/MapTools/AddCity").pressed.connect(_request_name.bind("city"))
	toolbar.get_node("Content/MapTools/EditCity").pressed.connect(_open_city)
	toolbar.get_node("Content/MapTools/AddEntrance").pressed.connect(_request_entrance)
	toolbar.get_node("Content/MapTools/Connect").pressed.connect(_start_connect)
	toolbar.get_node("Content/MapTools/AddPlace").pressed.connect(_add_place)
	dialog.confirmed.connect(_confirm_name)
	dialog.canceled.connect(cancel)
	name_input.text_changed.connect(func(text: String): dialog.get_ok_button().disabled = text.strip_edges().is_empty())
	name_input.text_submitted.connect(func(_text: String):
		if not name_input.text.strip_edges().is_empty():
			dialog.hide()
			_confirm_name())
	preview_toggle.toggled.connect(_toggle_preview)
	detail_slider.value_changed.connect(_apply_preview)
	toolbar.get_node("Content/Preview/Collapsed").pressed.connect(_preview_preset.bind(0.0))
	toolbar.get_node("Content/Preview/Middle").pressed.connect(_preview_preset.bind(0.5))
	toolbar.get_node("Content/Preview/Expanded").pressed.connect(_preview_preset.bind(1.0))

func cleanup() -> void:
	_stop_preview()
	var scope: Node2D = plugin._scope()
	if scope is WorldData:
		for city in scope.get_node("Cities").get_children():
			if city is MapCity:
				city.set_editor_compact(false)

func scene_changed() -> void:
	_stop_preview()
	dialog.hide()
	cancel()
	refresh()
	var scope: Node2D = plugin._scope()
	if scope != null and scope.scene_file_path == pending_entrance_path and scope is MapCity:
		pending_entrance_path = ""
		_request_name.call_deferred("entrance")

func refresh() -> void:
	var scope: Node2D = plugin._scope()
	var preview := is_instance_valid(preview_copy)
	toolbar.get_node("Content/MapTools/AddCity").disabled = preview or not scope is WorldData
	toolbar.get_node("Content/MapTools/EditCity").disabled = preview or _selected_city() == null or scope is MapCity
	toolbar.get_node("Content/MapTools/AddEntrance").disabled = preview or _selected_city() == null
	toolbar.get_node("Content/MapTools/Connect").disabled = preview or scope == null
	toolbar.get_node("Content/MapTools/AddPlace").disabled = preview or _selected_city_point() == null
	for child in toolbar.get_node("Content/Tools").get_children():
		if child is BaseButton:
			child.disabled = preview
		elif child is SpinBox:
			child.editable = not preview
	if scope is MapCity:
		scope.set_editor_compact(false)
	elif scope is WorldData:
		for city in scope.get_node("Cities").get_children():
			if city is MapCity:
				city.set_editor_compact(true)

func _selected_city() -> MapCity:
	var scope: Node2D = plugin._scope()
	if scope is MapCity:
		return scope
	for selected in EditorInterface.get_selection().get_selected_nodes():
		var node: Node = selected
		while node != null and node != scope:
			if node is MapCity:
				return node
			node = node.get_parent()
	return null

func _selected_city_point() -> MapPoint:
	var city := plugin._scope() as MapCity
	if city == null:
		return null
	var selection := EditorInterface.get_selection().get_selected_nodes()
	if selection.size() != 1:
		return null
	var point := selection[0] as MapPoint
	return point if point != null and city.get_node("Layout/Points").is_ancestor_of(point) else null

func _add_place() -> void:
	var point := _selected_city_point()
	if point == null or is_instance_valid(preview_copy):
		plugin._set_hint("Выберите один дорожный узел в отдельной сцене города.")
		return
	var city := plugin._scope() as MapCity
	var parent := city.get_node("Layout/Places")
	var ids: Array[String] = []
	for child in city.get_node("Layout/Points").get_children():
		if child is MapPoint:
			ids.append(child.point_id)
	for child in parent.get_children():
		if child is MapPlace:
			ids.append(child.place_id)
	var prefix := city.city_id + "_place_" if not city.city_id.is_empty() else "place_"
	var index := 1
	while ids.has(prefix + str(index)):
		index += 1
	var place := PLACE_SCENE.instantiate() as MapPlace
	place.name = plugin._unique_name(parent, "PointOfInterest")
	place.place_id = prefix + str(index)
	place.position = parent.to_local(point.global_position)
	place.road_node = NodePath("../" + str(parent.get_path_to(point)))
	plugin._set_mode(0)
	var undo := plugin.get_undo_redo()
	undo.create_action("Добавить точку интереса", UndoRedo.MERGE_DISABLE, city)
	undo.add_do_method(parent, "add_child", place, true)
	undo.add_do_property(place, "owner", city)
	undo.add_do_reference(place)
	undo.add_undo_method(parent, "remove_child", place)
	undo.commit_action()
	plugin._select_node(place)
	plugin._set_hint("Точка интереса добавлена и привязана к узлу. В Inspector выберите Object Type и задайте Display Name.")

func _open_city() -> void:
	var city := _selected_city()
	if city == null:
		plugin._set_hint("Выберите значок города или его узел в Cities.")
		return
	if city.scene_file_path.is_empty():
		plugin._set_hint("У города нет отдельного файла. Сначала сохраните его ветку как сцену.")
		return
	EditorInterface.open_scene_from_path(city.scene_file_path)

func _request_entrance() -> void:
	var scope: Node2D = plugin._scope()
	if scope is MapCity:
		_request_name("entrance")
	else:
		var city := _selected_city()
		if city == null or city.scene_file_path.is_empty():
			plugin._set_hint("Сначала выберите город с отдельной сценой.")
			return
		pending_entrance_path = city.scene_file_path
		_open_city()

func _request_name(kind: String) -> void:
	var scope: Node2D = plugin._scope()
	if (kind == "city" and not scope is WorldData) or (kind == "entrance" and not scope is MapCity):
		return
	plugin._set_mode(0)
	placement = kind
	placement_name = ""
	dialog.title = "Новый город" if kind == "city" else "Новый въезд"
	name_input.text = ""
	dialog.get_ok_button().disabled = true
	dialog.popup_centered()
	name_input.grab_focus()

func _confirm_name() -> void:
	placement_name = name_input.text.strip_edges()
	if placement_name.is_empty():
		return
	plugin._set_hint("Щёлкните на карте, чтобы разместить %s «%s». Esc / ПКМ — отмена." % ["город" if placement == "city" else "въезд", placement_name])
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(plugin._scope())
	plugin.update_overlays()

func cancel() -> void:
	placement = ""
	placement_name = ""
	connect_only = false

func _start_connect() -> void:
	plugin._set_mode(1)
	connect_only = true
	plugin._set_hint("Выберите начальный и конечный въезд или дорожный узел. Между ними появится дорога; изгибы — в режиме «Форма».")

func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_instance_valid(preview_copy):
			preview_toggle.button_pressed = false
			return true
		if not placement.is_empty() or connect_only:
			cancel()
			plugin._set_mode(0)
			return true
	if is_instance_valid(preview_copy):
		# Панорамирование и масштабирование остаются штатными.
		return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.alt_pressed and not Input.is_key_pressed(KEY_SPACE)
	if connect_only and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		plugin._set_mode(0)
		return true
	if placement_name.is_empty():
		if plugin.mode == 0 and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not event.alt_pressed and not Input.is_key_pressed(KEY_SPACE):
			var city := _pick_city(event.position)
			if city != null and not EditorInterface.get_selection().get_selected_nodes().has(city):
				plugin._select_node(city)
				return true
		return false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel()
			plugin._set_mode(0)
			return true
		if event.button_index == MOUSE_BUTTON_LEFT and not event.alt_pressed and not Input.is_key_pressed(KEY_SPACE):
			if event.pressed:
				if placement == "city":
					_create_city(event.position)
				else:
					_create_entrance(event.position)
			return true
	return false

func _pick_city(screen: Vector2) -> MapCity:
	var scope: Node2D = plugin._scope()
	if not scope is WorldData:
		return null
	var nearest: MapCity
	var distance := INF
	for city in scope.get_node("Cities").get_children():
		if not city is MapCity:
			continue
		var center: Vector2 = plugin._screen_position(city)
		var edge: Vector2 = plugin._screen_position(city, Vector2(20, 0))
		var candidate := screen.distance_to(center)
		if candidate <= maxf(12.0, center.distance_to(edge)) and candidate < distance:
			nearest = city
			distance = candidate
	return nearest

func _create_city(screen: Vector2) -> void:
	var scope: Node2D = plugin._scope()
	if not scope is WorldData:
		return
	var index := 1
	var used_ids: Array[String] = []
	for city in scope.get_node("Cities").get_children():
		if city is MapCity:
			used_ids.append(city.city_id)
	for point in scope.get_node("Junctions").get_children():
		if point is MapPoint:
			used_ids.append(point.point_id)
	while used_ids.has("city_%d" % index) or FileAccess.file_exists("res://scenes/world/cities/City%d.tscn" % index):
		index += 1
	var path := "res://scenes/world/cities/City%d.tscn" % index
	var template := ResourceLoader.load(TEMPLATE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if template == null:
		plugin._set_hint("Не удалось загрузить чистый шаблон CityTemplate.")
		return
	var authored := template.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as MapCity
	authored.scene_file_path = ""
	authored.name = "City%d" % index
	authored.city_id = "city_%d" % index
	authored.display_name = placement_name
	authored.position = Vector2.ZERO
	# Чистый шаблон содержит только основной въезд и пустые контейнеры.
	var packed := PackedScene.new()
	var error := packed.pack(authored)
	authored.free()
	if error == OK:
		error = ResourceSaver.save(packed, path)
	if error != OK:
		plugin._set_hint("Не удалось сохранить сцену города: %s" % error_string(error))
		return
	EditorInterface.get_resource_filesystem().scan()
	var saved := load(path) as PackedScene
	var city := saved.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as MapCity
	var parent := scope.get_node("Cities")
	city.name = plugin._unique_name(parent, "City")
	city.position = plugin._local_position(parent, screen)
	var undo := plugin.get_undo_redo()
	undo.create_action("Добавить город", UndoRedo.MERGE_DISABLE, scope)
	undo.add_do_method(parent, "add_child", city, true)
	undo.add_do_property(city, "owner", scope)
	undo.add_do_reference(city)
	undo.add_undo_method(parent, "remove_child", city)
	undo.commit_action()
	cancel()
	plugin._select_node(city)
	refresh()
	plugin._set_hint("Создан %s. Сохраните World. Для улиц нажмите «Редактировать город». Undo убирает экземпляр, файл города остаётся." % path)

func _create_entrance(screen: Vector2) -> void:
	var city := plugin._scope() as MapCity
	if city == null:
		return
	var existing := plugin._pick_point(screen) as MapPoint
	var parent := city.get_node("Layout/Points")
	var point: MapPoint = existing if existing != null else POINT_SCENE.instantiate()
	var undo := plugin.get_undo_redo()
	undo.create_action("Добавить въезд города", UndoRedo.MERGE_DISABLE, city)
	if existing == null:
		point.name = plugin._unique_name(parent, "Entry")
		point.point_id = plugin._unique_point_id()
		point.position = plugin._local_position(parent, screen)
		undo.add_do_method(parent, "add_child", point, true)
		undo.add_do_property(point, "owner", city)
		undo.add_do_reference(point)
		undo.add_undo_method(parent, "remove_child", point)
	undo.add_do_property(point, "city_entrance", true)
	undo.add_do_property(point, "entrance_name", placement_name)
	undo.add_undo_property(point, "city_entrance", point.city_entrance)
	undo.add_undo_property(point, "entrance_name", point.entrance_name)
	var entry := city.get_node_or_null(city.entry_node)
	if not entry is MapPoint or not city.is_ancestor_of(entry):
		undo.add_do_property(city, "entry_node", NodePath("Layout/Points/" + str(point.name)))
		undo.add_undo_property(city, "entry_node", city.entry_node)
	undo.commit_action()
	cancel()
	plugin._select_node(point)
	plugin._set_hint("Въезд добавлен. Соедините его с улицами, сохраните город и вернитесь в World для подключения трассы.")

func _preview_preset(value: float) -> void:
	detail_slider.value = value
	preview_toggle.button_pressed = true

func _toggle_preview(enabled: bool) -> void:
	if not enabled:
		_stop_preview()
		refresh()
		plugin._set_hint()
		return
	plugin._set_mode(0)
	preview_source = plugin._scope()
	if preview_source == null:
		_stop_preview()
		return
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(preview_source)
	# Не сериализуем копию и не трогаем исходные Node2D.transform/visible.
	# Копируем текущее дерево, включая несохранённые узлы: повторное
	# инстанцирование файла потеряло бы их или вернуло удалённые объекты.
	preview_copy = preview_source.duplicate(Node.DUPLICATE_SCRIPTS) as Node2D
	preview_copy.name = "MapFoldPreview"
	preview_copy.set_meta("_map_fold_preview", true)
	_collect_preview(preview_copy)
	preview_source.get_parent().add_child(preview_copy)
	RenderingServer.canvas_item_set_visible(preview_source.get_canvas_item(), false)
	_apply_preview.call_deferred(detail_slider.value)
	refresh()
	plugin._set_hint("Предпросмотр: ползунок показывает раскрытие как в игре. Координаты исходных сцен не меняются. Для редактирования выключите предпросмотр или нажмите Esc.")
	plugin.update_overlays()

func _collect_preview(node: Node) -> void:
	if node is MapCity:
		node.editor_preview = true
		preview_cities.append(node)
	elif node is MapPoint:
		node.editor_preview = true
	elif node is MapPlace:
		node.editor_preview = true
	elif node is MapRoad:
		preview_roads.append(node)
	for child in node.get_children():
		_collect_preview(child)

func _apply_preview(value: float) -> void:
	toolbar.get_node("Content/Preview/Value").text = "%d%%" % roundi(value * 100)
	if not is_instance_valid(preview_copy):
		return
	for city in preview_cities:
		city.set_view(value, true, "")
	for road in preview_roads:
		if road.intercity:
			road.detail = value
	plugin.update_overlays()

func _stop_preview() -> void:
	preview_toggle.set_pressed_no_signal(false)
	if is_instance_valid(preview_source):
		RenderingServer.canvas_item_set_visible(preview_source.get_canvas_item(), preview_source.visible)
	if is_instance_valid(preview_copy):
		preview_copy.get_parent().remove_child(preview_copy)
		preview_copy.queue_free()
	preview_source = null
	preview_copy = null
	preview_cities.clear()
	preview_roads.clear()
	plugin.update_overlays()

func draw_overlay(overlay: Control) -> void:
	if is_instance_valid(preview_copy):
		return
	var scope: Node2D = plugin._scope()
	var cities: Array[MapCity] = []
	if scope is MapCity:
		cities.append(scope)
	elif scope is WorldData:
		for city in scope.get_node("Cities").get_children():
			if city is MapCity:
				cities.append(city)
	for city in cities:
		for point in city.get_entrance_points():
			var position: Vector2 = plugin._screen_position(point)
			var color := Color(0.95, 0.7, 0.3)
			if scope is WorldData:
				overlay.draw_dashed_line(plugin._screen_position(city), position, Color(color, 0.3), 1.0, 5.0)
			overlay.draw_circle(position, 7.0, color, false, 2.0)
			var title := point.entrance_name if not point.entrance_name.is_empty() else point.point_id
			overlay.draw_string(ThemeDB.fallback_font, position + Vector2(10, -8), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	if not placement_name.is_empty():
		overlay.draw_circle(plugin.mouse_position, 20.0 if placement == "city" else 7.0, Color(0.3, 0.88, 0.85), false, 2.0)
