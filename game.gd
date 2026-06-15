extends Node2D

@export var hex_scene: PackedScene
@export var vertex_scene: PackedScene
@export var road_scene: PackedScene

var player_count := 2
var start_canvas: CanvasLayer

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
var board_offset := Vector2(650, 450)

var hex_positions: Array[Vector2] = []
var hex_infos := []
var vertices_by_key := {}
var roads_by_key := {}

var current_player_index := 0
var has_rolled_this_turn := false

class PlayerData:
	var name: String
	var color: Color
	var is_cpu: bool = false
	var personality: CatanEngine.Personality = CatanEngine.Personality.RANDOM
	var settlement_count: int = 0
	var road_count : int = 0
	var city_count : int = 0
	var vp: int = 0
	var resources : Dictionary
	
var player_data: Array[PlayerData] = []

var available_player_colors = [
	Color.BLUE,
	Color.RED,
	Color(0.6, 0.2, 1.0),
	Color(1.0, 0.55, 0.0)
]

var max_roads := 15
var max_settlements := 5
var max_cities := 4

var points_to_win := 10
var game_over := false

# NAJDŁUŻSZA DROGA
var longest_road_owner := -1
var longest_road_length := 0
var longest_road_min_length := 5
var longest_road_bonus_points := 2

# SETUP POCZĄTKOWY:
# 2 graczy: 0, 1, 1, 0
# 3 graczy: 0, 1, 2, 2, 1, 0
# 4 graczy: 0, 1, 2, 3, 3, 2, 1, 0
var setup_phase := true
var setup_sequence: Array[int] = []
var setup_step := 0
var setup_waiting_for_road := false
var setup_last_vertex = null

var starting_resources = {
	"wood": 0,
	"brick": 0,
	"sheep": 0,
	"wheat": 0,
	"ore": 0
}

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
var extra_resources_label: Label
var message_label: Label

var message_history: Array[String] = []
var max_messages := 5

var trade_from_option: OptionButton
var trade_to_option: OptionButton
var trade_info_label: Label

var resource_order = ["wood", "brick", "sheep", "wheat", "ore"]

# ZŁODZIEJ
var robber_hex_info = null
var robber_marker: Node2D
var waiting_for_robber := false

#silnik
var engine: CatanEngine
var cpu_thinking := false
var cpu_action_delay := 0.01

func _ready():
	randomize()
	add_to_group("game")

	create_start_menu()


func create_start_menu():
	start_canvas = CanvasLayer.new()
	add_child(start_canvas)

	var panel := Panel.new()
	panel.position = Vector2(430, 170)
	panel.size = Vector2(540, 540)
	start_canvas.add_child(panel)

	var title := Label.new()
	title.text = "HexSettlers"
	title.position = Vector2(585, 210)
	title.add_theme_font_size_override("font_size", 36)
	start_canvas.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Wybierz tryb gry"
	subtitle.position = Vector2(590, 275)
	subtitle.add_theme_font_size_override("font_size", 22)
	start_canvas.add_child(subtitle)

	var button_local := Button.new()
	button_local.text = "2 graczy lokalnie"
	button_local.position = Vector2(575, 330)
	button_local.size = Vector2(250, 45)
	button_local.pressed.connect(func(): start_game(2, [false, false]))
	start_canvas.add_child(button_local)

	var button_cpu_2 := Button.new()
	button_cpu_2.text = "1 gracz + 1 CPU"
	button_cpu_2.position = Vector2(575, 390)
	button_cpu_2.size = Vector2(250, 45)
	button_cpu_2.pressed.connect(func(): start_game(2, [false, true]))
	start_canvas.add_child(button_cpu_2)

	var button_cpu_3 := Button.new()
	button_cpu_3.text = "1 gracz + 2 CPU"
	button_cpu_3.position = Vector2(575, 450)
	button_cpu_3.size = Vector2(250, 45)
	button_cpu_3.pressed.connect(func(): start_game(3, [false, true, true]))
	start_canvas.add_child(button_cpu_3)

	var button_cpu_4 := Button.new()
	button_cpu_4.text = "1 gracz + 3 CPU"
	button_cpu_4.position = Vector2(575, 510)
	button_cpu_4.size = Vector2(250, 45)
	button_cpu_4.pressed.connect(func(): start_game(4, [false, true, true, true]))
	start_canvas.add_child(button_cpu_4)

	var button_cpu_only := Button.new()
	button_cpu_only.text = "4 CPU"
	button_cpu_only.position = Vector2(575, 570)
	button_cpu_only.size = Vector2(250, 45)
	button_cpu_only.pressed.connect(func(): start_game(4, [true, true, true, true]))
	start_canvas.add_child(button_cpu_only)

