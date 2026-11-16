extends Control

const VehicleState = preload("res://scripts/simulation/VehicleState.gd")
const InventoryGrid = preload("res://scripts/ui/InventoryGrid.gd")
const VehiclePart = preload("res://scripts/simulation/VehiclePart.gd")
const CELL: float = InventoryGrid.CELL
const SLOTS := [
	["engine", "Двигатель"],
	["front_left_wheel", "Переднее левое"],
	["front_right_wheel", "Переднее правое"],
	["transmission", "Трансмиссия"],
	["rear_left_wheel", "Заднее левое"],
	["rear_right_wheel", "Заднее правое"],
]

var vehicle: VehicleState
var editable: bool = false
var selectable: bool = false
var selected: VehiclePart
var show_condition: bool = true
signal slot_clicked(part_id: String)


func _ready() -> void:
	custom_minimum_size = Vector2(240, 288)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if editable or selectable:
		mouse_filter = Control.MOUSE_FILTER_STOP
	size = custom_minimum_size


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		queue_redraw()
	if not (editable or selectable) or not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	for index in range(SLOTS.size()):
		var id: String = SLOTS[index][0]
		var origin := _slot_origin(index)
		if Rect2(origin, Vector2(VehicleState.PART_SLOT_SIZES[id]) * CELL).has_point(event.position):
			slot_clicked.emit(id)
			accept_event()
			return


func show_vehicle(model: VehicleState) -> void:
	vehicle = model
	queue_redraw()


func _slot_origin(index: int) -> Vector2:
	return Vector2(8 + (index % 3) * 80, 22 + (index / 3) * 144)


func _draw() -> void:
	if vehicle == null:
		return
	var font := ThemeDB.fallback_font
	for index in range(SLOTS.size()):
		var id: String = SLOTS[index][0]
		var part := vehicle.get_part(id)
		var origin := _slot_origin(index)
		var slot_size: Vector2i = VehicleState.PART_SLOT_SIZES[id]
		draw_string(font, origin - Vector2(0, 7), SLOTS[index][1], HORIZONTAL_ALIGNMENT_LEFT, 76, 9)
		# Фон — место установки. Заполненная область — существующая деталь.
		draw_rect(Rect2(origin, Vector2(slot_size) * CELL), Color(0.12, 0.16, 0.17))
		if part != null:
			var part_rect := Rect2(origin + Vector2.ONE, Vector2(part.size) * CELL - Vector2.ONE * 2)
			var textured := InventoryGrid.draw_item(self, part, part_rect, false, Color(0.85, 0.7, 0.3) if selected == part else Color(0.26, 0.52, 0.46))
			if textured and selected == part:
				draw_rect(part_rect, Color(0.85, 0.7, 0.3), false)
		for y in range(slot_size.y):
			for x in range(slot_size.x):
				draw_rect(Rect2(origin + Vector2(x, y) * CELL, Vector2.ONE * CELL), Color(0.65, 0.75, 0.72), false)
		if part != null:
			if show_condition:
				draw_string(font, origin + Vector2(0, slot_size.y * CELL + 11), "%.1f%%" % part.condition_percent, HORIZONTAL_ALIGNMENT_LEFT, 76, 9)
			draw_string(font, origin + Vector2(0, slot_size.y * CELL + 23), part.model_name, HORIZONTAL_ALIGNMENT_LEFT, 76, 9)
		if editable and selected != null and Rect2(origin, Vector2(slot_size) * CELL).has_point(get_local_mouse_position()):
			var fits := part == null and selected.slot_type == VehicleState.slot_type(id) and selected.size == slot_size
			var preview_rect := Rect2(origin, Vector2(selected.size) * CELL)
			var color := Color(0.4, 0.9, 0.5, 0.65) if fits else Color(1, 0.3, 0.3, 0.65)
			InventoryGrid.draw_item(self, selected, preview_rect, false, color, Color(1, 1, 1, 0.65))
			draw_rect(preview_rect, color, false)
