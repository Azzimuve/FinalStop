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
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(280.0, 400.0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var content := VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 12)
		card.add_child(content)
		_add_order_card_label(content, ("Срочный · %d кр." if order.is_urgent else "Доставка · %d кр.") % order.reward, 20)
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 10)
		content.add_child(details)
		_add_order_card_label(details, "%s → %s" % [order.pickup_city_name, order.delivery_city_name])
		_add_order_card_label(details, "От: %s\nДо: %s" % [order.pickup_name, order.delivery_name])
		_add_order_card_label(details, "До %s · %.1f км" % [clock.format_deadline(order.deadline_total_minutes), order.distance_km])
		var cargo_lines := PackedStringArray()
		for item in order.cargo:
			var short_title := item.title.trim_prefix("Тестовый ").trim_prefix("Тестовая ")
			cargo_lines.append("%s %d×%d" % [short_title, item.size.x, item.size.y])
		_add_order_card_label(details, "Груз:\n" + "\n".join(cargo_lines))
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(spacer)
		var choose_button := Button.new()
		choose_button.text = "Выбрать"
		choose_button.custom_minimum_size.y = 40.0
		choose_button.add_theme_font_size_override("font_size", 16)
		choose_button.pressed.connect(order_selected.emit.bind(order))
		content.add_child(choose_button)
		orders_cards.add_child(card)


func _add_order_card_label(parent: VBoxContainer, text: String, font_size: int = 16) -> void:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