func start_game(count: int, cpu_flags: Array = []):
	if start_canvas != null:
		start_canvas.queue_free()
		start_canvas = null

	engine = CatanEngine.new()

	setup_players(count, cpu_flags)

	create_turn_ui()

	generate_board()
	generate_vertices()
	generate_roads()
	create_robber_marker()

	update_turn_ui()
	update_resources_ui()

	show_message("Gra rozpoczęta: " + str(player_count) + " graczy")

func setup_players(count: int, cpu_flags: Array = []):
	player_count = clampi(count, 2, 4)

	player_data.clear()
	setup_sequence.clear()

	for i in range(player_count):
		
		var player = PlayerData.new()
		player.name = "Gracz " + str(i + 1)
		player.color = available_player_colors[i]

		player.settlement_count = 0
		player.road_count = 0
		player.city_count = 0
		player.vp = 0

		player.resources = starting_resources.duplicate()

		if i < cpu_flags.size() && cpu_flags[i]:
			player.is_cpu = true
			player.personality = engine.get_random_personality()
		else:
			player.is_cpu = false
		
		player_data.append(player)
		
	for i in range(player_count):
		setup_sequence.append(i)

	for i in range(player_count - 1, -1, -1):
		setup_sequence.append(i)

	setup_step = 0
	setup_phase = true
	setup_waiting_for_road = false
	setup_last_vertex = null
	current_player_index = setup_sequence[setup_step]
	has_rolled_this_turn = false
	game_over = false

	longest_road_owner = -1
	longest_road_length = 0

	waiting_for_robber = false
	robber_hex_info = null
	cpu_thinking = false

	message_history.clear()

func create_turn_ui():
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var left_panel := Panel.new()
	left_panel.position = Vector2(10, 10)
	left_panel.size = Vector2(330, 870)
	left_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(left_panel)

	var right_panel := Panel.new()
	right_panel.position = Vector2(960, 10)
	right_panel.size = Vector2(420, 870)
	right_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(right_panel)

	var message_panel := Panel.new()
	message_panel.position = Vector2(360, 700)
	message_panel.size = Vector2(580, 180)
	message_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(message_panel)

	var message_title := Label.new()
	message_title.text = "Komunikaty"
	message_title.position = Vector2(380, 720)
	message_title.add_theme_font_size_override("font_size", 18)
	canvas.add_child(message_title)

	message_label = Label.new()
	message_label.position = Vector2(380, 755)
	message_label.size = Vector2(540, 105)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_font_size_override("font_size", 15)
	message_label.text = ""
	canvas.add_child(message_label)

	turn_label = Label.new()
	turn_label.position = Vector2(30, 30)
	turn_label.size = Vector2(300, 70)
	turn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	turn_label.add_theme_font_size_override("font_size", 24)
	canvas.add_child(turn_label)

	var roll_button := Button.new()
	roll_button.text = "Rzuć kostką"
	roll_button.position = Vector2(30, 120)
	roll_button.size = Vector2(140, 40)
	roll_button.pressed.connect(roll_dice)
	canvas.add_child(roll_button)

	var end_turn_button := Button.new()
	end_turn_button.text = "Koniec tury"
	end_turn_button.position = Vector2(30, 170)
	end_turn_button.size = Vector2(140, 40)
	end_turn_button.pressed.connect(next_turn)
	canvas.add_child(end_turn_button)

	dice_label = Label.new()
	dice_label.position = Vector2(30, 235)
	dice_label.add_theme_font_size_override("font_size", 18)
	dice_label.text = "Rzut: -"
	canvas.add_child(dice_label)

	resources_label = Label.new()
	resources_label.position = Vector2(30, 275)
	resources_label.size = Vector2(300, 580)
	resources_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resources_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(resources_label)

	create_trade_ui(canvas)


func show_message(message):
	var message_text := str(message)

	message_history.append(message_text)

	if message_history.size() > max_messages:
		message_history.pop_front()

	if message_label == null:
		return

	var text := ""

	for item in message_history:
		text += item + "\n"

	message_label.text = text


func update_turn_ui():
	if game_over:
		return

	if waiting_for_robber:
		turn_label.text = "Tura: " + get_current_player_name() + " - przesuń złodzieja"
	elif setup_phase:
		if setup_waiting_for_road:
			turn_label.text = "Setup: " + get_current_player_name() + " - postaw drogę"
		else:
			turn_label.text = "Setup: " + get_current_player_name() + " - postaw osadę"
	else:
		turn_label.text = "Tura: " + get_current_player_name()

	if is_current_player_cpu():
		turn_label.text += " [CPU]"

	turn_label.modulate = get_current_player_color()

	call_deferred("run_cpu_turn_if_needed")

func update_resources_ui():
	var left_text := ""
	var right_text := ""

	if longest_road_owner == -1:
		left_text += "Najdłuższa droga: brak\n\n"
	else:
		left_text += "Najdłuższa droga: " + player_data[longest_road_owner].name + " (" + str(longest_road_length) + ")\n\n"

	for i in range(player_data.size()):
		var block := get_player_status_text(i)

		if i < 2:
			left_text += block
		else:
			right_text += block

	resources_label.text = left_text

	if extra_resources_label != null:
		if right_text == "":
			extra_resources_label.text = "Przy 3–4 graczach tutaj pojawią się ich zasoby."
		else:
			extra_resources_label.text = right_text


