class_name Miner
extends Node2D
## 矿工 —— 纯状态机
## 职责：摆动、发射、回收的状态流转 + 视觉表现
## 不内嵌任何道具/游戏逻辑，所有决策通过信号抛给外部

enum State {SWING, LAUNCH, RETRACT}

# ===== 状态机事件（外部监听并决定如何处理） =====
signal item_hooked(item: Node)       ## 钩中了物品，外部决定回收速度等
signal item_released()               ## 物品在中途被释放（炸弹等）
signal item_delivered(item: Node)    ## 物品成功回收到底
signal bomb_requested()              ## 玩家在回收中按下了炸弹键

# ===== 状态 =====
var state: State = State.SWING

# 摆动参数
var swing_speed: float = 1.5
var swing_angle: float = 72.5
var swing_time: float = 0.0

# 钩爪参数
var launch_speed: float = 400.0
var retract_speed: float = 300.0
var base_retract_speed: float = 300.0
var hook_extension: float = 0.0

@onready var hook_pivot: Node2D = $HookPivot
@onready var line: Line2D = $HookPivot/Line2D
@onready var claw: Area2D = $HookPivot/Claw
@onready var claw_sprite: Sprite2D = $HookPivot/Claw/Sprite2D
@onready var body: AnimatedSprite2D = $Body

var initial_claw_pos: Vector2
var extend_direction: Vector2
var line_end_offset: Vector2

# 抓取相关
var hooked_item: Node = null
var original_claw_texture: Texture2D
var original_claw_offset: Vector2
var original_claw_scale: Vector2

# 炸弹序列标记：true 表示正在等 "bomb" 动画播完后执行 release
var _bomb_release_pending: bool = false


func _ready() -> void:
	initial_claw_pos = claw.position
	extend_direction = initial_claw_pos.normalized()
	
	# 修正 Line2D 缩放
	var actual_line_end = line.position + line.points[1] * line.scale
	line.position = Vector2.ZERO
	line.scale = Vector2.ONE
	line.points = PackedVector2Array([Vector2.ZERO, actual_line_end])
	line_end_offset = actual_line_end - initial_claw_pos
	
	# 保存钩爪原始外观
	original_claw_texture = claw_sprite.texture
	original_claw_offset = claw_sprite.position
	original_claw_scale = claw_sprite.scale
	
	claw.area_entered.connect(_on_claw_area_entered)


func _process(delta: float) -> void:
	match state:
		State.SWING:
			_process_swing(delta)
		State.LAUNCH:
			_process_launch(delta)
		State.RETRACT:
			_process_retract(delta)


func _input(event: InputEvent) -> void:
	match state:
		State.SWING:
			if event.is_action_pressed("game_shot"):
				_start_launch()
		State.RETRACT:
			# 回收过程中按下炸弹键 → 只发信号，外部决定是否处理
			if event.is_action_pressed("game_bomb"):
				bomb_requested.emit()


# ---- 状态处理 ----

func _process_swing(delta: float) -> void:
	if not is_instance_valid(hook_pivot):
		return
	swing_time += delta * swing_speed
	hook_pivot.rotation_degrees = sin(swing_time) * swing_angle


func _start_launch() -> void:
	state = State.LAUNCH
	hook_extension = 0.0
	body.play("start")
	Global.play_sfx(Global.sfx_down, self)


func _process_launch(delta: float) -> void:
	if not is_instance_valid(claw):
		return
	hook_extension += launch_speed * delta
	_update_hook_visual()
	if _is_claw_out_of_bounds():
		_start_retract(null)


func _process_retract(delta: float) -> void:
	if not is_instance_valid(claw) or not is_instance_valid(line):
		return
	hook_extension -= retract_speed * delta
	if hook_extension <= 0.0:
		hook_extension = 0.0
		_update_hook_visual()
		_finish_retract()
		return
	_update_hook_visual()


func _start_retract(item) -> void:
	state = State.RETRACT
	if item == null:
		body.play("end")
	elif item.has_method("get") and "difficulty" in item:
		if item.difficulty < 3:
			body.play("end")
		else:
			body.play("end_hard")
	else:
		body.play("end_hard")


func _finish_retract() -> void:
	if hooked_item:
		item_delivered.emit(hooked_item)
		_destroy_hooked_item()
	_restore_claw_sprite()
	state = State.SWING
	body.play("idle")


