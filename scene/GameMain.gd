extends Control
## 游戏主关卡 —— 事件中枢
## 职责：关卡初始化、监听矿工事件、调用 ItemManager 计算、更新 UI

var time = Global.basic_time

@onready var miner: Node2D = $CharaterArea/Miner

# 待提交的奖励队列（动画结束后才写入 Global，游戏结束时会强制提交）
var _pending_rewards: Array[Dictionary] = []

func update_state() -> void:
	$CharaterArea/MarginContainer/HBoxContainer/VBoxContainer3/GoldText.text = "$" + str(Global.total_golds)
	$CharaterArea/MarginContainer/HBoxContainer/VBoxContainer3/GoalText.text = "$" + str(Global.current_target_score)
	$CharaterArea/MarginContainer/HBoxContainer/VBoxContainer2/VBoxContainer2/LevelText.text = str(Global.current_level)
	$CharaterArea/MarginContainer/HBoxContainer/VBoxContainer2/VBoxContainer2/TimeText.text = str(time)

func game_end() -> void:
	_commit_pending_rewards()
	get_tree().change_scene_to_file("res://scene/end.tscn")


func _ready() -> void:
	_fill_background()
	_spawn_items()
	$Timer.wait_time = Global.basic_time
	$Timer.start()
	_update_bomb_display()
	
	# 连接矿工事件信号
	miner.item_hooked.connect(_on_miner_item_hooked)
	miner.item_released.connect(_on_miner_item_released)
	miner.item_delivered.connect(_on_miner_item_delivered)
	miner.bomb_requested.connect(_on_miner_bomb_requested)


func _process(_delta: float) -> void:
	time = str(int(ceil($Timer.time_left)))
	update_state()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("game_exit"):
		game_end()


func _fill_background():
	var maps = Global.game_maps
	$ItemArea.texture = maps[randi() % maps.size()]


func _spawn_items():
	var item_area = $ItemArea
	# 关键：_ready() 时 Control 布局尚未完成，get_global_rect() 可能返回错误值
	# 等待一帧，确保 layout 已稳定
	if item_area.size == Vector2.ZERO:
		await get_tree().process_frame
	
	var area_rect = item_area.get_global_rect()
	var item_count = 26 + Global.current_level * 4
	
	var positions = _generate_uniform_positions(area_rect, item_count)
	positions.shuffle()
	
	for i in range(positions.size()):
		var config = _pick_random_item()
		var instance = config["scene"].instantiate()
		instance.position = positions[i]
		instance.add_to_group("grabbable_item")
		add_child(instance)


## 在矿工正下方生成一个大椭圆，物品集中分布在地下区域
func _generate_uniform_positions(area: Rect2, count: int) -> Array:
	var positions: Array = []
	
	# 安全边距：顶部留空间给钩爪下落，底部避免贴边，左右留出摆动余量
	var margin_top = 150.0
	var margin_bottom = 20.0
	var margin_h = 50.0
	
	# 安全区域（实际可用于生成的矩形）
	var safe_x = area.position.x + margin_h
	var safe_y = area.position.y + margin_top
	var safe_w = maxf(0, area.size.x - margin_h * 2)
	var safe_h = maxf(0, area.size.y - margin_top - margin_bottom)
	
	if safe_w <= 0 or safe_h <= 0:
		push_warning("ItemArea 尺寸不足以生成物品")
		return positions
	
	# 椭圆中心：水平居中，垂直位于安全区域的中上部（0.45 处）
	# 这样椭圆会向下延伸更多，形成"正下方"的视觉效果
	var center = Vector2(
		safe_x + safe_w * 0.5,
		safe_y + safe_h * 0.45
	)
	
	# 椭圆半径：水平撑满安全区域，垂直向下大幅延伸
	var radius_x = safe_w * 0.5
	var radius_y = safe_h * 0.65
	
	# 确保椭圆不超出安全区域顶部（关键！防止物品生成到矿工区域）
	var max_radius_y_down = safe_y + safe_h - center.y
	var max_radius_y_up = center.y - safe_y
	radius_y = minf(radius_y, max_radius_y_down)
	radius_y = minf(radius_y, max_radius_y_up)
	
	var max_attempts = count * 30
	var min_dist = 42.0
	
	for attempt in range(max_attempts):
		if positions.size() >= count:
			break
		
		var pos = _random_point_in_ellipse(center, radius_x, radius_y)
		
		# 最小间距检查
		var too_close = false
		for existing in positions:
			if pos.distance_to(existing) < min_dist:
				too_close = true
				break
		
		if not too_close:
			positions.append(pos)
	
	return positions


## 在椭圆内均匀随机取一点（拒绝采样法）
func _random_point_in_ellipse(center: Vector2, rx: float, ry: float) -> Vector2:
	while true:
		var x = randf_range(-rx, rx)
		var y = randf_range(-ry, ry)
		if (x * x) / (rx * rx) + (y * y) / (ry * ry) <= 1.0:
			return center + Vector2(x, y)
	return center