func get_player_status_text(player_id: int) -> String:
	var data : PlayerData = player_data[player_id]

	var text := ""
	text += data.name + ":\n"
	text += "  Punkty: " + str(data.vp) + " / " + str(points_to_win) + "\n"
	text += "  Osady: " + str(data.settlement_count) + " / " + str(max_settlements) + "\n"
	text += "  Miasta: " + str(data.city_count) + " / " + str(max_cities) + "\n"
	text += "  Drogi: " + str(data.road_count) + " / " + str(max_roads) + "\n"
	text += "  Drewno: " + str(data.resources["wood"]) + "\n"
	text += "  Cegła: " + str(data.resources["brick"]) + "\n"
	text += "  Owce: " + str(data.resources["sheep"]) + "\n"
	text += "  Zboże: " + str(data.resources["wheat"]) + "\n"
	text += "  Ruda: " + str(data.resources["ore"]) + "\n\n"

	return text


func next_turn():
	if game_over:
		return

	if setup_phase:
		show_message("Najpierw zakończ setup: postaw osadę i drogę")
		return

	if waiting_for_robber:
		show_message("Najpierw przesuń złodzieja")
		return

	current_player_index += 1

	if current_player_index >= player_data.size():
		current_player_index = 0

	has_rolled_this_turn = false
	dice_label.text = "Rzut: -"

	update_turn_ui()

	show_message("Teraz gra: " + get_current_player_name())


func roll_dice():
	if game_over:
		return

	if setup_phase:
		show_message("Najpierw zakończ setup")
		return

	if waiting_for_robber:
		show_message("Najpierw przesuń złodzieja")
		return

	if has_rolled_this_turn:
		show_message("Już rzucałeś kostką w tej turze")
		return

	var die_1 := randi_range(1, 6)
	var die_2 := randi_range(1, 6)
	var result := die_1 + die_2

	has_rolled_this_turn = true

	dice_label.text = "Rzut: " + str(die_1) + " + " + str(die_2) + " = " + str(result)

	show_message("Wypadło: " + str(result))

	if result == 7:
		start_robber_phase()
		return

	produce_resources(result)
	update_resources_ui()


func produce_resources(rolled_number: int):
	for hex_info in hex_infos:
		if hex_info["number"] != rolled_number:
			continue

		if hex_info.get("has_robber", false):
			show_message("Złodziej blokuje pole z numerem " + str(rolled_number))
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

				show_message(
					player_data[vertex.owner_id].name
					+ " dostaje +"
					+ str(amount)
					+ " "
					+ get_resource_name_pl(resource_type)
				)


func add_resource(player_id: int, resource_type: String, amount: int):
	if player_id < 0:
		return

	if player_id >= player_data.size():
		return

	player_data[player_id].resources[resource_type] += amount


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
	return player_data[current_player_index].name


func get_current_player_color() -> Color:
	return player_data[current_player_index].color


func generate_board():
	hex_positions.clear()
	hex_infos.clear()
	robber_hex_info = null

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

			var has_robber := false

			if hex.resource_type == "desert":
				has_robber = true

			var hex_info = {
				"node": hex,
				"position": pos,
				"axial_q": q,
				"axial_r": r,
				"resource_type": hex.resource_type,
				"number": hex.number,
				"vertex_keys": vertex_keys,
				"has_robber": has_robber
			}

			hex_infos.append(hex_info)

			if has_robber:
				robber_hex_info = hex_info


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
	player_data[player_id].settlement_count += 1
	player_data[player_id].vp += 1

	refresh_longest_road()
	update_resources_ui()
	check_victory(player_id)


func register_road(player_id: int):
	player_data[player_id].road_count += 1

	refresh_longest_road()
	update_resources_ui()


func register_city(player_id: int):
	player_data[player_id].city_count += 1
	player_data[player_id].settlement_count = max(player_data[player_id].settlement_count - 1, 0)

	player_data[player_id].vp += 1

	update_resources_ui()
	check_victory(player_id)


func check_victory(player_id: int):
	if player_data[player_id].vp >= points_to_win:
		game_over = true

		turn_label.text = "Wygrywa: " + player_data[player_id].name
		turn_label.modulate = player_data[player_id].color

		show_message(player_data[player_id].name + " wygrywa grę!")


