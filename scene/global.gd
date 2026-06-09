extends Node

#const
const game_maps = [
	preload("res://resource/Map_1.jpg"),
	preload("res://resource/Map_2.jpg"),
	preload("res://resource/Map_3.jpg"),
	preload("res://resource/Map_4.jpg"),
]

enum Item {BOOK, POWER, STRAW, BOMB, BOTTLE}
enum Behavior {NULL, MOVE}
enum Hooked_Event {NULL, EXPLODE}
enum Hooked_Category {GOLD, ROCK, PIG, DIAMOND, BAG, BOMB_BARREL, TRASH}
enum Recycle_Event {NULL, MULTIPLIED_MONEY}
enum Recycle_Finish_Event {NULL, GET_RANDOM_EFFECT}

var item_configs = [
	{"scene": preload("res://scene/small_gold.tscn"),        "weight": 5, "score": 50,  "radius": 9},
	{"scene": preload("res://scene/middle_size_gold.tscn"),  "weight": 4, "score": 100, "radius": 50},
	#{"scene": preload("res://scene/big_gold.tscn"),          "weight": 2, "score": 500, "radius": 105},
	{"scene": preload("res://scene/rock_1.tscn"),            "weight": 3, "score": 10,  "radius": 30},
	{"scene": preload("res://scene/rock_2.tscn"),            "weight": 3, "score": 10,  "radius": 30},
	{"scene": preload("res://scene/diamond.tscn"),           "weight": 1, "score": 600, "radius": 10},
	{"scene": preload("res://scene/pig.tscn"),               "weight": 2, "score": 5,   "radius": 20},
	{"scene": preload("res://scene/diamond_pig.tscn"),       "weight": 1, "score": 100, "radius": 20},
	{"scene": preload("res://scene/bomb_barrel.tscn"),       "weight": 1, "score": 2,   "radius": 30},
	{"scene": preload("res://scene/unkown_item.tscn"),       "weight": 1, "score": 0,   "radius": 20},
	{"scene": preload("res://scene/bone.tscn"), "weight":1, "score":5, "radius": 20},
	{"scene": preload("res://scene/head_bone.tscn"), "weight":1, "score":5, "radius": 20},
]


#configs
const basic_golds: int = 650
const basic_time: float = 60.0
const goal_display_time: float = 2.0
const end_display_time: float = 2.0

#total infos
var total_golds: int = 0

var total_items: Dictionary = {
	Item.BOMB: 0,
	Item.BOOK: false,
	Item.POWER: false,
	Item.STRAW: false,
	Item.BOTTLE: false,
}


# ========== Getter ==========
func get_item(item: Item) -> Variant:
	return total_items[item]

# ========== Setter ==========
func set_item(item: Item, value: Variant) -> void:
	match item:
		Item.BOMB:
			# BOMB 必须是 0~4 的整数
			if value is int and value >= 0 and value <= 4:
				total_items[item] = value
			else:
				push_error("BOMB 必须是 0~4 的整数，收到: %s" % value)
		
		Item.BOOK, Item.POWER, Item.STRAW, Item.BOTTLE:
			# 其他必须是 bool
			if value is bool:
				total_items[item] = value
			else:
				push_error("%s 必须是 bool，收到: %s" % [Item.keys()[item], value])
		
		_:
			push_error("未知物品类型: %s" % item)

# ========== 便捷方法 ==========
func has_bomb() -> bool:
	return total_items[Item.BOMB] > 0

func add_bomb(amount: int = 1) -> void:
	set_item(Item.BOMB, total_items[Item.BOMB] + amount)

func use_bomb() -> void:
	if total_items[Item.BOMB] > 0:
		set_item(Item.BOMB, total_items[Item.BOMB] - 1)


#current infos
var current_target_score: int = 650    # 本关目标分数
var current_level: int = 1     # 当前关卡

# ---- sfx 资源集中化 ----
var sfx_down: AudioStream = preload("res://resource/down.ogg")
var sfx_up: AudioStream = preload("res://resource/up.ogg")
var sfx_score_add: AudioStream = preload("res://resource/scoreAdd.ogg")
var sfx_goal: AudioStream = preload("res://resource/goal.ogg")
var sfx_win: AudioStream = preload("res://resource/win.ogg")
var sfx_hv_cool: AudioStream = preload("res://resource/hvCool.ogg")
var sfx_hv_good: AudioStream = preload("res://resource/hvGood.ogg")
var sfx_hv_bad: AudioStream = preload("res://resource/hvBad.ogg")
var sfx_hv_explode: AudioStream = preload("res://resource/boom.ogg")

## 播放一次性音效，播放结束后自动释放
func play_sfx(stream: AudioStream, parent: Node) -> void:
	var sfx = AudioStreamPlayer.new()
	sfx.stream = stream
	parent.add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)
	
	
	
	
