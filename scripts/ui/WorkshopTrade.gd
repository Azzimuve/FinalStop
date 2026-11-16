extends AcceptDialog

const ItemCatalog = preload("res://scripts/simulation/ItemCatalog.gd")

const VehicleInventory = preload("res://scripts/simulation/VehicleInventory.gd")
const VehiclePart = preload("res://scripts/simulation/VehiclePart.gd")
const CargoItem = preload("res://scripts/simulation/CargoItem.gd")
const InventoryInteraction = preload("res://scripts/ui/InventoryInteraction.gd")

signal credits_changed(delta: float)
signal discarded(item: CargoItem)
signal used(item: CargoItem)

var stock := VehicleInventory.new(Vector2i(16, 24))
var interaction: InventoryInteraction
var credits: float
var settings: GameBalanceSettings
var is_store: bool = false
var stock_initialized: bool = false


func _ready() -> void:
	title = "Магазин · Торговля" if is_store else "Мастерская · Торговля"
	size = Vector2i(1224, 640)
	ok_button_text = "Закрыть"
	# Единственный прямой Control сохраняет раскладку внутри AcceptDialog.
	interaction = InventoryInteraction.new()
	add_child(interaction)
	interaction.transfer_check = _check_trade
	interaction.describe_item = _describe
	interaction.trading = true
	interaction.item_price = _price
	interaction.transferred.connect(_complete_trade)
	interaction.discarded.connect(func(item: CargoItem): discarded.emit(item))
	interaction.used.connect(func(item: CargoItem): used.emit(item))
	visibility_changed.connect(_on_visibility_changed)


func open(inventory: VehicleInventory, money: float, balance: GameBalanceSettings) -> void:
	credits = money
	settings = balance
	if not stock_initialized:
		var item := ItemCatalog.create("cigarettes" if is_store else "upgraded_engine")
		if item != null:
			stock.place(item, Vector2i.ZERO, false)
		if is_store:
			var water := ItemCatalog.create("water_bottle")
			if water != null:
				stock.auto_load([water])
		stock_initialized = true
	interaction.configure(inventory, stock, "Инвентарь торговца · 16×24")
	popup_centered()


func _price(item: CargoItem, buying: bool) -> float:
	var condition := (item as VehiclePart).condition_percent / 100.0 if item is VehiclePart else 1.0
	return item.price_credits if buying else item.price_credits * settings.trader_buyback_multiplier * condition


func _check_trade(item: CargoItem, buying: bool) -> String:
	if item.price_credits < 0.0:
		return "Для этого предмета цена не задана."
	if buying and credits < _price(item, true):
		return "Недостаточно кредитов для покупки."
	return ""


func _complete_trade(item: CargoItem, buying: bool) -> void:
	var delta := _price(item, buying) * (-1.0 if buying else 1.0)
	credits += delta
	credits_changed.emit(delta)


func _describe(item: CargoItem, buying: bool) -> String:
	var text := "Баланс: %.2f кр." % credits
	if item != null:
		if item.price_credits < 0.0:
			text += "\nДля этого предмета цена не задана."
		else:
			text += "\nЦена: %.2f кр." % _price(item, buying)
		if item is VehiclePart:
			text += "\nСостояние: %.1f%%" % item.condition_percent
			if item.slot_type == "engine":
				text += "\nСкорость: ×%.2f" % float(item.parameters.get("speed_multiplier", 1.0))
	return text


func _on_visibility_changed() -> void:
	if not visible and interaction != null:
		interaction.reset_selection()


func _input(event: InputEvent) -> void:
	if visible:
		interaction.handle_input(event)