# ---- 抓取逻辑 ----

func _on_claw_area_entered(area: Area2D) -> void:
	if state != State.LAUNCH:
		return
	if hooked_item:
		return
	
	var item = area.get_parent()
	if not item:
		return
	
	hooked_item = item
	
	# 替换钩爪纹理
	var hooked_sprite = item.get_node_or_null("Hooked")
	if hooked_sprite and hooked_sprite is Sprite2D:
		claw_sprite.texture = hooked_sprite.texture
		claw_sprite.position = original_claw_offset + hooked_sprite.position
		claw_sprite.scale = hooked_sprite.scale
	
	# 隐藏原物品
	item.visible = false
	
	# 发出钩中信号，外部（GameMain/ItemManager）决定回收速度等
	# 注意：外部应在连接此信号的回调中调用 miner.set_retract_speed()
	item_hooked.emit(item)
	
	# 播放抓取音效
	var tag = item.get("sound_tag") if item.get("sound_tag") != null else "good"
	var sfx_map = {
		"cool": Global.sfx_hv_cool,
		"good": Global.sfx_hv_good,
		"bad": Global.sfx_hv_bad,
	}
	if tag in sfx_map:
		Global.play_sfx(sfx_map[tag], self)
	
	_start_retract(hooked_item)


# ---- 外部可调用的接口 ----

## 外部设置回收速度（如力量药水、物品难度等）
func set_retract_speed(speed: float) -> void:
	retract_speed = speed


## 外部获取当前抓取的物品
func get_hooked_item() -> Node:
	return hooked_item


## 播放炸弹动画序列：先播 "bomb"，动画结束后才执行真正的 release
func play_bomb_sequence() -> void:
	if not hooked_item:
		return
	_bomb_release_pending = true
	body.play("bomb")


## 外部强制释放当前物品（炸弹等）
func release_item() -> void:
	if not hooked_item:
		return
	
	# 播放爆炸动画
	var blow_out = $HookPivot/Claw/BlowOut
	if blow_out:
		blow_out.visible = true
		blow_out.play("explode")
		if not blow_out.animation_finished.is_connected(_on_blow_out_finished):
			blow_out.animation_finished.connect(_on_blow_out_finished)
	
	_destroy_hooked_item()
	item_released.emit()
	_restore_claw_sprite()


## 获取物品难度（供外部计算速度用）
static func get_item_difficulty(item: Node) -> int:
	if item.has_method("get") and "difficulty" in item:
		return item.difficulty
	elif item.get("difficulty") != null:
		return item.get("difficulty")
	return 1


# ---- 内部辅助 ----

func _destroy_hooked_item() -> void:
	if hooked_item:
		hooked_item.queue_free()
		hooked_item = null


func _restore_claw_sprite() -> void:
	claw_sprite.texture = original_claw_texture
	claw_sprite.position = original_claw_offset
	claw_sprite.scale = original_claw_scale
	retract_speed = base_retract_speed


func _on_blow_out_finished() -> void:
	var blow_out = $HookPivot/Claw/BlowOut
	if blow_out:
		blow_out.visible = false


func _update_hook_visual() -> void:
	if not is_instance_valid(claw) or not is_instance_valid(line):
		return
	claw.position = initial_claw_pos + extend_direction * hook_extension
	line.points = PackedVector2Array([line.points[0], claw.position + line_end_offset])


func _is_claw_out_of_bounds() -> bool:
	if not is_instance_valid(claw):
		return false
	var claw_global = claw.global_position
	var screen = get_viewport_rect().size
	return claw_global.x < 0 or claw_global.x > screen.x \
		or claw_global.y < 0 or claw_global.y > screen.y


func _on_body_animation_looped() -> void:
	if state != State.RETRACT:
		return
	var anim = body.animation
	if anim == "end" or anim == "end_hard":
		Global.play_sfx(Global.sfx_up, self)


func _on_body_animation_finished() -> void:
	if body.animation == "body":
		body.play("idle")
		
	if body.animation == "strength":
		body.play("idle")
	
	if body.animation == "bomb" and _bomb_release_pending:
		Global.play_sfx(Global.sfx_hv_explode, body)
		_bomb_release_pending = false
		release_item()