func can_build_settlement(vertex) -> bool:
	if game_over:
		return false

	if waiting_for_robber:
		show_message("Najpierw przesuń złodzieja")
		return false

	if vertex.occupied:
		return false

	if not is_vertex_far_enough(vertex):
		show_message("Nie można budować osady obok innej osady")
		return false

	var player_id = get_current_player_id()

	if player_data[player_id].settlement_count >= max_settlements:
		show_message("Osiągnięto limit osad")
		return false

	if setup_phase:
		if setup_waiting_for_road:
			show_message("Najpierw postaw drogę przy ostatniej osadzie")
			return false

		return true

	if not can_afford_settlement(player_id):
		show_message("Brakuje surowców na osadę")
		return false

	for road in vertex.connected_roads:
		if road.occupied and road.owner_id == player_id:
			return true

	return false


func can_upgrade_city(vertex) -> bool:
	if game_over:
		return false

	if waiting_for_robber:
		show_message("Najpierw przesuń złodzieja")
		return false

	if setup_phase:
		show_message("Nie można budować miasta w setupie")
		return false

	if not vertex.occupied:
		return false

	if vertex.is_city:
		show_message("To już jest miasto")
		return false

	var player_id = get_current_player_id()

	if player_data[player_id].city_count >= max_cities:
		show_message("Osiągnięto limit miast")
		return false

	if vertex.owner_id != player_id:
		show_message("To nie jest twoja osada")
		return false

	if not can_afford_city(player_id):
		show_message("Brakuje surowców na miasto")
		return false

	return true


func can_build_road(road) -> bool:
	if game_over:
		return false

	if waiting_for_robber:
		show_message("Najpierw przesuń złodzieja")
		return false

	if road.occupied:
		return false

	var player_id = get_current_player_id()

	if player_data[player_id].road_count >= max_roads:
		show_message("Osiągnięto limit dróg")
		return false

	if setup_phase:
		if not setup_waiting_for_road:
			show_message("Najpierw postaw osadę")
			return false

		if road.vertex_a != setup_last_vertex and road.vertex_b != setup_last_vertex:
			show_message("Droga w setupie musi wychodzić z ostatniej osady")
			return false

		return true

	if not can_afford_road(player_id):
		show_message("Brakuje surowców na drogę")
		return false

	if can_connect_road_through_vertex(road.vertex_a, player_id):
		return true

	if can_connect_road_through_vertex(road.vertex_b, player_id):
		return true

	return false


func can_connect_road_through_vertex(vertex, player_id: int) -> bool:
	if vertex.occupied and vertex.owner_id != player_id:
		return false

	if vertex.occupied and vertex.owner_id == player_id:
		return true

	for connected_road in vertex.connected_roads:
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
	var resources = player_data[player_id].resources

	for resource_type in cost.keys():
		if resources[resource_type] < cost[resource_type]:
			return false

	return true


func pay_resources(player_id: int, cost: Dictionary):
	var resources = player_data[player_id].resources

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
		if is_second_setup_round():
			give_starting_resources_from_vertex(vertex, player_id)

		setup_waiting_for_road = true
		setup_last_vertex = vertex
		update_turn_ui()


func is_second_setup_round() -> bool:
	return setup_step >= player_count


func give_starting_resources_from_vertex(vertex, player_id: int):
	var vertex_key = get_vertex_key(vertex.position)

	var gained = {
		"wood": 0,
		"brick": 0,
		"sheep": 0,
		"wheat": 0,
		"ore": 0
	}

	for hex_info in hex_infos:
		var resource_type = hex_info["resource_type"]

		if resource_type == "desert":
			continue

		var is_adjacent := false

		if hex_info["vertex_keys"].has(vertex_key):
			is_adjacent = true
		else:
			for key in hex_info["vertex_keys"]:
				if vertices_by_key.has(key) and vertices_by_key[key] == vertex:
					is_adjacent = true
					break

		if not is_adjacent:
			continue

		add_resource(player_id, resource_type, 1)
		gained[resource_type] += 1

	var parts: Array[String] = []

	for resource_type in resource_order:
		if gained[resource_type] > 0:
			parts.append(get_resource_name_pl(resource_type) + " +" + str(gained[resource_type]))

	if parts.is_empty():
		show_message(player_data[player_id].name + " nie dostał startowych surowców")
	else:
		show_message(player_data[player_id].name + " dostaje startowe surowce: " + ", ".join(parts))

	update_resources_ui()

func on_city_built(vertex, player_id: int):
	register_city(player_id)
	show_message(player_data[player_id].name + " rozbudował osadę do miasta")


func on_road_built(road, player_id: int):
	register_road(player_id)

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

		show_message("Setup zakończony. Zaczyna normalna gra.")
	else:
		current_player_index = setup_sequence[setup_step]
		show_message("Setup: teraz " + get_current_player_name())

	update_turn_ui()


