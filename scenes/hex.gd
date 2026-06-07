extends Node2D

@export var radius := 40.0
@export var resource_type := "wood"
@export var number := 0

@onready var poly: Polygon2D = $Polygon2D
@onready var number_label: Label = $NumberLabel

func _ready():
	var points := PackedVector2Array()

	for i in range(6):
		var angle = deg_to_rad(60 * i)
		var p = Vector2(cos(angle), sin(angle)) * radius
		points.append(p)

	poly.polygon = points
	refresh()

func refresh():
	apply_color()
	update_number_label()

func apply_color():
	match resource_type:
		"wood":
			poly.color = Color(0.239, 0.431, 0.008)
		"brick":
			poly.color = Color(0.875, 0.420, 0.282)
		"sheep":
			poly.color = Color("#9BC325")
		"wheat":
			poly.color = Color("#f3c23f")
		"ore":
			poly.color = Color(0.678, 0.667, 0.612)
		"desert":
			poly.color = Color(0.886, 0.816, 0.416)

func update_number_label():
	if number == 0:
		number_label.text = ""
	else:
		number_label.text = str(number)

	number_label.position = Vector2(-10, -10)
