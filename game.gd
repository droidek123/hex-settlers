extends Node2D

@export var hex_scene: PackedScene
@export var vertex_scene: PackedScene
@export var road_scene: PackedScene

var resource_bag = [
	"wood", "wood", "wood", "wood",
	"brick", "brick", "brick",
	"sheep", "sheep", "sheep", "sheep",
	"wheat", "wheat", "wheat", "wheat",
	"ore", "ore", "ore",
	"desert"
]

var number_bag = [
	2, 3, 3, 4, 4, 5, 5, 6, 6,
	8, 8, 9, 9, 10, 10, 11, 11, 12
]

var hex_size := 42.0
var map_radius := 2
var board_offset := Vector2(670, 280)

var hex_positions: Array[Vector2] = []
var hex_infos := []
var vertices_by_key := {}
var roads_by_key := {}

var current_player_index := 0
var has_rolled_this_turn := false

var player_names = [
	"Gracz 1",
	"Gracz 2"
]

var player_colors = [
	Color.BLUE,
	Color.RED
]

var player_settlement_counts = [0, 0]

var victory_points = [0, 0]
var points_to_win := 5
var game_over := false

# SETUP POCZĄTKOWY:
# Gracz 1 -> Gracz 2 -> Gracz 2 -> Gracz 1
var setup_phase := true
var setup_sequence = [0, 1, 1, 0]
var setup_step := 0
var setup_waiting_for_road := false
var setup_last_vertex = null

var player_resources = [
	{
		"wood": 20,
		"brick": 20,
		"sheep": 20,
		"wheat": 20,
		"ore": 20
	},
	{
		"wood": 20,
		"brick": 20,
		"sheep": 20,
		"wheat": 20,
		"ore": 20
	}
]

var road_cost = {
	"wood": 1,
	"brick": 1,
	"sheep": 0,
	"wheat": 0,
	"ore": 0
}

var settlement_cost = {
	"wood": 1,
	"brick": 1,
	"sheep": 1,
	"wheat": 1,
	"ore": 0
}

var city_cost = {
	"wood": 0,
	"brick": 0,
	"sheep": 0,
	"wheat": 2,
	"ore": 3
}

var turn_label: Label
var dice_label: Label
var resources_label: Label

var trade_from_option: OptionButton
var trade_to_option: OptionButton
var trade_info_label: Label

var resource_order = ["wood", "brick", "sheep", "wheat", "ore"]

func _ready():
	randomize()
	add_to_group("game")

	current_player_index = setup_sequence[setup_step]

	create_turn_ui()

	generate_board()
	generate_vertices()
	generate_roads()

	update_turn_ui()
	update_resources_ui()

func create_turn_ui():
	var canvas := CanvasLayer.new()
	add_child(canvas)

	turn_label = Label.new()
	turn_label.position = Vector2(20, 20)
	turn_label.add_theme_font_size_override("font_size", 24)
	canvas.add_child(turn_label)

	var roll_button := Button.new()
	roll_button.text = "Rzuć kostką"
	roll_button.position = Vector2(20, 60)
	roll_button.size = Vector2(140, 40)
	roll_button.pressed.connect(roll_dice)
	canvas.add_child(roll_button)

	var end_turn_button := Button.new()
	end_turn_button.text = "Koniec tury"
	end_turn_button.position = Vector2(20, 110)
	end_turn_button.size = Vector2(140, 40)
	end_turn_button.pressed.connect(next_turn)
	canvas.add_child(end_turn_button)

	dice_label = Label.new()
	dice_label.position = Vector2(20, 165)
	dice_label.add_theme_font_size_override("font_size", 18)
	dice_label.text = "Rzut: -"
	canvas.add_child(dice_label)

	resources_label = Label.new()
	resources_label.position = Vector2(20, 200)
	resources_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(resources_label)
	create_trade_ui(canvas)

func update_turn_ui():
	if game_over:
		return

	if setup_phase:
		if setup_waiting_for_road:
			turn_label.text = "Setup: " + get_current_player_name() + " - postaw drogę"
		else:
			turn_label.text = "Setup: " + get_current_player_name() + " - postaw osadę"
	else:
		turn_label.text = "Tura: " + get_current_player_name()

	turn_label.modulate = get_current_player_color()

func update_resources_ui():
	var text := ""

	for i in range(player_names.size()):
		var res = player_resources[i]

		text += player_names[i] + ":\n"
		text += "  Punkty: " + str(victory_points[i]) + " / " + str(points_to_win) + "\n"
		text += "  Drewno: " + str(res["wood"]) + "\n"
		text += "  Cegła: " + str(res["brick"]) + "\n"
		text += "  Owce: " + str(res["sheep"]) + "\n"
		text += "  Zboże: " + str(res["wheat"]) + "\n"
		text += "  Ruda: " + str(res["ore"]) + "\n"

		if i < player_names.size() - 1:
			text += "\n"

	resources_label.text = text