func _pick_random_item() -> Dictionary:
	var total_weight = 0
	for config in Global.item_configs:
		total_weight += config["weight"]
	
	var roll = randi() % total_weight
	var cumulative = 0
	for config in Global.item_configs:
		cumulative += config["weight"]
		if roll < cumulative:
			return config
	
	return Global.item_configs[0]


# ===== 矿工事件回调 =====

## 钩中物品时：外部决定回收速度，或处理特殊事件（爆炸桶等）
func _on_miner_item_hooked(item: Node) -> void:
	var hooked_event = Global.Hooked_Event.NULL
	if item.get("hooked_event") != null:
		hooked_event = item.hooked_event
	
	var difficulty = Miner.get_item_difficulty(item)
	var speed = ItemManager.calculate_retract_speed(difficulty)
	miner.set_retract_speed(speed)
	
	if hooked_event == Global.Hooked_Event.EXPLODE:
		_trigger_explosion(item)


## 触发炸药桶范围爆炸 —— 炸掉周围物品，但桶本身继续被回收
func _trigger_explosion(barrel: Node) -> void:
	var center = barrel.global_position
	var radius = 150.0
	
	# 播放爆炸动画（炸药桶自带）
	# 注意：miner 钩中时已把 barrel.visible = false，需要重新显示父节点
	var event_node = barrel.get_node_or_null("Event")
	if event_node:
		barrel.visible = true
		# 隐藏不需要的子节点，只保留爆炸动画
		var area = barrel.get_node_or_null("Area2D")
		if area:
			area.visible = false
		var hooked = barrel.get_node_or_null("Hooked")
		if hooked:
			hooked.visible = false
		event_node.visible = true
		event_node.play("explode")
	
	# 延迟一帧，确保碰撞检测有效
	await get_tree().process_frame
	
	# 摧毁范围内所有可抓取物品（不包括桶本身）
	var targets = get_tree().get_nodes_in_group("grabbable_item")
	for target in targets:
		if target == barrel:
			continue
		if target.global_position.distance_to(center) <= radius:
			var score = target.get("value") if target.get("value") != null else 0
			var category = target.get("category") if target.get("category") != null else Global.Hooked_Category.GOLD
			var final_score = ItemManager.calculate_score(score, category)
			Global.total_golds += final_score
			target.queue_free()


## 提交所有待处理的奖励（动画结束后或游戏结束时调用）
func _commit_pending_rewards() -> void:
	for reward in _pending_rewards:
		match reward.get("type"):
			"money":
				Global.total_golds += reward.value
			"strength":
				Global.set_item(Global.Item.POWER, true)
				# 如果正在回收，立即加速当前这钩
				if is_instance_valid(miner) and miner.state == Miner.State.RETRACT:
					var current_item = miner.get_hooked_item()
					var difficulty = 1
					if current_item:
						difficulty = Miner.get_item_difficulty(current_item)
					var speed = ItemManager.calculate_retract_speed(difficulty)
					miner.set_retract_speed(speed)
			"bomb":
				Global.add_bomb()
	_pending_rewards.clear()
	if is_instance_valid(self):
		_update_bomb_display()


## 物品被释放时（炸弹等）
func _on_miner_item_released() -> void:
	_update_bomb_display()


## 物品成功回收到底时：计算最终分数
func _on_miner_item_delivered(item: Node) -> void:
	var base_score = 0
	var category = Global.Hooked_Category.GOLD
	
	if item.get("value") != null:
		base_score = item.get("value")
	if item.get("category") != null:
		category = item.get("category")
	
	# 处理问号袋随机效果
	var recycle_event = Global.Recycle_Finish_Event.NULL
	if item.get("recycle_finish_event") != null:
		recycle_event = item.get("recycle_finish_event")
	
	if recycle_event == Global.Recycle_Finish_Event.GET_RANDOM_EFFECT:
		var reward = ItemManager.get_bag_reward()
		_play_reward_animation(reward)
		return
	
	var final_score = ItemManager.calculate_score(base_score, category)
	_pending_rewards.append({"type": "money", "value": final_score})
	await _play_money_animation(final_score)
	if is_instance_valid(self):
		_commit_pending_rewards()


## 统一奖励动画分发器
func _play_reward_animation(reward: Dictionary) -> void:
	match reward["type"]:
		ItemManager.Bag_Reward_Type.MONEY:
			var amount = reward.get("value", 0)
			_pending_rewards.append({"type": "money", "value": amount})
			await _play_money_animation(amount)
			if is_instance_valid(self):
				_commit_pending_rewards()
		ItemManager.Bag_Reward_Type.STRENGTH:
			_pending_rewards.append({"type": "strength"})
			await _play_strength_animation()
			if is_instance_valid(self):
				_commit_pending_rewards()
		ItemManager.Bag_Reward_Type.BOMB:
			_pending_rewards.append({"type": "bomb"})
			await _play_bomb_animation()
			if is_instance_valid(self):
				_commit_pending_rewards()