func create_trade_ui(canvas: CanvasLayer):
	var trade_x := 990
	var trade_y := 40

	var trade_title := Label.new()
	trade_title.text = "Handel z bankiem 4:1"
	trade_title.position = Vector2(trade_x, trade_y)
	trade_title.add_theme_font_size_override("font_size", 22)
	canvas.add_child(trade_title)

	var from_label := Label.new()
	from_label.text = "Oddajesz:"
	from_label.position = Vector2(trade_x, trade_y + 45)
	canvas.add_child(from_label)

	trade_from_option = OptionButton.new()
	trade_from_option.position = Vector2(trade_x, trade_y + 70)
	trade_from_option.size = Vector2(160, 36)
	canvas.add_child(trade_from_option)

	var to_label := Label.new()
	to_label.text = "Dostajesz:"
	to_label.position = Vector2(trade_x + 180, trade_y + 45)
	canvas.add_child(to_label)

	trade_to_option = OptionButton.new()
	trade_to_option.position = Vector2(trade_x + 180, trade_y + 70)
	trade_to_option.size = Vector2(160, 36)
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
	trade_button.position = Vector2(trade_x, trade_y + 125)
	trade_button.size = Vector2(160, 42)
	trade_button.pressed.connect(trade_4_to_1)
	canvas.add_child(trade_button)

	trade_info_label = Label.new()
	trade_info_label.text = ""
	trade_info_label.visible = false
	canvas.add_child(trade_info_label)

	var extra_players_title := Label.new()
	extra_players_title.text = "Dodatkowi gracze"
	extra_players_title.position = Vector2(trade_x, trade_y + 220)
	extra_players_title.add_theme_font_size_override("font_size", 22)
	canvas.add_child(extra_players_title)

	extra_resources_label = Label.new()
	extra_resources_label.position = Vector2(trade_x, trade_y + 260)
	extra_resources_label.size = Vector2(360, 560)
	extra_resources_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	extra_resources_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(extra_resources_label)


func trade_4_to_1():
	if game_over:
		return

	if waiting_for_robber:
		show_message("Najpierw przesuń złodzieja")
		return

	if setup_phase:
		trade_info_label.text = "Handel dostępny po setupie"
		show_message("Handel dostępny dopiero po setupie")
		return

	var from_idx := trade_from_option.get_selected_id()
	var to_idx := trade_to_option.get_selected_id()

	if from_idx < 0 or to_idx < 0:
		return

	var from_resource = resource_order[from_idx]
	var to_resource = resource_order[to_idx]

	if from_resource == to_resource:
		trade_info_label.text = "Wybierz różne surowce"
		show_message("Nie można wymienić surowca na ten sam surowiec")
		return

	var player_id = get_current_player_id()
	var resources = player_data[player_id].resources

	if resources[from_resource] < 4:
		trade_info_label.text = "Brakuje: " + get_resource_name_pl(from_resource)
		show_message("Brakuje surowców do handlu 4:1")
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
	show_message(message)


# ============================================================
# NAJDŁUŻSZA DROGA
# ============================================================

func refresh_longest_road():
	var lengths: Array[int] = []

	for player_id in range(player_data.size()):
		var length := compute_longest_road_for_player(player_id)
		lengths.append(length)

	var best_length := 0
	var best_players: Array[int] = []

	for player_id in range(lengths.size()):
		var length = lengths[player_id]

		if length > best_length:
			best_length = length
			best_players.clear()
			best_players.append(player_id)
		elif length == best_length and length > 0:
			best_players.append(player_id)

	var old_owner := longest_road_owner
	var new_owner := -1

	if best_length >= longest_road_min_length:
		if longest_road_owner != -1 and lengths[longest_road_owner] == best_length:
			new_owner = longest_road_owner
		elif best_players.size() == 1:
			new_owner = best_players[0]

	if old_owner != new_owner:
		if old_owner != -1:
			player_data[old_owner].vp = max(player_data[old_owner].vp - longest_road_bonus_points, 0)
			show_message(player_data[old_owner].name + " traci Najdłuższą Drogę")

		if new_owner != -1:
			player_data[new_owner].vp += longest_road_bonus_points
			show_message(player_data[new_owner].name + " zdobywa Najdłuższą Drogę +" + str(longest_road_bonus_points) + " punkty")

	longest_road_owner = new_owner

	if longest_road_owner == -1:
		longest_road_length = 0
	else:
		longest_road_length = lengths[longest_road_owner]
		check_victory(longest_road_owner)


func compute_longest_road_for_player(player_id: int) -> int:
	var best := 0

	for road_key in roads_by_key.keys():
		var road = roads_by_key[road_key]

		if not road.occupied:
			continue

		if road.owner_id != player_id:
			continue

		var visited_roads := {}
		var length_from_a := 1 + dfs_longest_road(player_id, road.vertex_b, visited_roads_with_road(visited_roads, road))
		var length_from_b := 1 + dfs_longest_road(player_id, road.vertex_a, visited_roads_with_road(visited_roads, road))

		best = max(best, length_from_a)
		best = max(best, length_from_b)

	for vertex_key in vertices_by_key.keys():
		var vertex = vertices_by_key[vertex_key]
		best = max(best, dfs_longest_road(player_id, vertex, {}))

	return best