func next_turn():
	if game_over:
		return

	if setup_phase:
		print("Najpierw zakończ setup: postaw osadę i drogę")
		return

	current_player_index += 1

	if current_player_index >= player_names.size():
		current_player_index = 0

	has_rolled_this_turn = false
	dice_label.text = "Rzut: -"

	update_turn_ui()

	print("Teraz gra: " + get_current_player_name())

func roll_dice():
	if game_over:
		return

	if setup_phase:
		print("Najpierw zakończ setup")
		return

	if has_rolled_this_turn:
		print("Już rzucałeś kostką w tej turze")
		return

	var die_1 := randi_range(1, 6)
	var die_2 := randi_range(1, 6)
	var result := die_1 + die_2

	has_rolled_this_turn = true

	dice_label.text = "Rzut: " + str(die_1) + " + " + str(die_2) + " = " + str(result)

	print("Wypadło: " + str(result))

	produce_resources(result)
	update_resources_ui()

func produce_resources(rolled_number: int):
	for hex_info in hex_infos:
		if hex_info["number"] != rolled_number:
			continue

		var resource_type = hex_info["resource_type"]

		if resource_type == "desert":
			continue

		var vertex_keys = hex_info["vertex_keys"]

		for vertex_key in vertex_keys:
			if not vertices_by_key.has(vertex_key):
				continue

			var vertex = vertices_by_key[vertex_key]

			if vertex.occupied and vertex.owner_id >= 0:
				var amount := 1

				if vertex.is_city:
					amount = 2

				add_resource(vertex.owner_id, resource_type, amount)

				print(
					player_names[vertex.owner_id]
					+ " dostaje +"
					+ str(amount)
					+ " "
					+ get_resource_name_pl(resource_type)
				)

func add_resource(player_id: int, resource_type: String, amount: int):
	if player_id < 0:
		return

	if player_id >= player_resources.size():
		return

	player_resources[player_id][resource_type] += amount

func get_resource_name_pl(resource_type: String) -> String:
	match resource_type:
		"wood":
			return "drewno"
		"brick":
			return "cegła"
		"sheep":
			return "owce"
		"wheat":
			return "zboże"
		"ore":
			return "ruda"
		_:
			return resource_type

func get_current_player_id() -> int:
	return current_player_index

func get_current_player_name() -> String:
	return player_names[current_player_index]

func get_current_player_color() -> Color:
	return player_colors[current_player_index]

func generate_board():
	hex_positions.clear()
	hex_infos.clear()

	var resources = resource_bag.duplicate()
	var numbers = number_bag.duplicate()

	resources.shuffle()
	numbers.shuffle()

	for q in range(-map_radius, map_radius + 1):
		for r in range(-map_radius, map_radius + 1):
			if abs(q + r) > map_radius:
				continue

			var hex = hex_scene.instantiate()
			add_child(hex)

			var pos = axial_to_world(q, r) + board_offset
			hex.position = pos
			hex_positions.append(pos)

			hex.resource_type = resources.pop_back()

			if hex.resource_type == "desert":
				hex.number = 0
			else:
				hex.number = numbers.pop_back()

			hex.refresh()

			var vertex_keys: Array[String] = []

			for i in range(6):
				var angle = deg_to_rad(60 * i)
				var corner_pos = pos + Vector2(cos(angle), sin(angle)) * hex_size
				var key = get_vertex_key(corner_pos)
				vertex_keys.append(key)

			hex_infos.append({
				"node": hex,
				"resource_type": hex.resource_type,
				"number": hex.number,
				"vertex_keys": vertex_keys
			})

func generate_vertices():
	vertices_by_key.clear()

	for center_pos in hex_positions:
		for i in range(6):
			var angle = deg_to_rad(60 * i)
			var corner_pos = center_pos + Vector2(cos(angle), sin(angle)) * hex_size

			var key = get_vertex_key(corner_pos)

			if vertices_by_key.has(key):
				continue

			var vertex = vertex_scene.instantiate()
			add_child(vertex)

			vertex.position = corner_pos
			vertex.z_index = 10

			vertices_by_key[key] = vertex

