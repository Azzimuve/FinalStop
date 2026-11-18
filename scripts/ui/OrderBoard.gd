extends Control

const DeliveryOrder = preload("res://scripts/orders/DeliveryOrder.gd")
const GameClock = preload("res://scripts/simulation/GameClock.gd")

signal order_selected(order: DeliveryOrder)
signal closed

@onready var orders_cards: HBoxContainer = $BoardPanel/BoardContent/OrdersCards
@onready var close_button: Button = $BoardPanel/BoardContent/CloseOrdersButton


func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)


func _on_close_pressed() -> void:
	hide()
	closed.emit()


func show_offers(offers: Array[DeliveryOrder], clock: GameClock) -> void:
	visible = true
	for child in orders_cards.get_children():
		orders_cards.remove_child(child)
		child.queue_free()

	for order in offers:
		var card = preload("res://scenes/ui/OrderCard.tscn").instantiate()
		orders_cards.add_child(card)
		card.show_order(order, clock)
		card.selected.connect(order_selected.emit)
