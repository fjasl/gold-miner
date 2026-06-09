extends Control

@onready var start_btn:TextureButton = $TextureButton


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("game_start"):
		start_btn.pressed.emit()



func _on_texture_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scene/goal.tscn")