func generate_roads():
	roads_by_key.clear()

	for center_pos in hex_positions:
		var corner_keys: Array[String] = []

		for i in range(6):
			var angle = deg_to_rad(60 * i)
			var corner_pos = center_pos + Vector2(cos(angle), sin(angle)) * hex_size
			var key = get_vertex_key(corner_pos)
			corner_keys.append(key)

		for i in range(6):
			var key_a = corner_keys[i]
			var key_b = corner_keys[(i + 1) % 6]

			var road_key = get_road_key(key_a, key_b)

			if roads_by_key.has(road_key):
				continue

			if not vertices_by_key.has(key_a) or not vertices_by_key.has(key_b):
				continue

			var vertex_a = vertices_by_key[key_a]
			var vertex_b = vertices_by_key[key_b]

			var road = road_scene.instantiate()
			add_child(road)

			road.setup(vertex_a, vertex_b)
			road.z_index = 5

			vertex_a.connected_roads.append(road)
			vertex_b.connected_roads.append(road)

			roads_by_key[road_key] = road

func register_settlement(player_id: int):
	player_settlement_counts[player_id] += 1
	victory_points[player_id] += 1

	update_resources_ui()
	check_victory(player_id)

func register_city(player_id: int):
	victory_points[player_id] += 1

	update_resources_ui()
	check_victory(player_id)

func check_victory(player_id: int):
	if victory_points[player_id] >= points_to_win:
		game_over = true

		turn_label.text = "Wygrywa: " + player_names[player_id]
		turn_label.modulate = player_colors[player_id]

		print(player_names[player_id] + " wygrywa grę!")

func can_build_settlement(vertex) -> bool:
	if game_over:
		return false

	if vertex.occupied:
		return false

	if not is_vertex_far_enough(vertex):
		print("Nie można budować osady obok innej osady")
		return false

	var player_id = get_current_player_id()

	if setup_phase:
		if setup_waiting_for_road:
			print("Najpierw postaw drogę przy ostatniej osadzie")
			return false

		return true

	if not can_afford_settlement(player_id):
		print("Brakuje surowców na osadę")
		return false

	for road in vertex.connected_roads:
		if road.occupied and road.owner_id == player_id:
			return true

	return false

func can_upgrade_city(vertex) -> bool:
	if game_over:
		return false

	if setup_phase:
		print("Nie można budować miasta w setupie")
		return false

	if not vertex.occupied:
		return false

	if vertex.is_city:
		print("To już jest miasto")
		return false

	var player_id = get_current_player_id()

	if vertex.owner_id != player_id:
		print("To nie jest twoja osada")
		return false

	if not can_afford_city(player_id):
		print("Brakuje surowców na miasto")
		return false

	return true

func can_build_road(road) -> bool:
	if game_over:
		return false

	if road.occupied:
		return false

	var player_id = get_current_player_id()

	if setup_phase:
		if not setup_waiting_for_road:
			print("Najpierw postaw osadę")
			return false

		if road.vertex_a != setup_last_vertex and road.vertex_b != setup_last_vertex:
			print("Droga w setupie musi wychodzić z ostatniej osady")
			return false

		return true

	if not can_afford_road(player_id):
		print("Brakuje surowców na drogę")
		return false

	if road.vertex_a.owner_id == player_id:
		return true

	if road.vertex_b.owner_id == player_id:
		return true

	for connected_road in road.vertex_a.connected_roads:
		if connected_road.occupied and connected_road.owner_id == player_id:
			return true

	for connected_road in road.vertex_b.connected_roads:
		if connected_road.occupied and connected_road.owner_id == player_id:
			return true

	return false

func get_vertex_key(pos: Vector2) -> String:
	return "%d_%d" % [int(round(pos.x)), int(round(pos.y))]

func get_road_key(key_a: String, key_b: String) -> String:
	var keys = [key_a, key_b]
	keys.sort()
	return keys[0] + "_" + keys[1]

func axial_to_world(q: int, r: int) -> Vector2:
	var x = hex_size * (3.0 / 2.0 * q)
	var y = hex_size * (sqrt(3) / 2.0 * q + sqrt(3) * r)
	return Vector2(x, y)

func has_resources(player_id: int, cost: Dictionary) -> bool:
	var resources = player_resources[player_id]

	for resource_type in cost.keys():
		if resources[resource_type] < cost[resource_type]:
			return false

	return true

func pay_resources(player_id: int, cost: Dictionary):
	var resources = player_resources[player_id]

	for resource_type in cost.keys():
		resources[resource_type] -= cost[resource_type]

	update_resources_ui()

func can_afford_road(player_id: int) -> bool:
	return has_resources(player_id, road_cost)

func can_afford_settlement(player_id: int) -> bool:
	return has_resources(player_id, settlement_cost)

func can_afford_city(player_id: int) -> bool:
	return has_resources(player_id, city_cost)

