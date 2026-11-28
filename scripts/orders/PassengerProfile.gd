extends Resource

@export var booked_name: String
@export var booked_number: String
## Пустые поля означают, что предъявленный документ совпадает с заявкой.
@export var presented_name: String
@export var presented_number: String
@export var portrait: Texture2D
@export var coat_color := Color("#607b71")
@export var hair_color := Color("#413830")
@export var glasses := false

func document_name() -> String:
	return booked_name if presented_name.is_empty() else presented_name

func document_number() -> String:
	return booked_number if presented_number.is_empty() else presented_number
