extends Control

const VehicleInventory = preload("res://scripts/simulation/VehicleInventory.gd")
const CargoItem = preload("res://scripts/simulation/CargoItem.gd")
const CELL: float = 10.0

signal clicked(item: CargoItem, cell: Vector2i)
signal double_clicked(item: CargoItem, cell: Vector2i)
signal context_requested(item: CargoItem, cell: Vector2i)
signal hovered(item: CargoItem)
var model: VehicleInventory
var selected: CargoItem
var selected_rotation: bool = false


func setup(inventory: VehicleInventory) -> void:
	model = inventory
	custom_minimum_size = Vector2(model.dimensions) * CELL
	size = custom_minimum_size
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if selected != null:
			queue_redraw()
		var hover_item: CargoItem
		if model != null:
			for placement in model.placements:
				if Rect2i(placement.cell, placement.extent).has_point(Vector2i(event.position / CELL)):
					hover_item = placement.item
					break
		hovered.emit(hover_item)
	if model == null or not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	var cell := Vector2i(event.position / CELL)
	var item: CargoItem
	for placement in model.placements:
		if Rect2i(placement.cell, placement.extent).has_point(cell):
			item = placement.item
			break
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if item != null:
			context_requested.emit(item, cell)
	elif event.double_click and double_clicked.has_connections():
		double_clicked.emit(item, cell)
	else:
		clicked.emit(item, cell)
	accept_event()


func _draw() -> void:
	if model == null:
		return
	var grid_color := Color(0.3, 0.4, 0.4)
	for y in range(model.dimensions.y + 1):
		draw_line(Vector2(0, y * CELL), Vector2(model.dimensions.x * CELL, y * CELL), grid_color)
	for x in range(model.dimensions.x + 1):
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, model.dimensions.y * CELL), grid_color)
	for index in range(model.placements.size()):
		var placement: Dictionary = model.placements[index]
		var rect := Rect2(Vector2(placement.cell) * CELL + Vector2.ONE, Vector2(placement.extent) * CELL - Vector2.ONE * 2)
		draw_rect(rect, Color(0.85, 0.7, 0.3) if selected == placement.item else Color(0.3, 0.65, 0.55))
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(1, 9), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
	if selected != null:
		var mouse := get_local_mouse_position()
		if Rect2(Vector2.ZERO, size).has_point(mouse):
			var cell := Vector2i(mouse / CELL)
			var extent := Vector2i(selected.size.y, selected.size.x) if selected_rotation else selected.size
			var color := Color(0.4, 0.9, 0.5, 0.65) if model.can_place(selected, cell, selected_rotation) else Color(1, 0.3, 0.3, 0.65)
			draw_rect(Rect2(Vector2(cell) * CELL, Vector2(extent) * CELL), color)