func pay_for_road(player_id: int):
	pay_resources(player_id, road_cost)

func pay_for_settlement(player_id: int):
	pay_resources(player_id, settlement_cost)

func pay_for_city(player_id: int):
	pay_resources(player_id, city_cost)

func is_setup_phase() -> bool:
	return setup_phase

func is_vertex_far_enough(vertex) -> bool:
	for road in vertex.connected_roads:
		var other_vertex = get_other_vertex(road, vertex)

		if other_vertex != null and other_vertex.occupied:
			return false

	return true

func get_other_vertex(road, vertex):
	if road.vertex_a == vertex:
		return road.vertex_b

	if road.vertex_b == vertex:
		return road.vertex_a

	return null

func on_settlement_built(vertex, player_id: int):
	if setup_phase:
		setup_waiting_for_road = true
		setup_last_vertex = vertex
		update_turn_ui()

func on_city_built(vertex, player_id: int):
	register_city(player_id)
	print(player_names[player_id] + " rozbudował osadę do miasta")

func on_road_built(road, player_id: int):
	if not setup_phase:
		return

	setup_waiting_for_road = false
	setup_last_vertex = null

	setup_step += 1

	if setup_step >= setup_sequence.size():
		setup_phase = false
		current_player_index = 0
		has_rolled_this_turn = false
		dice_label.text = "Rzut: -"

		print("Setup zakończony. Zaczyna normalna gra.")
	else:
		current_player_index = setup_sequence[setup_step]
		print("Setup: teraz " + get_current_player_name())

	update_turn_ui()

func create_trade_ui(canvas: CanvasLayer):
	var trade_x := 360
	var trade_y := 20

	var trade_title := Label.new()
	trade_title.text = "Handel 4:1"
	trade_title.position = Vector2(trade_x, trade_y)
	trade_title.add_theme_font_size_override("font_size", 20)
	canvas.add_child(trade_title)

	var from_label := Label.new()
	from_label.text = "Oddajesz:"
	from_label.position = Vector2(trade_x, trade_y + 35)
	canvas.add_child(from_label)

	trade_from_option = OptionButton.new()
	trade_from_option.position = Vector2(trade_x, trade_y + 60)
	trade_from_option.size = Vector2(120, 32)
	canvas.add_child(trade_from_option)

	var to_label := Label.new()
	to_label.text = "Dostajesz:"
	to_label.position = Vector2(trade_x + 140, trade_y + 35)
	canvas.add_child(to_label)

	trade_to_option = OptionButton.new()
	trade_to_option.position = Vector2(trade_x + 140, trade_y + 60)
	trade_to_option.size = Vector2(120, 32)
	canvas.add_child(trade_to_option)

	for i in range(resource_order.size()):
		var resource_type = resource_order[i]
		var resource_name = get_resource_name_pl(resource_type)

		trade_from_option.add_item(resource_name, i)
		trade_to_option.add_item(resource_name, i)

	trade_from_option.select(0)
	trade_to_option.select(1)

	var trade_button := Button.new()
	trade_button.text = "Wymień 4:1"
	trade_button.position = Vector2(trade_x, trade_y + 105)
	trade_button.size = Vector2(140, 40)
	trade_button.pressed.connect(trade_4_to_1)
	canvas.add_child(trade_button)

	trade_info_label = Label.new()
	trade_info_label.text = ""
	trade_info_label.visible = false
	canvas.add_child(trade_info_label)

func trade_4_to_1():
	if game_over:
		return

	if setup_phase:
		trade_info_label.text = "Handel dostępny po setupie"
		print("Handel dostępny dopiero po setupie")
		return

	var from_idx := trade_from_option.get_selected_id()
	var to_idx := trade_to_option.get_selected_id()

	if from_idx < 0 or to_idx < 0:
		return

	var from_resource = resource_order[from_idx]
	var to_resource = resource_order[to_idx]

	if from_resource == to_resource:
		trade_info_label.text = "Wybierz różne surowce"
		print("Nie można wymienić surowca na ten sam surowiec")
		return

	var player_id = get_current_player_id()
	var resources = player_resources[player_id]

	if resources[from_resource] < 4:
		trade_info_label.text = "Brakuje: " + get_resource_name_pl(from_resource)
		print("Brakuje surowców do handlu 4:1")
		return

	resources[from_resource] -= 4
	resources[to_resource] += 1

	update_resources_ui()

	var message = (
		get_current_player_name()
		+ " wymienił 4 "
		+ get_resource_name_pl(from_resource)
		+ " na 1 "
		+ get_resource_name_pl(to_resource)
	)

	trade_info_label.text = message
	print(message)
