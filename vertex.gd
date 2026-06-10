extends Area2D

var occupied := false
var owner_id := -1
var is_city := false
var connected_roads: Array = []

@onready var visual: Polygon2D = $Polygon2D

func _ready():
	set_visual_size(5)
	visual.color = Color.WHITE

func set_visual_size(size: float):
	visual.polygon = PackedVector2Array([
		Vector2(-size, -size),
		Vector2(size, -size),
		Vector2(size, size),
		Vector2(-size, size)
	])

func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		viewport.set_input_as_handled()

		var game = get_tree().get_first_node_in_group("game")

		if game == null:
			return

		if not occupied:
			if game.can_build_settlement(self):
				build_settlement(game)
			else:
				print("Nie można tutaj zbudować osady")
		else:
			if game.can_upgrade_city(self):
				upgrade_to_city(game)
			else:
				print("Nie można tutaj zbudować miasta")

func build_settlement(game):
	occupied = true
	owner_id = game.get_current_player_id()
	is_city = false

	set_visual_size(5)
	visual.color = game.get_current_player_color()

	if not game.is_setup_phase():
		game.pay_for_settlement(owner_id)

	game.register_settlement(owner_id)
	game.on_settlement_built(self, owner_id)

	print(game.get_current_player_name() + " zbudował osadę")

func upgrade_to_city(game):
	is_city = true

	set_visual_size(8)
	visual.color = game.get_current_player_color()

	game.pay_for_city(owner_id)
	game.on_city_built(self, owner_id)
