extends Node2D

@export var hex_scene: PackedScene

var types = ["wood", "brick", "sheep", "wheat", "ore", "desert"]
var numbers = [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12]

var hex_size = 42
var map_radius = 2
var board_offset = Vector2(400, 250)

func _ready():
	randomize()
	generate_board()

func generate_board():
	for q in range(-map_radius, map_radius + 1):
		for r in range(-map_radius, map_radius + 1):
			if abs(q + r) > map_radius:
				continue

			var hex = hex_scene.instantiate()
			add_child(hex)

			hex.position = axial_to_world(q, r) + board_offset
			hex.resource_type = types.pick_random()

			if hex.resource_type == "desert":
				hex.number = 0
			else:
				hex.number = numbers.pick_random()

			hex.refresh()

func axial_to_world(q: int, r: int) -> Vector2:
	var x = hex_size * (3.0 / 2.0 * q)
	var y = hex_size * (sqrt(3) / 2.0 * q + sqrt(3) * r)
	return Vector2(x, y)
