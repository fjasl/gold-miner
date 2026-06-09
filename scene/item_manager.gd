extends Node
## 道具效果集中管理器
## 所有道具的数值配置、效果计算、使用逻辑统一放在这里
## 各脚本只调用接口，不写死任何道具逻辑


# ==================== 问号袋奖励类型 ====================

enum Bag_Reward_Type {MONEY, STRENGTH, BOMB}

# ==================== 道具效果配置表 ====================

const _CATEGORY_MULTIPLIERS: Dictionary = {
	# 道具类型 → {目标类别: 倍率}
	Global.Item.BOOK:   {"category": Global.Hooked_Category.ROCK,    "multiplier": 3},
	Global.Item.BOTTLE: {"category": Global.Hooked_Category.DIAMOND, "multiplier": 2},
}

const _RETRACT_SPEED_BOOST: float = 1.5

# 问号袋奖励池：每项含 type / weight，金钱类额外含 value
const _BAG_REWARD_POOL: Array = [
	{"type": Bag_Reward_Type.MONEY, "value": 10,  "weight": 4},
	{"type": Bag_Reward_Type.MONEY, "value": 50,  "weight": 5},
	{"type": Bag_Reward_Type.MONEY, "value": 100, "weight": 4},
	{"type": Bag_Reward_Type.MONEY, "value": 200, "weight": 3},
	{"type": Bag_Reward_Type.MONEY, "value": 400, "weight": 2},
	{"type": Bag_Reward_Type.MONEY, "value": 600, "weight": 1},
	{"type": Bag_Reward_Type.STRENGTH, "weight": 2},
	{"type": Bag_Reward_Type.BOMB, "weight": 2},
]


# ==================== 分值计算 ====================

## 计算最终分值：应用所有激活的类别倍率道具
func calculate_score(base_score: int, category: Global.Hooked_Category) -> int:
	var final_score = base_score
	for item_type in _CATEGORY_MULTIPLIERS:
		var config = _CATEGORY_MULTIPLIERS[item_type]
		if Global.get_item(item_type) and category == config["category"]:
			final_score *= config["multiplier"]
	return final_score


# ==================== 回收速度 ====================

## 难度 → 回收速度的映射（difficulty 1-5）
const _DIFFICULTY_SPEED_MAP: Array = [1.0, 0.7, 0.5, 0.35, 0.2]

## 根据物品难度，计算最终回收速度（含力量药水加成）
func calculate_retract_speed(difficulty: int, base_speed: float = 300.0) -> float:
	var speed_index = clampi(difficulty - 1, 0, _DIFFICULTY_SPEED_MAP.size() - 1)
	var difficulty_mult = _DIFFICULTY_SPEED_MAP[speed_index]
	var power_mult = _RETRACT_SPEED_BOOST if Global.get_item(Global.Item.POWER) else 1.0
	return base_speed * power_mult * difficulty_mult


# ==================== 问号袋奖励 ====================

## 生成问号袋随机奖励，返回字典：{"type": Bag_Reward_Type, "value": ...}
func get_bag_reward() -> Dictionary:
	var pool = _BAG_REWARD_POOL.duplicate(true)
	
	# 幸运草：提升高价值奖励概率（后续可扩展）
	# 当前逻辑保持默认权重
	
	var total_weight = 0
	for entry in pool:
		total_weight += entry["weight"]
	
	var roll = randi() % total_weight
	var cumulative = 0
	for entry in pool:
		cumulative += entry["weight"]
		if roll < cumulative:
			var result = entry.duplicate()
			result.erase("weight")
			return result
	
	return {"type": Bag_Reward_Type.MONEY, "value": 50}


# ==================== 炸弹 ====================

## 尝试使用炸弹。返回是否成功。
func try_use_bomb() -> bool:
	if not Global.has_bomb():
		return false
	Global.use_bomb()
	return true


# ==================== 关卡生命周期 ====================

## 清除所有一次性道具（每关结束后调用）
func clear_one_time_items() -> void:
	Global.set_item(Global.Item.BOOK,   false)
	Global.set_item(Global.Item.POWER,  false)
	Global.set_item(Global.Item.STRAW,  false)
	Global.set_item(Global.Item.BOTTLE, false)
