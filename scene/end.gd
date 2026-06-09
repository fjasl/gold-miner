extends Control

@onready var template = $Gold

var win: bool = false

	
func _ready():
	template.visible = false
	
	if Global.total_golds >= Global.current_target_score:
		win = true
	
	# 配置并启动计时器
	$Timer.wait_time = Global.end_display_time
	$Timer.start()
	
	var win_title = $TextureRect/WinTitle
	var fail_title = $TextureRect/FailTitle
	var texture_rect2 = $TextureRect2
	
	
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
	
	if win:
		win_title.visible = true
		fail_title.visible = false
		texture_rect2.visible = true
	
		# WinTitle 的出场缩放动画
		win_title.pivot_offset = win_title.size / 2 # 设置缩放中心
		win_title.scale = Vector2.ZERO
		var tween = create_tween()
		tween.tween_property(win_title, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		Global.play_sfx(Global.sfx_win, self)
	else:
		win_title.visible = false
		fail_title.visible = true
		texture_rect2.visible = false
		fail_title.pivot_offset = fail_title.size / 2 # 设置缩放中心
		fail_title.scale = Vector2.ZERO
		var tween = create_tween()
		tween.tween_property(fail_title, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		Global.play_sfx(Global.sfx_down, self)

func _on_timer_timeout() -> void:
	if win:
		# 胜利：推进关卡并提高目标分数
		Global.current_level += 1
		Global.current_target_score += 500 + Global.current_level * 100
		# 清除一次性道具（胜利后失效）
		ItemManager.clear_one_time_items()
		get_tree().change_scene_to_file("res://scene/shop.tscn")
	else:
		# 失败：重置关卡数据，回到开始界面
		Global.current_level = 1
		Global.current_target_score = Global.basic_golds
		Global.total_golds = 0
		ItemManager.clear_one_time_items()
		get_tree().change_scene_to_file("res://scene/start.tscn")