func dfs_longest_road(player_id: int, vertex, visited_roads: Dictionary) -> int:
	if visited_roads.size() > 0 and is_vertex_blocked_for_longest_road(vertex, player_id):
		return 0

	var best := 0

	for road in vertex.connected_roads:
		if not road.occupied:
			continue

		if road.owner_id != player_id:
			continue

		var road_id = road.get_instance_id()

		if visited_roads.has(road_id):
			continue

		var new_visited = visited_roads.duplicate()
		new_visited[road_id] = true

		var other_vertex = get_other_vertex(road, vertex)

		if other_vertex == null:
			continue

		var length := 1 + dfs_longest_road(player_id, other_vertex, new_visited)
		best = max(best, length)

	return best


func visited_roads_with_road(visited_roads: Dictionary, road) -> Dictionary:
	var new_visited = visited_roads.duplicate()
	new_visited[road.get_instance_id()] = true
	return new_visited


func is_vertex_blocked_for_longest_road(vertex, player_id: int) -> bool:
	if not vertex.occupied:
		return false

	if vertex.owner_id == player_id:
		return false

	return true


# ============================================================
# ZŁODZIEJ
# ============================================================

func start_robber_phase():
	show_message("Wypadło 7 — złodziej aktywny")

	discard_for_seven()

	waiting_for_robber = true
	dice_label.text += " — kliknij pole"

	update_resources_ui()
	update_turn_ui()


func discard_for_seven():
	for player_id in range(player_data.size()):
		var total := get_total_resources(player_id)

		if total <= 7:
			continue

		var amount_to_discard := int(floor(float(total) / 2.0))
		auto_discard_resources(player_id, amount_to_discard)


func auto_discard_resources(player_id: int, amount_to_discard: int):
	var remaining := amount_to_discard
	var sorted_resources = resource_order.duplicate()

	sorted_resources.sort_custom(func(a, b):
		return player_data[player_id].resources[a] > player_data[player_id].resources[b]
	)

	for resource_type in sorted_resources:
		if remaining <= 0:
			break

		var available = player_data[player_id].resources[resource_type]
		var taken = min(available, remaining)

		if taken <= 0:
			continue

		player_data[player_id].resources[resource_type] -= taken
		remaining -= taken

	show_message(player_data[player_id].name + " odrzuca " + str(amount_to_discard) + " surowców")


func get_total_resources(player_id: int) -> int:
	var total := 0

	for resource_type in resource_order:
		total += player_data[player_id].resources[resource_type]

	return total


func _unhandled_input(event):
	if game_over:
		return

	if not waiting_for_robber:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos := get_global_mouse_position()
		var hex_info = get_hex_info_at_position(mouse_pos)

		if hex_info == null:
			show_message("Kliknij pole planszy, żeby przesunąć złodzieja")
			return

		move_robber_to(hex_info)


func get_hex_info_at_position(pos: Vector2):
	var closest_hex = null
	var closest_distance := INF

	for hex_info in hex_infos:
		var hex_pos: Vector2 = hex_info["position"]
		var distance := pos.distance_to(hex_pos)

		if distance < closest_distance:
			closest_distance = distance
			closest_hex = hex_info

	if closest_distance <= hex_size:
		return closest_hex

	return null


func move_robber_to(hex_info):
	if robber_hex_info != null and hex_info["node"] == robber_hex_info["node"]:
		show_message("Złodziej już stoi na tym polu")
		return

	if robber_hex_info != null:
		robber_hex_info["has_robber"] = false

	hex_info["has_robber"] = true
	robber_hex_info = hex_info

	waiting_for_robber = false

	update_robber_marker()
	steal_random_resource_from_adjacent_player(hex_info)

	update_resources_ui()
	update_turn_ui()

	show_message("Złodziej został przesunięty")


func steal_random_resource_from_adjacent_player(hex_info):
	var current_player_id := get_current_player_id()
	var possible_targets: Array[int] = []

	for vertex_key in hex_info["vertex_keys"]:
		if not vertices_by_key.has(vertex_key):
			continue

		var vertex = vertices_by_key[vertex_key]

		if not vertex.occupied:
			continue

		if vertex.owner_id == current_player_id:
			continue

		if vertex.owner_id < 0:
			continue

		if get_total_resources(vertex.owner_id) <= 0:
			continue

		if not possible_targets.has(vertex.owner_id):
			possible_targets.append(vertex.owner_id)

	if possible_targets.is_empty():
		show_message("Brak przeciwnika do okradzenia przy tym polu")
		return

	var target_id = possible_targets.pick_random()
	var stolen_resource = get_random_resource_from_player(target_id)

	if stolen_resource == "":
		show_message("Przeciwnik nie ma surowców do kradzieży")
		return

	player_data[target_id].resources[stolen_resource] -= 1
	player_data[current_player_id].resources[stolen_resource] += 1

	show_message(
		get_current_player_name()
		+ " kradnie 1 "
		+ get_resource_name_pl(stolen_resource)
		+ " od "
		+ player_data[target_id].name
	)


