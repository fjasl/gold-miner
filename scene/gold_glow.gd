extends TextureRect

var time = 0.0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	time += delta
	var pulse = 1.0 + 0.1 * sin(time * 2.0)
	scale = Vector2(pulse, pulse)
	pass
