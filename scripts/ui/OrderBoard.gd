extends Control

const DeliveryOrder = preload("res://scripts/orders/DeliveryOrder.gd")
const GameClock = preload("res://scripts/simulation/GameClock.gd")
const OrderCard = preload("res://scripts/ui/OrderCard.gd")

signal order_selected(order: DeliveryOrder)
signal closed

@export var map_shade := Color(0.20, 0.17, 0.12, 0.17)
@export var document_scene: PackedScene = preload("res://scenes/ui/OrderCard.tscn")
@export_range(0.15, 1.5, 0.05, "suffix:s") var exchange_seconds := 0.55

@onready var radio_space: Control = %RadioSpace
@onready var folder: Control = %Folder
@onready var choose_button: Button = %Choose
var waybill: OrderCard
var filed: Array[OrderCard] = []
var exchange: Tween
var next_number := 1

func _ready() -> void:
	%CloseOrdersButton.pressed.connect(_on_close_pressed)
	choose_button.pressed.connect(_take_order)
	%Desk.resized.connect(_fit_folder)
	visibility_changed.connect(_on_visibility_changed)

func _fit_folder() -> void:
	var available: Vector2 = %Desk.size - Vector2(28, 14)
	var factor := maxf(0.01, minf(available.x / folder.size.x, available.y / folder.size.y))
	folder.scale = Vector2.ONE * factor
	folder.position = ((%Desk.size - folder.size * factor) * 0.5).round()

func _on_visibility_changed() -> void:
	if visible:
		_fit_folder()
	else:
		_settle()

func _on_close_pressed() -> void:
	hide()
	closed.emit()

func _take_order() -> void:
	if is_visible_in_tree() and waybill != null and exchange == null:
		order_selected.emit(waybill.order)

func update_clock(clock: GameClock, next_refresh := -1.0) -> void:
	%Time.text = clock.time_text()
	%Refresh.visible = next_refresh >= 0.0
	if %Refresh.visible:
		%Refresh.text = "Обновление в " + clock.format_deadline(next_refresh)

func show_offers(offers: Array[DeliveryOrder], clock: GameClock, next_refresh := -1.0) -> void:
	_settle()
	var previous := waybill.order if waybill != null else null
	for document in %Documents.get_children():
		%Documents.remove_child(document)
		document.queue_free()
	filed.clear()
	waybill = null
	var preview := previous if offers.has(previous) else (null if offers.is_empty() else offers[0])
	for order in offers:
		if order.dispatch_number == 0:
			order.dispatch_number = next_number
			next_number += 1
		var document := document_scene.instantiate() as OrderCard
		%Documents.add_child(document)
		document.fill(order, clock)
		document.gui_input.connect(_on_paper_input.bind(document))
		if order == preview:
			waybill = document
		else:
			filed.append(document)
	%Empty.visible = offers.is_empty()
	update_clock(clock, next_refresh)
	_settle()
	show()

func _stack_position(slot: int) -> Vector2:
	var weight := float(slot) / maxi(1, filed.size() - 1)
	return %StackBack.position.lerp(%StackFront.position, weight)

func _settle() -> void:
	if exchange != null:
		exchange.kill()
		exchange = null
	for slot in filed.size():
		var sheet := filed[slot]
		%Documents.move_child(sheet, slot)
		sheet.position = _stack_position(slot)
		sheet.scale = %StackBack.scale
		sheet.rotation = 0.0
		sheet.set_filed(true)
	if waybill != null:
		%Documents.move_child(waybill, -1)
		waybill.position = %ReadingPlace.position
		waybill.scale = %ReadingPlace.scale
		waybill.rotation = 0.0
		waybill.set_filed(false)
	choose_button.disabled = waybill == null

func _on_paper_input(event: InputEvent, sheet: OrderCard) -> void:
	if event.is_action_pressed("ui_accept") and sheet.has_focus():
		sheet.accept_event()
		_select(sheet)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var at: Vector2 = sheet.get_transform() * event.position
		if not Geometry2D.is_point_in_polygon(at, %PocketFront.polygon):
			sheet.accept_event()
			_select(sheet)

func _select(incoming: OrderCard) -> void:
	var slot := filed.find(incoming)
	if slot < 0 or exchange != null:
		return
	var outgoing := waybill
	var pocket_pos := incoming.position
	var reading_pos := outgoing.position
	waybill = incoming
	filed[slot] = outgoing
	choose_button.disabled = true
	# Возвращаемый лист сразу входит под выбранный, сохраняя порядок остальных листов.
	%Documents.move_child(outgoing, slot)
	exchange = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	exchange.tween_method(_move_sheets.bind(incoming, outgoing, pocket_pos, reading_pos), 0.0, 1.0, exchange_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	exchange.tween_callback(_settle)

func _move_sheets(t: float, incoming: OrderCard, outgoing: OrderCard, pocket: Vector2, reading: Vector2) -> void:
	# Разные дуги оставляют оба листа видимыми при встречном движении.
	var arc := sin(PI * t)
	incoming.position = pocket.lerp(reading, t) + Vector2(0, -25.0 * arc)
	outgoing.position = reading.lerp(pocket, t) + Vector2(0, 22.0 * arc)
	incoming.scale = %StackBack.scale.lerp(%ReadingPlace.scale, t)
	outgoing.scale = %ReadingPlace.scale.lerp(%StackBack.scale, t)
	incoming.rotation = -0.028 * arc
	outgoing.rotation = 0.055 * arc
