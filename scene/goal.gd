extends Control

@onready var template = $Gold

func _ready():
	template.visible = false
	# 播放进入目标界面的音效
	Global.play_sfx(Global.sfx_goal, self)
	
	# 配置并启动计时器
	$Timer.wait_time = Global.goal_display_time
	$Timer.start()
	
	var screen_size = get_viewport_rect().size
	var tex_size = template.texture.get_size() # 金块原始尺寸
	
	# 网格步长（比金块小一些，让它们重叠堆积）
	var step_x = tex_size.x * 0.5
	var step_y = tex_size.y * 0.5
	
	var y = - tex_size.y * 0.5
	while y < screen_size.y + tex_size.y:
		var x = - tex_size.x * 0.5
		while x < screen_size.x + tex_size.x:
			var copy = template.duplicate()
			copy.visible = true
			copy.position = Vector2(
				x + randf_range(-30, 30),
				y + randf_range(-30, 30)
			)
			copy.rotation_degrees = randf_range(0, 360)
			copy.scale = Vector2.ONE * randf_range(0.7, 1.2)
			add_child(copy)
			move_child(copy, 1)
			x += step_x
		y += step_y
	$TextureRect/GoalNumber.text = "$" + str(Global.current_target_score)


func _on_timer_timeout() -> void:
	get_tree().change_scene_to_file("res://scene/main.tscn")
