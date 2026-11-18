extends Node

# Обычный HUD скрывается целиком, сохраняя видимость отдельных кнопок.
var hud: Control
var backdrop: ColorRect
var windows: Array[Node] = []
var opened: Array[Node] = []
var map_view: Node


func setup(root: Control, modal_windows: Array[Node], map: Node) -> void:
	windows = modal_windows
	map_view = map
	hud = root.get_node("BaseHUD")
	backdrop = root.get_node("ModalBackdrop")
	for window in windows:
		if window is Control:
			window.z_index = 100
		elif window is Window:
			window.transient = true
			window.exclusive = true
		window.visibility_changed.connect(_visibility_changed.bind(window))
		if window.get("visible"):
			opened.append(window)
	_refresh()


func _visibility_changed(window: Node) -> void:
	opened.erase(window)
	if window.get("visible"):
		opened.append(window)
	_refresh()


func _refresh() -> void:
	var modal_open := not opened.is_empty()
	hud.visible = not modal_open
	backdrop.visible = modal_open
	var top: Node = opened.back() if modal_open else null
	for window in windows:
		if window is Control:
			window.set_process_input(window == top)
			window.modulate = Color.WHITE if window == top or not modal_open else Color(1, 1, 1, 0)
	# _input выполняется до GUI: отключаем и его, чтобы карта не ловила жесты.
	map_view.set_process_input(not modal_open)
	map_view.set_process_unhandled_input(not modal_open)
	if modal_open:
		map_view.set("camera_drag_pending", false)
		map_view.set("camera_drag_active", false)
		for window in windows:
			if window is Control:
				window.z_index = 98
		if top is Control:
			top.z_index = 100
			top.get_parent().move_child(top, -1)
