extends Control

const CargoItem = preload("res://scripts/simulation/CargoItem.gd")
const VehicleInventory = preload("res://scripts/simulation/VehicleInventory.gd")
const InventoryGrid = preload("res://scripts/ui/InventoryGrid.gd")
const CharacterSlots = preload("res://scripts/ui/CharacterSlots.gd")
const DOUBLE_CLICK_MSEC: int = 300

signal discarded(item: CargoItem)
signal used(item: CargoItem)
signal transferred(item: CargoItem, from_right: bool)

# Политика окна проверяет только условия переноса (заказ или оплата).
# Размещение, выбор, поворот и контекстное меню одинаковы для всех окон.
var transfer_check: Callable
var describe_item: Callable
var item_price: Callable
var trading: bool = false
@onready var card: Panel = $ItemCard
@onready var card_title: Label = $ItemCard/Layout/Title
@onready var card_shape: ColorRect = $ItemCard/Layout/Shape
@onready var card_description: Label = $ItemCard/Layout/Notes/Description
@onready var card_texture: TextureRect = $ItemCard/Layout/Texture
@onready var card_price: Label = $ItemCard/Layout/Footer/Price
@onready var card_weight: Label = $ItemCard/Layout/Footer/Weight
@export var single_inventory_width: float = 704.0
@export var dual_inventory_width: float = 1214.0
var cargo_capacity_kg: float = -1.0
var left: VehicleInventory
var right: VehicleInventory
@onready var grids: Array[InventoryGrid] = [$Truck/Diagram/Hold/Grid, $RightScroll/Grid]
@onready var character_slots: CharacterSlots = $Truck/Diagram/CharacterSlots
@onready var stock_scroll: ScrollContainer = $RightScroll
var inspected: CargoItem
var inspected_right := false
@onready var right_title: Label = $RightTitle
@onready var info: Label = $Info
@onready var menu: PopupMenu = $ContextMenu
var selected: CargoItem
var source_right: bool = false
var rotated: bool = false
var context_item: CargoItem
var context_right: bool = false
var click_item: CargoItem
var click_side: bool = false
var click_time: int = 0
var click_position: Vector2


func _ready() -> void:
	for index in range(grids.size()):
		var grid := grids[index]
		var side := index == 1
		grid.clicked.connect(_click.bind(side))
		grid.context_requested.connect(_context.bind(side))
		grid.hovered.connect(_hover.bind(side))
	menu.id_pressed.connect(_context_action)


func _hover(item: CargoItem, on_right: bool) -> void:
	if item == null or (item == inspected and on_right == inspected_right and card.visible):
		return
	$ItemCard/Layout/Notes.scroll_vertical = 0
	_show_card(item, on_right)


func _show_card(item: CargoItem, on_right: bool) -> void:
	inspected = item
	inspected_right = on_right
	$ItemCard/Layout/Footer/Dimensions.text = "%d × %d" % [item.size.x, item.size.y]
	card_weight.text = "%s кг" % String.num(item.weight_kg, 2) if item.weight_kg >= 0.0 else "Вес не указан"
	card_title.text = item.title
	card_description.text = item.description
	var effects := item.effects_text()
	if not effects.is_empty():
		card_description.text += "\n" + effects
	if item.has_uses:
		card_description.text += "\nОсталось: %d" % item.uses_remaining
	card_texture.texture = InventoryGrid.item_texture(item)
	card_texture.visible = card_texture.texture != null
	card_shape.visible = not card_texture.visible
	card_shape.custom_minimum_size = Vector2(item.size) * minf(20.0, 88.0 / maxi(item.size.x, item.size.y))
	card_price.visible = trading
	if trading:
		card_price.text = "%.2f кр." % float(item_price.call(item, on_right)) if item.price_credits >= 0.0 else "Цена не задана"
	card.get_node("Layout/Notes").visible = not card_description.text.is_empty()
	card.show()


func configure(player: VehicleInventory, other: VehicleInventory, caption: String) -> void:
	$PlayerTitle.text = "Урал  ·  кузов %d × %d" % [player.dimensions.x, player.dimensions.y]
	left = player
	right = other
	custom_minimum_size = Vector2(dual_inventory_width if right != null else single_inventory_width, custom_minimum_size.y)
	size = custom_minimum_size
	grids[0].setup(left)
	grids[1].visible = right != null
	stock_scroll.visible = right != null
	stock_scroll.scroll_vertical = 0
	stock_scroll.scroll_horizontal = 0
	right_title.visible = right != null
	right_title.text = caption
	inspected = null
	if right != null:
		grids[1].setup(right)
	reset_selection()


func _model(on_right: bool) -> VehicleInventory:
	return right if on_right else left


func reset_selection() -> void:
	click_item = null
	selected = null
	context_item = null
	menu.hide()
	refresh()


