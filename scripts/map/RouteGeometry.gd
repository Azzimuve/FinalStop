extends RefCounted

const WorldMapData = preload("res://scripts/WorldMapData.gd")


static func length(points: Array[Vector2]) -> float:
	var distance := 0.0
	for index in range(points.size() - 1):
		distance += points[index].distance_to(points[index + 1])
	return distance


static func remaining_points(points: Array[Vector2], progress: float) -> Array[Vector2]:
	var remaining: Array[Vector2] = []
	if points.size() < 2:
		return remaining

	var total_length := length(points)
	if total_length <= 0.0 or progress >= 1.0:
		return remaining
	var target_distance := total_length * clampf(progress, 0.0, 1.0)
	var distance_so_far := 0.0
	for index in range(points.size() - 1):
		var segment_length := points[index].distance_to(points[index + 1])
		if target_distance <= distance_so_far + segment_length:
			var segment_progress := (target_distance - distance_so_far) / segment_length
			remaining.append(points[index].lerp(points[index + 1], segment_progress))
			for next_index in range(index + 1, points.size()):
				remaining.append(points[next_index])
			return remaining
		distance_so_far += segment_length
	return remaining


static func position_at(points: Array[Vector2], progress: float) -> Vector2:
	if points.is_empty():
		return WorldMapData.WORLD_CENTER
	if points.size() == 1:
		return points[0]

	var total_length := length(points)

	var target_distance := total_length * progress
	var distance_so_far := 0.0
	for index in range(points.size() - 1):
		var segment_length := points[index].distance_to(points[index + 1])
		if target_distance <= distance_so_far + segment_length:
			var segment_progress := (target_distance - distance_so_far) / segment_length
			return points[index].lerp(points[index + 1], segment_progress)
		distance_so_far += segment_length
	return points[-1]
