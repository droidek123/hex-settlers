extends Area2D

var occupied := false
var owner_id := -1

var vertex_a = null
var vertex_b = null

var length := 40.0
var thickness := 6.0
var endpoint_margin := 12.0

@onready var visual: Polygon2D = $Polygon2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready():
	visual.color = Color(1, 1, 1, 0.35)

func setup(a, b):
	vertex_a = a
	vertex_b = b

	var start_pos = vertex_a.global_position
	var end_pos = vertex_b.global_position

	var middle = (start_pos + end_pos) / 2.0
	var direction = end_pos - start_pos

	global_position = middle
	rotation = direction.angle()

	var full_length = direction.length()
	length = max(full_length - endpoint_margin * 2.0, 1.0)

	visual.polygon = PackedVector2Array([
		Vector2(-length / 2.0, -thickness / 2.0),
		Vector2(length / 2.0, -thickness / 2.0),
		Vector2(length / 2.0, thickness / 2.0),
		Vector2(-length / 2.0, thickness / 2.0)
	])

	var shape := RectangleShape2D.new()
	shape.size = Vector2(length, thickness)
	collision.shape = shape

func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		viewport.set_input_as_handled()

		var game = get_tree().get_first_node_in_group("game")

		if game == null:
			return

		if game.can_build_road(self):
			build_road(game)
		else:
			print("Nie można tutaj zbudować drogi")

func build_road(game):
	occupied = true
	owner_id = game.get_current_player_id()
	visual.color = game.get_current_player_color()

	if not game.is_setup_phase():
		game.pay_for_road(owner_id)

	game.on_road_built(self, owner_id)

	print(game.get_current_player_name() + " zbudował drogę")