func refresh() -> void:
	if inspected == null or _model(inspected_right) == null or not _model(inspected_right).contains(inspected):
		inspected = null
		card.hide()
		for side: bool in [true, false]:
			var inventory := _model(side)
			if inventory != null and not inventory.placements.is_empty():
				_hover(inventory.placements[0].item, side)
				break
	else:
		_show_card(inspected, inspected_right)
	$Empty.visible = inspected == null
	if selected != null and not _model(source_right).contains(selected):
		selected = null
	for grid in grids:
		grid.selected = selected
		grid.selected_rotation = rotated
		grid.queue_redraw()
	info.text = ""
	if left != null and cargo_capacity_kg > 0.0:
		var weight := left.total_weight_kg()
		info.text = "Груз: %s / %s кг" % [str(weight), str(cargo_capacity_kg)]
		if left.has_unknown_weights():
			info.text += "\nВес неполный: есть предметы без веса."
		if weight > cargo_capacity_kg:
			info.text += "\nПерегруз: %.1f%%" % ((weight / cargo_capacity_kg - 1.0) * 100.0)
		info.text += "\n"
	info.text += "ЛКМ: взять / положить. R: поворот. ПКМ: меню."
	if right != null:
		info.text += "\nДвойной ЛКМ: перенос."
	if selected != null:
		info.text += "\n" + selected.title
	if describe_item.is_valid():
		info.text += "\n" + str(describe_item.call(selected, source_right))


func _choose(item: CargoItem, on_right: bool) -> void:
	_hover(item, on_right)
	selected = item
	source_right = on_right
	rotated = false
	if item != null:
		for placement in _model(on_right).placements:
			if placement.item == item:
				rotated = placement.rotated
				break
	refresh()


func _click(item: CargoItem, cell: Vector2i, on_right: bool) -> void:
	if menu.visible:
		return
	var now := Time.get_ticks_msec()
	var cursor := get_global_mouse_position()
	if item != null and item == click_item and selected == item and on_right == click_side and now - click_time <= DOUBLE_CLICK_MSEC and cursor.distance_to(click_position) <= 6.0:
		_double_click(item, cell, on_right)
		return
	click_item = null
	if selected == null:
		_choose(item, on_right)
		click_item = item
		click_side = on_right
		click_time = now
		click_position = cursor
	elif _move(selected, source_right, on_right, cell, rotated):
		reset_selection()


func _move(item: CargoItem, from_right: bool, to_right: bool, cell: Vector2i, rotation: bool) -> bool:
	var source := _model(from_right)
	var target := _model(to_right)
	if source == null or target == null or not source.contains(item):
		return false
	if source != target and transfer_check.is_valid():
		var reason := str(transfer_check.call(item, from_right))
		if not reason.is_empty():
			info.text = reason
			return false
	if not target.place(item, cell, rotation):
		info.text = "Недостаточно свободных клеток."
		return false
	# Перестановка внутри сетки уже выполнена place(): удалять предмет нельзя.
	if source != target:
		source.remove(item)
		transferred.emit(item, from_right)
	return true


func _double_click(item: CargoItem, _cell: Vector2i, on_right: bool) -> void:
	# Первый клик уже мог выбрать предмет. Снимаем захват даже при отказе.
	reset_selection()
	if item != null and right != null:
		auto_transfer(item, on_right)


func auto_transfer(item: CargoItem, from_right: bool) -> bool:
	var target := _model(not from_right)
	if target == null or not _model(from_right).contains(item):
		return false
	for rotation in [false, true]:
		for y in range(target.dimensions.y):
			for x in range(target.dimensions.x):
				var cell := Vector2i(x, y)
				if target.can_place(item, cell, rotation):
					var moved := _move(item, from_right, not from_right, cell, rotation)
					if moved:
						refresh()
					return moved
	info.text = "В противоположном инвентаре нет свободного места."
	return false


func handle_input(event: InputEvent) -> void:
	if menu.visible or selected == null:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		rotated = not rotated
		refresh()
		get_viewport().set_input_as_handled()


func _context(item: CargoItem, _cell: Vector2i, on_right: bool) -> void:
	click_item = null
	context_item = item
	context_right = on_right
	menu.clear()
	_hover(item, on_right)
	if trading and on_right:
		menu.add_item("Купить", 3)
	if not on_right:
		if trading and item.price_credits >= 0.0:
			menu.add_item("Продать", 5)
		menu.add_item("Повернуть", 0)
		menu.add_item("Выбросить", 1)
		if item.can_use():
			menu.add_item("Использовать", 2)
	menu.position = Vector2i(get_viewport().get_mouse_position())
	menu.popup()


func _context_action(action: int) -> void:
	var item := context_item
	var model := _model(context_right)
	if item == null or model == null or not model.contains(item):
		return
	match action:
		5:
			if trading and not context_right and item.price_credits >= 0.0:
				reset_selection()
				auto_transfer(item, false)
			return
		3:
			if trading and context_right:
				reset_selection()
				auto_transfer(item, true)
			return
		0:
			if context_right:
				return
			if selected == item:
				rotated = not rotated
			else:
				for placement in model.placements:
					if placement.item == item:
						if not model.place(item, placement.cell, not placement.rotated):
							info.text = "Для поворота недостаточно места."
							return
						break
		1:
			if context_right:
				return
			model.remove(item)
			discarded.emit(item)
		2:
			if context_right:
				return
			used.emit(item)
	refresh()
