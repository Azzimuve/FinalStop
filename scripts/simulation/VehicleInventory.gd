extends RefCounted

const CargoItem = preload("res://scripts/simulation/CargoItem.gd")
const SIZE := Vector2i(24, 8)

# Размещение отделено от данных предмета: один и тот же груз сохраняет свою сущность.
var placements: Array[Dictionary] = []
var dimensions: Vector2i


func _init(grid_size: Vector2i = SIZE) -> void:
	dimensions = grid_size


func can_place(item: CargoItem, cell: Vector2i, rotated: bool) -> bool:
	var extent := Vector2i(item.size.y, item.size.x) if rotated else item.size
	var area := Rect2i(cell, extent)
	if not Rect2i(Vector2i.ZERO, dimensions).encloses(area):
		return false
	for placement in placements:
		if placement.item != item and area.intersects(Rect2i(placement.cell, placement.extent)):
			return false
	return true


func place(item: CargoItem, cell: Vector2i, rotated: bool) -> bool:
	if not can_place(item, cell, rotated):
		return false
	remove(item)
	placements.append({"item": item, "cell": cell, "extent": Vector2i(item.size.y, item.size.x) if rotated else item.size, "rotated": rotated})
	return true


func remove(item: CargoItem) -> void:
	for index in range(placements.size() - 1, -1, -1):
		if placements[index].item == item:
			placements.remove_at(index)


func contains(item: CargoItem) -> bool:
	for placement in placements:
		if placement.item == item:
			return true
	return false


func auto_load(items: Array[CargoItem]) -> bool:
	var before := placements.duplicate()
	var pending: Array[CargoItem] = []
	for item in items:
		if not contains(item):
			pending.append(item)
	if _pack(pending, 0):
		return true
	placements = before
	return false


func _pack(items: Array[CargoItem], index: int) -> bool:
	if index == items.size():
		return true
	var item := items[index]
	for y in range(dimensions.y):
		for x in range(dimensions.x):
			for rotated in [false, true]:
				if place(item, Vector2i(x, y), rotated):
					if _pack(items, index + 1):
						return true
					remove(item)
	return false