## 金钱奖励飞入动画（飞到金币 UI）
func _play_money_animation(amount: int) -> void:
	var label = _create_floating_label("+$" + str(amount), Color("009900ff"))
	await _animate_reward_fly_to_ui(label, _get_gold_label_center())
	if not is_instance_valid(self):
		return
	Global.play_sfx(Global.sfx_score_add, self)
	if is_instance_valid(label):
		label.queue_free()


## Strength 飘出动画：出现 → 停留 → 淡出
func _play_strength_animation() -> void:
	var label = _create_floating_label("STRENGTH!", Color("009900ff"))
	var miner_center = miner.global_position
	var start_pos = miner_center + Vector2(-200, -20)
	
	# 第一段：出现
	var tween = create_tween()
	tween.parallel().tween_property(label, "global_position", start_pos, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished
	
	# 第二段：停留
	await get_tree().create_timer(0.6).timeout
	
	# 第三段：淡出 + 上浮
	var tween2 = create_tween()
	tween2.parallel().tween_property(label, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween2.parallel().tween_property(label, "global_position", start_pos + Vector2(0, -60), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween2.finished
	
	if is_instance_valid(label):
		label.queue_free()


## Bomb 飞入动画：出现 → 停留 → 飞到 bomb 栏位
func _play_bomb_animation() -> void:
	var bomb_icon = Sprite2D.new()
	var item_bomb = preload("res://scene/item_bomb.tscn").instantiate()
	bomb_icon.texture = item_bomb.get_node("Item").texture
	item_bomb.queue_free()
	add_child(bomb_icon)
	
	var miner_center = miner.global_position
	var start_pos = miner_center + Vector2(-200, -20)
	bomb_icon.global_position = miner.global_position
	bomb_icon.scale = Vector2.ZERO
	
	# 第一段：出现
	var tween = create_tween()
	tween.parallel().tween_property(bomb_icon, "global_position", start_pos, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(bomb_icon, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished
	
	# 第二段：停留
	await get_tree().create_timer(0.3).timeout
	
	# 第三段：飞到 bomb 存放处
	var bomb_root = $CharaterArea/TextureRect/Root
	var target_pos = bomb_root.global_position if bomb_root else start_pos + Vector2(400, -100)
	
	var tween2 = create_tween()
	tween2.parallel().tween_property(bomb_icon, "global_position", target_pos, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween2.parallel().tween_property(bomb_icon, "scale", Vector2.ZERO, 0.6).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	await tween2.finished
	
	if is_instance_valid(bomb_icon):
		bomb_icon.queue_free()


# ===== 动画辅助函数 =====

## 创建一个飘浮 Label（通用）
func _create_floating_label(text: String, color: Color) -> Label:
	var label = Label.new()
	label.text = text
	var font = FontFile.new()
	font.font_data = load("res://resource/SourceHanSansSC-Bold.otf")
	font.fixed_size = 34
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_font_override("font", font)
	add_child(label)
	
	label.global_position = miner.global_position
	label.scale = Vector2.ZERO
	return label


## 通用奖励飞入动画（第一段出现 + 停留 + 飞到目标）
func _animate_reward_fly_to_ui(node: Control, target_pos: Vector2) -> void:
	var miner_center = miner.global_position
	var start_pos = miner_center + Vector2(-200, -20)
	
	# 第一段：出现
	var tween = create_tween()
	tween.parallel().tween_property(node, "global_position", start_pos, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(node, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished
	
	# 第二段：停留
	await get_tree().create_timer(0.5).timeout
	
	# 第三段：飞到目标
	var tween2 = create_tween()
	tween2.parallel().tween_property(node, "global_position", target_pos, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween2.parallel().tween_property(node, "scale", Vector2.ZERO, 0.8).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	await tween2.finished


## 获取金币 Label 的中心位置（飞入目标）
func _get_gold_label_center() -> Vector2:
	var gold_label = $CharaterArea/MarginContainer/HBoxContainer/VBoxContainer3/GoldText
	return gold_label.get_global_rect().get_center()


## 炸弹按键被按下时
func _on_miner_bomb_requested() -> void:
	if ItemManager.try_use_bomb():
		miner.play_bomb_sequence()


# ===== UI 更新 =====

func _update_bomb_display() -> void:
	var bomb_root = $CharaterArea/TextureRect/Root
	if not bomb_root:
		return
	var count = Global.get_item(Global.Item.BOMB)
	for i in range(1, 5):
		var bomb = bomb_root.get_node_or_null("Bomb_" + str(i))
		if bomb:
			bomb.visible = i == count


func _on_timer_timeout() -> void:
	_commit_pending_rewards()
	game_end()


func _on_texture_rect_pressed() -> void:
	game_end()
