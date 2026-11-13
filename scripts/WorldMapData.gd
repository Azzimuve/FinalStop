extends RefCounted

# Временные данные для прототипа. Геометрия не является финальной картой.
const START_CITY_ID := "company_city"
const DELIVERY_CITY_ID := "nearby_settlement"
const BRANCH_CITY_ID := "northern_settlement"
const CENTRAL_JUNCTION_ID := "central_road_junction"
const START_LOCATION_ID := "company_start"
const DELIVERY_LOCATION_ID := "settlement_delivery"
const HOTEL_LOCATION_ID := "northern_settlement_hotel"
const WORLD_CENTER := Vector2(640.0, 360.0)


static func get_cities() -> Array[Dictionary]:
	return [
		{
			"id": START_CITY_ID,
			"name": "Город компании",
			"type": "city",
			"position": Vector2(250.0, 600.0),
			"entry_location_id": START_LOCATION_ID,
			"entrances": {CENTRAL_JUNCTION_ID: START_LOCATION_ID},
			"street_nodes": [
				{"id": START_LOCATION_ID, "position": Vector2(110.0, 15.0)},
				{"id": "company_depot_road", "position": Vector2(-20.0, 0.0)},
				{"id": "company_fuel_road", "position": Vector2(5.0, 25.0)},
				{"id": "company_north_junction", "position": Vector2(-5.0, -45.0)},
				{"id": "company_office_road", "position": Vector2(-45.0, -85.0)},
				{"id": "company_garage_road", "position": Vector2(55.0, -65.0)},
				{"id": "company_station_road", "position": Vector2(30.0, 45.0)},
			],
			"street_roads": [
				{"from": START_LOCATION_ID, "to": "company_depot_road"},
				{"from": "company_depot_road", "to": "company_fuel_road"},
				{"from": "company_depot_road", "to": "company_north_junction"},
				{"from": "company_north_junction", "to": "company_office_road"},
				{"from": "company_north_junction", "to": "company_garage_road"},
				{"from": "company_depot_road", "to": "company_station_road"},
			],
			"places": [
				{
					"id": "company_depot",
					"name": "Склад компании",
					"type": "warehouse",
					"position": Vector2(-20.0, 0.0),
					"road_node_id": "company_depot_road",
				},
				{
					"id": "company_fuel_station",
					"name": "Заправка",
					"type": "fuel_station",
					"position": Vector2(5.0, 25.0),
					"road_node_id": "company_fuel_road",
				},
				{
					"id": "company_office",
					"name": "Офис компании",
					"type": "company_office",
					"position": Vector2(-45.0, -85.0),
					"road_node_id": "company_office_road",
				},
				{"id": "company_garage", "name": "Гараж", "type": "garage", "position": Vector2(55.0, -65.0), "road_node_id": "company_garage_road"},
				{
					"id": "company_station",
					"name": "Автостанция",
					"type": "stop",
					"position": Vector2(30.0, 45.0),
					"road_node_id": "company_station_road",
				},
			],
		},
		{
			"id": DELIVERY_CITY_ID,
			"name": "Соседний посёлок",
			"type": "settlement",
			"position": Vector2(1030.0, 600.0),
			"entry_location_id": "settlement_west",
			"entrances": {CENTRAL_JUNCTION_ID: "settlement_west", BRANCH_CITY_ID: "settlement_north"},
			"street_nodes": [
				{"id": "settlement_west", "position": Vector2(-100.0, -25.0)},
				{"id": "settlement_center", "position": Vector2(-20.0, -25.0)},
				{"id": "settlement_fuel_road", "position": Vector2(-55.0, 45.0)},
				{"id": "settlement_delivery_road", "position": Vector2(0.0, 35.0)},
				{"id": "settlement_north", "position": Vector2(-5.0, -80.0)},
				{"id": "settlement_shop_road", "position": Vector2(40.0, -80.0)},
			],
			"street_roads": [
				{"from": "settlement_west", "to": "settlement_center"},
				{"from": "settlement_center", "to": "settlement_fuel_road"},
				{"from": "settlement_center", "to": "settlement_delivery_road"},
				{"from": "settlement_center", "to": "settlement_north"},
				{"from": "settlement_north", "to": "settlement_shop_road"},
			],
			"places": [
				{
					"id": "settlement_fuel_station",
					"name": "Заправка",
					"type": "fuel_station",
					"position": Vector2(-55.0, 45.0),
					"road_node_id": "settlement_fuel_road",
				},
				{
					"id": DELIVERY_LOCATION_ID,
					"name": "Пункт доставки",
					"type": "delivery_point",
					"position": Vector2(0.0, 35.0),
					"road_node_id": "settlement_delivery_road",
				},
				{"id": "settlement_shop", "name": "Магазин", "type": "store", "position": Vector2(40.0, -80.0), "road_node_id": "settlement_shop_road"},
			],
		},
		{
			"id": BRANCH_CITY_ID,
			"name": "Северный посёлок",
			"type": "settlement",
			"position": Vector2(640.0, 260.0),
			"entry_location_id": "northern_settlement_entry",
			"entrances": {CENTRAL_JUNCTION_ID: "northern_settlement_entry", DELIVERY_CITY_ID: "northern_settlement_east"},
			"street_nodes": [
				{"id": "northern_settlement_entry", "position": Vector2(0.0, 110.0)},
				{"id": "northern_settlement_east", "position": Vector2(110.0, 70.0)},
				{"id": "northern_settlement_center", "position": Vector2(0.0, 45.0)},
				{"id": "northern_settlement_hotel_road", "position": Vector2(-65.0, 20.0)},
				{"id": "northern_settlement_workshop_road", "position": Vector2(55.0, 75.0)},
			],
			"street_roads": [
				{"from": "northern_settlement_entry", "to": "northern_settlement_center"},
				{"from": "northern_settlement_center", "to": "northern_settlement_hotel_road"},
				{"from": "northern_settlement_center", "to": "northern_settlement_workshop_road"},
				{"from": "northern_settlement_workshop_road", "to": "northern_settlement_east"},
			],
			"places": [
				{
					"id": "northern_settlement_workshop",
					"name": "Мастерская",
					"type": "garage",
					"position": Vector2(55.0, 75.0),
					"road_node_id": "northern_settlement_workshop_road",
				},
				{
					"id": HOTEL_LOCATION_ID,
					"name": "Отель",
					"type": "hotel",
					"position": Vector2(-65.0, 20.0),
					"road_node_id": "northern_settlement_hotel_road",
				},
			],
		},
	]


static func get_road_junctions() -> Array[Dictionary]:
	return [
		{"id": CENTRAL_JUNCTION_ID, "position": Vector2(640.0, 600.0)},
	]


static func get_roads() -> Array[Dictionary]:
	return [
		{"from": START_CITY_ID, "to": CENTRAL_JUNCTION_ID},
		{"from": CENTRAL_JUNCTION_ID, "to": DELIVERY_CITY_ID},
		{"from": CENTRAL_JUNCTION_ID, "to": BRANCH_CITY_ID},
		{"from": DELIVERY_CITY_ID, "to": BRANCH_CITY_ID},
	]
