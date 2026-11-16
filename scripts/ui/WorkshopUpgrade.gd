extends AcceptDialog

const VehicleState = preload("res://scripts/simulation/VehicleState.gd")
const VehiclePart = preload("res://scripts/simulation/VehiclePart.gd")
const CargoItem = preload("res://scripts/simulation/CargoItem.gd")
const InventoryGrid = preload("res://scripts/ui/InventoryGrid.gd")
const CharacterSlots = preload("res://scripts/ui/CharacterSlots.gd")
const VehiclePartsView = preload("res://scripts/ui/VehiclePartsView.gd")

signal accepted(cost: float)
signal credits_changed(delta: float)
var vehicle: VehicleState
var parts_view: VehiclePartsView
var grid: InventoryGrid
var info: Label
var selected: VehiclePart
var selected_slot: String = ""
var rotated: bool = false
var parts_before: Dictionary
var inventory_before: Array[Dictionary]
var applied: bool = false
var cost: float
var credits: float
var content: Control
var diagnosis_button: Button
var diagnosed: bool = false
var diagnosis_cost: float


func _ready() -> void:
	dialog_hide_on_ok = false
	title = "Мастерская · Улучшить"
	size = Vector2i(1084, 612)
	ok_button_text = "Принять работу"
	add_cancel_button("Отмена")
	content = Control.new()
	content.custom_minimum_size = Vector2(1064, 562)
	add_child(content)
	var inventory_title := Label.new()
	inventory_title.text = "Мой инвентарь · 6×12"
	inventory_title.position = Vector2(12, 8)
	inventory_title.add_theme_font_size_override("font_size", 12)
	content.add_child(inventory_title)
	var character_slots := CharacterSlots.new()
	character_slots.position = Vector2(12 + (6 * InventoryGrid.CELL - (CharacterSlots.SLOT_SIZE * 3.0 + CharacterSlots.GAP * 2.0)) / 2.0, 32)
	content.add_child(character_slots)
	var parts_title := Label.new()
	parts_title.text = "Детали автомобиля"
	parts_title.position = Vector2(228, 8)
	parts_title.add_theme_font_size_override("font_size", 12)
	content.add_child(parts_title)
	parts_view = VehiclePartsView.new()
	parts_view.editable = true
	parts_view.position = Vector2(228, 32)
	content.add_child(parts_view)
	parts_view.slot_clicked.connect(_slot_clicked)
	grid = InventoryGrid.new()
	grid.position = Vector2(12, 112)
	content.add_child(grid)
	grid.clicked.connect(_inventory_clicked)
	diagnosis_button = Button.new()
	diagnosis_button.position = Vector2(228, 340)
	diagnosis_button.pressed.connect(_diagnose)
	content.add_child(diagnosis_button)
	info = Label.new()
	info.position = Vector2(500, 40)
	info.size = Vector2(540, 500)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 12)
	content.add_child(info)
	confirmed.connect(_accept_work)
	visibility_changed.connect(_on_hide)


func open(model: VehicleState, money: float, service_cost: float, inspection_cost: float) -> void:
	vehicle = model
	credits = money
	cost = service_cost
	diagnosis_cost = inspection_cost
	diagnosed = false
	parts_before = vehicle.parts_snapshot()
	inventory_before = vehicle.inventory.placements.duplicate()
	selected = null
	selected_slot = ""
	rotated = false
	applied = false
	_refresh()
	popup_centered()


func _refresh() -> void:
	parts_view.show_condition = diagnosed
	parts_view.show_vehicle(vehicle)
	parts_view.selected = selected
	grid.setup(vehicle.inventory)
	grid.selected = selected
	grid.selected_rotation = rotated
	diagnosis_button.text = "Диагностика выполнена" if diagnosed else "Диагностика — %.0f кр." % diagnosis_cost
	diagnosis_button.disabled = diagnosed or credits < diagnosis_cost
	get_ok_button().disabled = not vehicle.is_complete() or credits < cost or not _has_part_changes()
	info.text = "ЛКМ: взять деталь, затем выбрать ячейку или место в инвентаре.\nРабота: %.0f кр. Баланс: %.2f кр." % [cost, credits]
	if not vehicle.is_complete():
		info.text += "\nУстановите двигатель, трансмиссию и все четыре колеса."
	elif not _has_part_changes():
		info.text += "\nДетали не изменены — оплачивать нечего."
	elif selected != null:
		info.text += "\n%s · R: поворот" % selected.title
		if diagnosed:
			info.text += " · %.1f%%" % selected.condition_percent


func _diagnose() -> void:
	if diagnosed or credits < diagnosis_cost:
		return
	credits -= diagnosis_cost
	diagnosed = true
	credits_changed.emit(-diagnosis_cost)
	_refresh()


func _slot_clicked(id: String) -> void:
	if selected == null:
		selected = vehicle.get_part(id)
		selected_slot = id if selected != null else ""
		rotated = false
		_refresh()
		return
	if selected_slot == id:
		selected = null
		selected_slot = ""
		_refresh()
		return
	if vehicle.get_part(id) != null:
		info.text = "Сначала снимите установленную деталь в инвентарь."
		return
	if vehicle.replace_part(id, selected):
		if selected_slot.is_empty():
			vehicle.inventory.remove(selected)
		else:
			vehicle.remove_part(selected_slot)
		selected = null
		selected_slot = ""
		_refresh()
	else:
		info.text = "Деталь не подходит к выбранному месту установки."


func _inventory_clicked(item: CargoItem, cell: Vector2i) -> void:
	if selected == null:
		if item is VehiclePart:
			selected = item as VehiclePart
			selected_slot = ""
			rotated = false
			_refresh()
		return
	if vehicle.inventory.place(selected, cell, rotated):
		if not selected_slot.is_empty():
			vehicle.remove_part(selected_slot)
		selected = null
		selected_slot = ""
		_refresh()
	else:
		info.text = "Не хватает свободного места для детали."


func _input(event: InputEvent) -> void:
	if visible and selected != null and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		rotated = not rotated
		_refresh()


func _has_part_changes() -> bool:
	for id in VehicleState.PART_NAMES:
		if vehicle.get_part(id) != parts_before.get(id):
			return true
	return false


func _accept_work() -> void:
	if applied or not vehicle.is_complete() or credits < cost or not _has_part_changes():
		return
	applied = true
	accepted.emit(cost)
	hide()


func _on_hide() -> void:
	if visible:
		return
	if vehicle != null and not applied:
		vehicle.restore_parts(parts_before)
		vehicle.inventory.placements = inventory_before
	selected = null
