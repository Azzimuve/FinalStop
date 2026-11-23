extends AcceptDialog

const VehicleInventory = preload("res://scripts/simulation/VehicleInventory.gd")
const VehicleState = preload("res://scripts/simulation/VehicleState.gd")
const VehiclePart = preload("res://scripts/simulation/VehiclePart.gd")
const CargoItem = preload("res://scripts/simulation/CargoItem.gd")
const InventoryInteraction = preload("res://scripts/ui/InventoryInteraction.gd")

signal credits_changed(delta: float)
signal discarded(item: CargoItem)
signal used(item: CargoItem)

var stock := VehicleInventory.new(Vector2i(16, 24))
@onready var interaction: InventoryInteraction = $Interaction
var credits: float
var settings: GameBalanceSettings
@export var is_store: bool = false
var stocks_by_city: Dictionary = {}
@export var initial_stock: Array[CargoItem] = []


func _ready() -> void:
	title = "Магазин · Торговля" if is_store else "Мастерская · Торговля"
	interaction.transfer_check = _check_trade
	interaction.describe_item = _describe
	interaction.trading = true
	interaction.item_price = _price
	interaction.transferred.connect(_complete_trade)
	interaction.discarded.connect(func(item: CargoItem): discarded.emit(item))
	interaction.used.connect(func(item: CargoItem): used.emit(item))
	visibility_changed.connect(_on_visibility_changed)


func open(vehicle: VehicleState, money: float, balance: GameBalanceSettings, city_id: String, place_id: String) -> void:
	var inventory := vehicle.inventory
	interaction.character_slots.show_vehicle(vehicle)
	credits = money
	settings = balance
	stock = _stock_for_location(city_id, place_id)
	interaction.configure(inventory, stock, "Инвентарь торговца · 16×24")
	popup_centered()


func _stock_for_location(city_id: String, place_id: String) -> VehicleInventory:
	if not stocks_by_city.has(city_id):
		stocks_by_city[city_id] = {}
	var city_stocks: Dictionary = stocks_by_city[city_id]
	if not city_stocks.has(place_id):
		var inventory := VehicleInventory.new(Vector2i(16, 24))
		for definition in initial_stock:
			if definition != null:
				inventory.auto_load([definition.duplicate(true) as CargoItem])
		city_stocks[place_id] = inventory
	return city_stocks[place_id]


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
