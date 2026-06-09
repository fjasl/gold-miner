extends Node2D
## 所有可交互物品的基础脚本
## 挂到物品根节点 (Node2D) 上，在编辑器 Inspector 中设置属性

@export_range(1, 5) var difficulty: int = 1    # 难度 1-5，影响回收速度
@export var category: Global.Hooked_Category
@export var value: int = 50                     # 分数价值
@export var behavior: Global.Behavior = Global.Behavior.NULL
@export var hooked_event: Global.Hooked_Event = Global.Hooked_Event.NULL       #默认没有 触碰事件类型: normal / explode / ...
@export var recycle_event:Global.Recycle_Event = Global.Recycle_Event.NULL
@export var recycle_finish_event:Global.Recycle_Finish_Event = Global.Recycle_Finish_Event.NULL #如果有可能发生的回收事件
@export_enum("cool", "good", "bad") var sound_tag: String = "good"  # 抓取音效标签

# 移动行为参数
var _initial_position: Vector2
var _move_direction: int = 1
var _move_speed: float = 0.0
var _move_range: float = 0.0

func _ready() -> void:
	_initial_position = position
	if behavior == Global.Behavior.MOVE:
		_move_direction = 1 if randf() > 0.5 else -1
		_move_speed = randf_range(20.0, 40.0)
		_move_range = randf_range(60.0, 150.0)

func _process(delta: float) -> void:
	if behavior == Global.Behavior.MOVE:
		position.x += _move_speed * _move_direction * delta
		var dist = position.x - _initial_position.x
		if abs(dist) >= _move_range:
			_move_direction *= -1
			position.x = _initial_position.x + _move_range * sign(dist)


## 获取被钩中时替换的纹理
func get_hooked_texture() -> Texture2D:
	var hooked_sprite = get_node_or_null("Hooked")
	if hooked_sprite and hooked_sprite is Sprite2D:
		return hooked_sprite.texture
	return null

## 获取 Hooked 节点的 offset（位置偏移和缩放）
func get_hooked_offset() -> Vector2:
	var hooked_sprite = get_node_or_null("Hooked")
	if hooked_sprite:
		return hooked_sprite.position
	return Vector2.ZERO

func get_hooked_scale() -> Vector2:
	var hooked_sprite = get_node_or_null("Hooked")
	if hooked_sprite:
		return hooked_sprite.scale
	return Vector2.ONE
