extends Control

const Profile = preload("res://scripts/orders/PassengerProfile.gd")
const Order = preload("res://scripts/orders/DeliveryOrder.gd")
signal decided(allow: bool)

@export var applicants: Array[Profile]
@export var tutorial_passenger: Profile
## Номер документа → имя в полученной сводке.
@export var wanted: Dictionary[String, String]
@export var blacklist: Dictionary[String, String]

@onready var person: Node2D = %Person
@onready var allow_button: Button = %Allow
@onready var refuse_button: Button = %Refuse
var order: Order
var approaching: Tween
var waiting := false
var paper_motion: Tween

func _ready() -> void:
	allow_button.pressed.connect(_decide.bind(true))
	refuse_button.pressed.connect(_decide.bind(false))
	%Clip.toggled.connect(_toggle_papers)
	visibility_changed.connect(_on_visibility_changed)

func _toggle_papers(opened: bool) -> void:
	if paper_motion:
		paper_motion.kill()
	var sheet: Control = %Sheet
	if opened:
		if not %Drawer.visible:
			sheet.position.y = -sheet.size.y
		%Drawer.show()
	paper_motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	paper_motion.tween_property(sheet, "position:y", 0.0 if opened else -sheet.size.y, 0.22)
	if not opened:
		paper_motion.tween_callback(%Drawer.hide)

func _put_papers_away() -> void:
	if paper_motion:
		paper_motion.kill()
	%Drawer.hide()
	%Clip.set_pressed_no_signal(false)
	%Tabs.current_tab = 0

func _on_visibility_changed() -> void:
	if not visible:
		_put_papers_away()
		if approaching:
			approaching.kill()
		waiting = false

func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and %Clip.button_pressed and event.is_action_pressed("ui_cancel"):
		%Clip.button_pressed = false
		%Clip.grab_focus()
		get_viewport().set_input_as_handled()

func prepare_manifest(model: Order, tutorial: bool) -> bool:
	if not model.manifest.is_empty():
		return model.manifest.size() == model.passenger_count
	if tutorial and tutorial_passenger != null and model.passenger_count == 1:
		model.manifest.append(tutorial_passenger)
		return true
	var pool := applicants.filter(func(profile: Profile): return profile != null)
	if pool.size() < model.passenger_count:
		return false
	pool.shuffle()
	for index in range(model.passenger_count):
		model.manifest.append(pool[index])
	return true

func open(model: Order, seats: int) -> void:
	order = model
	var roster := PackedStringArray()
	for profile in order.manifest:
		roster.append("%s   № %s" % [profile.booked_name, profile.booked_number])
	%Roster.text = "%s → %s\n\n%s" % [order.pickup_city_name, order.delivery_city_name, "\n".join(roster)]
	%Wanted.text = _entries(wanted)
	%Blacklist.text = _entries(blacklist)
	show()
	_present(seats)

func _entries(records: Dictionary) -> String:
	var lines := PackedStringArray()
	for number in records:
		lines.append("%s   № %s" % [records[number], number])
	return "\n".join(lines) if not lines.is_empty() else "Записей нет"

func _present(seats: int) -> void:
	_put_papers_away()
	var index := order.decisions.size()
	var profile := order.manifest[index]
	%Heading.text = "Посадка   ·   %d из %d" % [index + 1, order.passenger_count]
	%Document.text = "%s\n№ %s" % [profile.document_name(), profile.document_number()]
	%Speech.text = "«Здравствуйте. Вот мои документы»."
	%Illustration.texture = profile.portrait
	%IdPhoto.texture = profile.portrait
	%IdPhoto.visible = profile.portrait != null
	%Silhouette.visible = profile.portrait == null
	%Silhouette.color = profile.coat_color
	%Hair.color = profile.hair_color
	%Glasses.visible = profile.glasses
	allow_button.disabled = true
	refuse_button.disabled = true
	waiting = false
	%Identity.hide()
	%Speech.hide()
	if approaching:
		approaching.kill()
	person.position = Vector2(-50,0)
	person.modulate.a = 0.0
	approaching = create_tween().set_parallel(true)
	approaching.tween_property(person, "position", Vector2.ZERO, 0.38).set_trans(Tween.TRANS_SINE)
	approaching.tween_property(person, "modulate:a", 1.0, 0.3)
	approaching.chain().tween_callback(_show_document.bind(seats))

func _show_document(seats: int) -> void:
	%Identity.show()
	%Speech.show()
	waiting = true
	allow_button.disabled = seats <= 0
	refuse_button.disabled = false

func _decide(allow: bool) -> void:
	if not waiting or not visible or (allow and allow_button.disabled):
		return
	waiting = false
	decided.emit(allow)