func get_random_resource_from_player(player_id: int) -> String:
	var available_resources: Array[String] = []

	for resource_type in resource_order:
		var amount = player_data[player_id].resources[resource_type]

		for i in range(amount):
			available_resources.append(resource_type)

	if available_resources.is_empty():
		return ""

	return available_resources.pick_random()


func create_robber_marker():
	robber_marker = Node2D.new()
	robber_marker.name = "RobberMarker"
	robber_marker.z_index = 30
	add_child(robber_marker)

	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = create_circle_polygon(14.0, 24)
	body.color = Color(0.05, 0.05, 0.05)
	robber_marker.add_child(body)

	var label := Label.new()
	label.name = "Label"
	label.text = "R"
	label.modulate = Color.WHITE
	label.position = Vector2(-5, -10)
	robber_marker.add_child(label)

	update_robber_marker()


func create_circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()

	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		var point := Vector2(cos(angle), sin(angle)) * radius
		points.append(point)

	return points


func update_robber_marker():
	if robber_marker == null:
		return

	if robber_hex_info == null:
		robber_marker.visible = false
		return

	robber_marker.visible = true
	robber_marker.position = robber_hex_info["position"]

# ============================================================
# CPU / CATAN ENGINE INTEGRATION
# ============================================================

func is_current_player_cpu() -> bool:
	if current_player_index < 0:
		return false

	return player_data[current_player_index].is_cpu


func run_cpu_turn_if_needed():
	if engine == null:
		return

	if cpu_thinking:
		return

	if game_over:
		return

	if not is_current_player_cpu():
		return

	cpu_thinking = true

	await get_tree().create_timer(cpu_action_delay).timeout

	if game_over:
		cpu_thinking = false
		return

	if not is_current_player_cpu():
		cpu_thinking = false
		return

	if not setup_phase and not waiting_for_robber and not has_rolled_this_turn:
		show_message(get_current_player_name() + " CPU rzuca kostką")
		roll_dice()
		await get_tree().create_timer(cpu_action_delay).timeout
		
		if game_over:
			cpu_thinking = false
			return

	var pos = engine.from_game_state(self)
	var candidate_moves = get_cpu_candidate_moves(pos)
	var applied := false
	var applied_move = null

	for move in candidate_moves:
		if apply_engine_move_to_game(move, pos):
			applied = true
			applied_move = move
			break

	cpu_thinking = false

	if not applied:
		show_message(get_current_player_name() + " CPU nie znalazł poprawnego ruchu")

		if not setup_phase and not waiting_for_robber:
			next_turn()
		else:
			call_deferred("run_cpu_turn_if_needed")

		return

	show_message(get_current_player_name() + " CPU wykonał: " + str(applied_move))

	update_resources_ui()
	update_turn_ui()


func get_cpu_candidate_moves(pos) -> Array:
	var result: Array = []

	var searched_move = engine.search(pos, cpu_action_delay, CatanEngine.Personality.RANDOM)

	if is_supported_cpu_move(searched_move):
		result.append(searched_move)
	else :
		print("playing: ", searched_move)
	return result

	var generated_moves: Array = pos.generate_moves()
	generated_moves.shuffle()

	for move in generated_moves:
		if not is_supported_cpu_move(move):
			continue

		if not result.has(move):
			result.append(move)

	if result.is_empty():
		result.append(CatanEngine.Move.new(CatanEngine.Move.Type.END_TURN))

	return result


func is_supported_cpu_move(move: CatanEngine.Move) -> bool:
	match move.type:
		CatanEngine.Move.Type.SETTLEMENT:
			return true
		CatanEngine.Move.Type.ROAD:
			return true
		CatanEngine.Move.Type.BUILD_SETTLEMENT:
			return true
		CatanEngine.Move.Type.BUILD_ROAD:
			return true
		CatanEngine.Move.Type.BUILD_CITY:
			return true
		CatanEngine.Move.Type.TRADE_BANK:
			return true
		CatanEngine.Move.Type.MOVE_ROBBER:
			return true
		CatanEngine.Move.Type.DISCARD:
			return true
		CatanEngine.Move.Type.END_TURN:
			return true
		_:
			return false


