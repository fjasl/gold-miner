extends Polygon2D

@export var radius: float = 45.0

func _ready():
	color = Color(0.1, 0.2, 0.6)
	var points = []
	# 从左到右画半圆弧（向上拱起）
	for i in range(31):
		var angle = deg_to_rad(i * 180.0 / 30)
		points.append(Vector2(cos(angle) * radius, -sin(angle) * radius))
	polygon = PackedVector2Array(points)
