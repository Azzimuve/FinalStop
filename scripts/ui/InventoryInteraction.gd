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
var card: PanelContainer
var card_title: Label
var card_shape: ColorRect
var card_description: Label
var card_texture: TextureRect
var card_price: Label
var card_weight: Label
var cargo_capacity_kg: float = -1.0
var left: VehicleInventory
var right: VehicleInventory
var grids: Array[InventoryGrid] = []
var grid_scrolls: Array[ScrollContainer] = []
var right_title: Label
var info: Label
var menu: PopupMenu
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
	custom_minimum_size = Vector2(1200, 588)
	_label("Мой инвентарь · 6×12", Vector2(12, 8))
	var character_slots := CharacterSlots.new()
	character_slots.position = Vector2(12 + (VehicleInventory.SIZE.x * InventoryGrid.CELL - (CharacterSlots.SLOT_SIZE * 3.0 + CharacterSlots.GAP * 2.0)) / 2.0, 32)
	add_child(character_slots)
	right_title = _label("", Vector2(612, 8))
	for side in [false, true]:
		var scroll := ScrollContainer.new()
		scroll.position = Vector2(612, 32) if side else Vector2(12, 112)
		scroll.size = Vector2(576, 544) if side else Vector2(192, 384)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(scroll)
		grid_scrolls.append(scroll)
		var grid := InventoryGrid.new()
		scroll.add_child(grid)
		scroll.get_v_scroll_bar().value_changed.connect(func(_value: float):
			if card != null:
				card.hide()
			grid.queue_redraw()
		)
		scroll.get_h_scroll_bar().value_changed.connect(func(_value: float):
			if card != null:
				card.hide()
			grid.queue_redraw()
		)
		grid.clicked.connect(_click.bind(side))
		grid.context_requested.connect(_context.bind(side))
		grid.hovered.connect(_hover.bind(side))
		grid.mouse_exited.connect(func(): card.hide())
		grids.append(grid)
	info = _label("", Vector2(228, 32))
	info.size = Vector2(360, 512)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu = PopupMenu.new()
	add_child(menu)
	menu.id_pressed.connect(_context_action)
	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size.x = 320
	card.add_theme_font_size_override("font_size", 16)
	card.z_index = 10
	add_child(card)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(layout)
	card_title = Label.new()
	card_title.add_theme_font_size_override("font_size", 20)
	card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(card_title)
	card_shape = ColorRect.new()
	card_shape.color = Color(0.3, 0.65, 0.55)
	card_shape.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	layout.add_child(card_shape)
	card_texture = TextureRect.new()
	card_texture.custom_minimum_size = Vector2(160, 140)
	card_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layout.add_child(card_texture)
	card_description = Label.new()
	card_description.custom_minimum_size = Vector2(320, 100)
	card_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(card_description)
	var footer := HBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(footer)
	card_weight = Label.new()
	card_weight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_weight.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(card_weight)
	card_price = Label.new()
	card_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(card_price)
	for child in layout.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.hide()


func _hover(item: CargoItem, on_right: bool) -> void:
	if item == null or menu.visible:
		card.hide()
		return
	card_weight.text = "Вес: %s кг" % str(item.weight_kg) if item.weight_kg >= 0.0 else "Вес не задан"
	card_title.text = item.title
	card_description.text = item.description if not item.description.is_empty() else "Описание не задано"
	var effects := item.effects_text()
	if not effects.is_empty():
		card_description.text += "\n" + effects
	if item.has_uses:
		card_description.text += "\nОсталось: %d" % item.uses_remaining
	card_texture.texture = InventoryGrid.item_texture(item)
	card_texture.visible = card_texture.texture != null
	card_shape.visible = not card_texture.visible
	card_shape.custom_minimum_size = Vector2(item.size) * 20.0
	card_price.visible = trading
	if trading:
		card_price.text = "%.2f кр." % float(item_price.call(item, on_right)) if item.price_credits >= 0.0 else "Цена не задана"
	card.reset_size()
	var edge_margin := 16.0
	var cursor_gap := 18.0
	var cursor := get_global_mouse_position()
	var viewport_size := get_viewport_rect().size
	var screen_position := cursor + Vector2(cursor_gap, 0)
	if screen_position.x + card.size.x > viewport_size.x - edge_margin:
		screen_position.x = cursor.x - cursor_gap - card.size.x
	screen_position.x = clampf(screen_position.x, edge_margin, maxf(edge_margin, viewport_size.x - card.size.x - edge_margin))
	screen_position.y = clampf(screen_position.y, edge_margin, maxf(edge_margin, viewport_size.y - card.size.y - edge_margin))
	card.global_position = screen_position
	card.show()


func configure(player: VehicleInventory, other: VehicleInventory, caption: String) -> void:
	left = player
	right = other
	custom_minimum_size = Vector2(1200, 588) if right != null else Vector2(600, 588)
	size = custom_minimum_size
	grid_scrolls[0].size = Vector2(192, 384)
	info.size.x = 360
	grids[0].setup(left)
	grids[1].visible = right != null
	grid_scrolls[1].visible = right != null
	for scroll in grid_scrolls:
		scroll.scroll_vertical = 0
		scroll.scroll_horizontal = 0
	right_title.visible = right != null
	right_title.text = caption
	if right != null:
		grids[1].setup(right)
	reset_selection()


func _model(on_right: bool) -> VehicleInventory:
	return right if on_right else left


func reset_selection() -> void:
	click_item = null
	if card != null:
		card.hide()
	selected = null
	context_item = null
	menu.hide()
	refresh()


func refresh() -> void:
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
	card.hide()
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


func _label(text: String, at: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", 12)
	add_child(label)
	return label