func apply_engine_move_to_game(move: CatanEngine.Move, pos) -> bool:
	match move.type:
		CatanEngine.Move.Type.SETTLEMENT:
			return apply_engine_settlement(move, pos)

		CatanEngine.Move.Type.ROAD:
			return apply_engine_road(move, pos)

		CatanEngine.Move.Type.BUILD_SETTLEMENT:
			return apply_engine_settlement(move, pos)

		CatanEngine.Move.Type.BUILD_ROAD:
			return apply_engine_road(move, pos)

		CatanEngine.Move.Type.BUILD_CITY:
			return apply_engine_city(move, pos)

		CatanEngine.Move.Type.TRADE_BANK:
			return apply_engine_bank_trade(move)

		CatanEngine.Move.Type.MOVE_ROBBER:
			return apply_engine_robber(move, pos)

		CatanEngine.Move.Type.DISCARD:
			return apply_engine_discard(move)

		CatanEngine.Move.Type.END_TURN:
			if setup_phase:
				return false
			next_turn()
			return true

		_:
			return false


func apply_engine_settlement(move: CatanEngine.Move, pos) -> bool:
	var vertex = get_visual_vertex_from_engine_id(pos, move.vertex_id)

	if vertex == null:
		return false

	if not can_build_settlement(vertex):
		return false

	vertex.build_settlement(self)
	show_message(get_current_player_name() + " CPU zbudował osadę")
	return true


func apply_engine_road(move: CatanEngine.Move, pos) -> bool:
	var road = get_visual_road_from_engine_id(pos, move.road_id)

	if road == null:
		return false

	if not can_build_road(road):
		return false

	road.build_road(self)
	show_message(get_current_player_name() + " CPU zbudował drogę")
	return true


func apply_engine_city(move: CatanEngine.Move, pos) -> bool:
	var vertex = get_visual_vertex_from_engine_id(pos, move.vertex_id)

	if vertex == null:
		return false

	if not can_upgrade_city(vertex):
		return false

	vertex.upgrade_to_city(self)
	show_message(get_current_player_name() + " CPU zbudował miasto")
	return true


func apply_engine_bank_trade(move: CatanEngine.Move) -> bool:
	if setup_phase:
		return false

	if waiting_for_robber:
		return false

	var player_id = get_current_player_id()

	if player_data[player_id].resources[move.bank_give] < move.bank_give_amount:
		return false

	player_data[player_id].resources[move.bank_give] -= move.bank_give_amount
	player_data[player_id].resources[move.bank_receive] += 1

	show_message(
		get_current_player_name()
		+ " CPU wymienia "
		+ str(move.bank_give_amount)
		+ " "
		+ get_resource_name_pl(move.bank_give)
		+ " na 1 "
		+ get_resource_name_pl(move.bank_receive)
	)

	return true


func apply_engine_discard(move: CatanEngine.Move) -> bool:
	var player_id = get_current_player_id()

	for resource_type in move.discard_resources.keys():
		var amount = move.discard_resources[resource_type]

		if not player_data[player_id].resources.has(resource_type):
			continue

		player_data[player_id].resources[resource_type] = max(player_data[player_id].resources[resource_type] - amount, 0)

	update_resources_ui()
	show_message(get_current_player_name() + " CPU odrzuca surowce")
	return true


func apply_engine_robber(move: CatanEngine.Move, pos) -> bool:
	if not waiting_for_robber:
		return false

	var hex_info = get_hex_info_from_engine_id(pos, move.robber_hex_id)

	if hex_info == null:
		return false

	move_robber_to(hex_info)
	return true


func get_visual_vertex_from_engine_id(pos, vertex_id: int):
	if vertex_id < 0 or vertex_id >= pos.vertices.size():
		return null

	var local_key := engine._get_vertex_pixel_key(pos, vertex_id)
	var world_key := local_key_to_world_key(local_key)

	if vertices_by_key.has(world_key):
		return vertices_by_key[world_key]

	return null


func get_visual_road_from_engine_id(pos, road_id: int):
	if road_id < 0 or road_id >= pos.roads.size():
		return null

	var engine_road = pos.roads[road_id]

	var local_a := engine._get_vertex_pixel_key(pos, engine_road.vertex_a_id)
	var local_b := engine._get_vertex_pixel_key(pos, engine_road.vertex_b_id)

	var world_a := local_key_to_world_key(local_a)
	var world_b := local_key_to_world_key(local_b)

	var road_key := get_road_key(world_a, world_b)

	if roads_by_key.has(road_key):
		return roads_by_key[road_key]

	return null


func get_hex_info_from_engine_id(pos, hex_id: int):
	if hex_id < 0 or hex_id >= pos.hexes.size():
		return null

	var engine_hex = pos.hexes[hex_id]

	for hex_info in hex_infos:
		var q = hex_info["axial_q"] if hex_info.has("axial_q") else null
		var r = hex_info["axial_r"] if hex_info.has("axial_r") else null

		if q == engine_hex.axial_q and r == engine_hex.axial_r:
			return hex_info

	return null


func local_key_to_world_key(local_key: String) -> String:
	var parts := local_key.split("_")

	if parts.size() != 2:
		return local_key

	var x := int(parts[0]) + int(round(board_offset.x))
	var y := int(parts[1]) + int(round(board_offset.y))

	return "%d_%d" % [x, y]
