@tool
extends Control

const VehicleInventory = preload("res://scripts/simulation/VehicleInventory.gd")
const CargoItem = preload("res://scripts/simulation/CargoItem.gd")
const CELL: float = 32.0
@export var preview_dimensions := Vector2i(6, 12)

static var _textures: Dictionary = {}


static func item_texture(item: CargoItem) -> Texture2D:
	if item.texture_path.is_empty():
		return null
	if not _textures.has(item.texture_path):
		if not ResourceLoader.exists(item.texture_path):
			return null
		_textures[item.texture_path] = load(item.texture_path) as Texture2D
	return _textures[item.texture_path] as Texture2D


static func draw_item(canvas: CanvasItem, item: CargoItem, rect: Rect2, rotated: bool, color: Color, tint: Color = Color.WHITE) -> bool:
	var texture := item_texture(item)
	if texture == null:
		canvas.draw_rect(rect, color)
		return false
	var available := Vector2(rect.size.y, rect.size.x) if rotated else rect.size
	var texture_size := texture.get_size()
	var fitted := texture_size * minf(available.x / texture_size.x, available.y / texture_size.y)
	canvas.draw_set_transform(rect.get_center(), PI / 2.0 if rotated else 0.0)
	canvas.draw_texture_rect(texture, Rect2(-fitted / 2.0, fitted), false, tint)
	canvas.draw_set_transform(Vector2.ZERO)
	return true

signal clicked(item: CargoItem, cell: Vector2i)
signal context_requested(item: CargoItem, cell: Vector2i)
signal hovered(item: CargoItem)
var model: VehicleInventory
var selected: CargoItem
var selected_rotation: bool = false


func setup(inventory: VehicleInventory) -> void:
	model = inventory
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
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
	else:
		clicked.emit(item, cell)
	accept_event()


func _draw() -> void:
	if model == null and not Engine.is_editor_hint():
		return
	var dimensions := model.dimensions if model != null else preview_dimensions
	var placements: Array = model.placements if model != null else []
	var grid_size := Vector2(dimensions) * CELL
	var grid_color := Color(0.47, 0.39, 0.27)
	draw_rect(Rect2(Vector2.ZERO, grid_size), Color(0.90, 0.82, 0.64, 0.87))
	for y in range(1, dimensions.y):
		draw_line(Vector2(0, y * CELL), Vector2(grid_size.x, y * CELL), grid_color, 1.0)
	for x in range(1, dimensions.x):
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, grid_size.y), grid_color, 1.0)
	for index in range(placements.size()):
		var placement: Dictionary = placements[index]
		var rect := Rect2(Vector2(placement.cell) * CELL + Vector2.ONE, Vector2(placement.extent) * CELL - Vector2.ONE * 2)
		var textured := draw_item(self, placement.item, rect, placement.rotated, Color(0.85, 0.7, 0.3) if selected == placement.item else Color(0.46, 0.48, 0.34))
		if textured and selected == placement.item:
			draw_rect(rect, Color(0.85, 0.7, 0.3), false)
		if not textured:
			draw_string(get_theme_default_font(), rect.position + Vector2(1, 9), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
	if selected != null:
		var mouse := get_local_mouse_position()
		if Rect2(Vector2.ZERO, grid_size).has_point(mouse):
			var cell := Vector2i(mouse / CELL)
			var extent := Vector2i(selected.size.y, selected.size.x) if selected_rotation else selected.size
			var color := Color(0.4, 0.9, 0.5, 0.65) if model.can_place(selected, cell, selected_rotation) else Color(1, 0.3, 0.3, 0.65)
			var preview_rect := Rect2(Vector2(cell) * CELL, Vector2(extent) * CELL)
			draw_item(self, selected, preview_rect, selected_rotation, color, Color(1, 1, 1, 0.65))
			draw_rect(preview_rect, color, false)
	# Четыре заполненные полосы дают одинаковую толщину без смещения обводки.
	# При масштабе 150% две логические единицы равны трём экранным пикселям.
	var border_width := 2.0
	var border_color := Color(0.29, 0.28, 0.21)
	draw_rect(Rect2(Vector2.ZERO, Vector2(grid_size.x, border_width)), border_color)
	draw_rect(Rect2(Vector2(0, grid_size.y - border_width), Vector2(grid_size.x, border_width)), border_color)
	draw_rect(Rect2(Vector2(0, border_width), Vector2(border_width, grid_size.y - border_width * 2.0)), border_color)
	draw_rect(Rect2(Vector2(grid_size.x - border_width, border_width), Vector2(border_width, grid_size.y - border_width * 2.0)), border_color)
