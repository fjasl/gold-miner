extends Control

@onready var detail_text: Label = $TextureRect/TextureRect/Label
@onready var shop_owner_anim: AnimatedSprite2D = $TextureRect/TextureRect2
@onready var next_game_btn: TextureButton = $TextureRect/TextureButton
var purchased:bool = false
# 存储当前可以选择的物品信息
var selectable_items: Array = []  # 每个元素是 {"item_node": Node, "goods_node": Node}
var current_select: int = 0


func next_game() -> void:
	get_tree().change_scene_to_file("res://scene/goal.tscn")
	pass

func update_selection() -> void:
	# 隐藏所有高亮（增加空判断）
	for data in selectable_items:
		var visual_sign = data.get("visual_sign")
		if visual_sign:
			visual_sign.hide()

	if selectable_items.is_empty():
		detail_text.text = ""
		return

	current_select = clampi(current_select, 0, selectable_items.size() - 1)
	var data = selectable_items[current_select]

	# 显示当前高亮
	if data.get("visual_sign"):
		data["visual_sign"].show()

	# 更新详情
	if data["goods_node"] and "detail" in data["goods_node"]:
		detail_text.text = data["goods_node"].detail

func _on_item_gui_input(event: InputEvent, item_node: TextureRect, goods_node: Node2D) -> void:
	# 检测鼠标左键双击事件
	if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		# 仅当物品可见时才触发购买（防止已隐藏的物品被双击）
		if item_node.visible:
			_on_item_bought(item_node, goods_node)
			
			
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	# 保证每次随机结果不同
	randomize()
	
	# 决定这次展示多少个物品(1~5个)
	# 通过一个权重池让概率趋近于3: 3出现5次，2和4出现2次，1和5出现1次
	var weight_pool = [1, 2, 2, 3, 3, 3, 3, 3, 4, 4, 5]
	var max_items_to_sell = weight_pool.pick_random()
	
	# 将5个物品节点放入数组
	var items = [$Item_1, $Item_2, $Item_3, $Item_4, $Item_5]
	
	# 随机打乱数组顺序
	#items.shuffle()
	
	# 清空列表
	selectable_items.clear()

	
	for i in range(items.size()):
		var item_node = items[i]
		if i >= max_items_to_sell:
			item_node.hide()
			continue

		item_node.show()
		var btn = item_node.get_node("TextureButton")
		var price_label = item_node.get_node("Label")
		var selected_sign = item_node.get_node("TextureButton/TextureRect")  # 高亮标记
		selected_sign.hide()  # 初始全部隐藏

		if btn and btn.get_child_count() > 0:
			var goods_node = btn.get_child(0)
			if price_label and goods_node and "price_base" in goods_node:
				price_label.text = "$" + str(goods_node.price_base)

			# 绑定鼠标信号（和原来一样）
			if not btn.mouse_entered.is_connected(_on_item_hovered):
				btn.mouse_entered.connect(_on_item_hovered.bind(goods_node,i))
			if not btn.pressed.is_connected(_on_item_bought):
				btn.pressed.connect(_on_item_bought.bind(item_node, goods_node,i))
			if not btn.gui_input.is_connected(_on_item_gui_input):
				btn.gui_input.connect(_on_item_gui_input.bind(item_node, goods_node))
			# 记录这个可选物品
			selectable_items.append({
				"item_node": item_node,
				"goods_node": goods_node,
				"visual_sign": selected_sign
			})

	shop_owner_anim.play("idle")
	
	# 初始化选中第一个（如果存在）
	if selectable_items.size() > 0:
		current_select = 0
		update_selection()
	
func _on_item_hovered(goods_node: Node2D, _i: int) -> void:
	# 根据 goods_node 在 selectable_items 中查找当前索引
	var idx = -1
	for i in range(selectable_items.size()):
		if selectable_items[i]["goods_node"] == goods_node:
			idx = i
			break
	if idx == -1:
		return  # 物品已被移除，忽略本次悬停

	current_select = idx
	update_selection()
	if goods_node and "detail" in goods_node:
		detail_text.text = goods_node.detail


func _on_item_bought(item_node: TextureRect, _goods_node: Node2D, _index: int = -1) -> void:
	purchased = true
	if Global.total_golds < _goods_node.price_base:
		shop_owner_anim.play("wrath")
	else:
		Global.total_golds -= _goods_node.price_base
		if _goods_node.type == Global.Item.BOMB:
			Global.add_bomb()
		else:
			Global.set_item(_goods_node.type,true)
		# 购买后隐藏该物品节点
		item_node.hide()
		# 购买后隐藏或重置详情页信息
		detail_text.text = ""
	# 从列表中移除已购买的物品
	for i in range(selectable_items.size() - 1, -1, -1):
		if selectable_items[i]["item_node"] == item_node:
			selectable_items.remove_at(i)
			break

	# 调整 current_select，防止越界
	if selectable_items.is_empty():
		current_select = 0
	else:
		current_select = mini(current_select, selectable_items.size() - 1)
		update_selection()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func _on_texture_button_pressed() -> void:
	if purchased:
		shop_owner_anim.play("pleasant")
	else:
		shop_owner_anim.play("wrath")
	pass


func _on_texture_rect_2_animation_finished() -> void:
	next_game()
	pass # Replace with function body.

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("shop_left"):
		current_select -= 1
		if current_select < 0:
			current_select = selectable_items.size() - 1  # 循环到最后一个
		print("left")
		update_selection()

	if event.is_action_pressed("shop_right"):
		current_select += 1
		if current_select >= selectable_items.size():
			current_select = 0
		print("right")
		update_selection()

	if event.is_action_pressed("shop_purchase"):
		if not selectable_items.is_empty():
			var data = selectable_items[current_select]
			_on_item_bought(data["item_node"], data["goods_node"])
	
	if event.is_action_pressed("shop_next"):
		next_game_btn.pressed.emit()
