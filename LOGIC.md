# GoldMiner 逻辑链路汇总

> 本文档汇总了整个项目的数据流、控制流、信号连接关系，方便手动修改时快速定位影响范围。

---

## 一、场景跳转总链路

```
┌─────────────┐   Space/手柄A   ┌─────────────┐   Timer到期   ┌─────────────┐
│  start.tscn │ ───────────────→│  goal.tscn  │ ─────────────→│  main.tscn  │
│  (开始界面)  │                 │ (目标分数展示)│               │  (核心关卡)  │
└─────────────┘                 └─────────────┘               └──────┬──────┘
                                                                     │
                                     ┌───────────────────────────────┘
                                     │ Timer到期 / 按Q / 点击退出按钮
                                     ▼
                              ┌─────────────┐
                              │   end.tscn  │
                              │ (结算界面)   │
                              └──────┬──────┘
                                     │
                    ┌────────────────┴────────────────┐
                    │ 判定: total_golds >= target_score │
                    ▼                                   ▼
              ┌─────────────┐                   ┌─────────────┐
              │   胜利分支   │                   │   失败分支   │
              │ → shop.tscn │                   │ → start.tscn│
              │  (商店购买)  │                   │ (重新开始)   │
              └──────┬──────┘                   └─────────────┘
                     │ 点击Next Level / 按S
                     ▼
              ┌─────────────┐
              │  goal.tscn  │  ← 下一关循环开始
              └─────────────┘
```

### 关键变量在跳转时的变化

| 场景 | 触发条件 | Global 变量变化 |
|------|---------|----------------|
| `end.tscn` → `shop.tscn` (胜利) | `win = true` | `current_level += 1`, `current_target_score += 500 + level*100`, 清除一次性道具 |
| `end.tscn` → `start.tscn` (失败) | `win = false` | `current_level = 1`, `current_target_score = basic_golds(650)`, `total_golds = 0`, 清除一次性道具 |
| `shop.tscn` → `goal.tscn` | 动画结束/点击Next Level | `total_golds` 减去购买花费 |

> **修改入口**：`end.gd` 第 68~82 行；`shop.gd` 第 12~14 行、第 143 行

---

## 二、核心战斗循环（Miner 状态机）

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              Miner 状态机                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────┐                                                                │
│  │  SWING   │◄──────────────────────────────────────────────────────────┐    │
│  │ (空闲摆动)│  播放 idle 动画                                           │    │
│  │          │  rotation_degrees = sin(swing_time) * swing_angle         │    │
│  └────┬─────┘                                                           │    │
│       │ 玩家按 Space / 手柄 A                                             │    │
│       ▼                                                                  │    │
│  ┌──────────┐   ┌──────────────────────────────────────────────────┐    │    │
│  │  LAUNCH  │──→│ 发射: hook_extension += launch_speed * delta      │    │    │
│  │ (钩爪下伸)│   │ 视觉: claw.position 与 line.points 同步更新        │    │    │
│  │          │   │ 边界: _is_claw_out_of_bounds() → 自动进入 RETRACT   │    │    │
│  └────┬─────┘   └──────────────────────────────────────────────────┘    │    │
│       │ 碰撞: Claw.Area2D.area_entered                                   │    │
│       ▼                                                                  │    │
│  ┌──────────┐   信号: item_hooked.emit(item) ─────────→ GameMain         │    │
│  │  RETRACT │   信号: bomb_requested.emit() ──────────→ GameMain        │    │
│  │ (回收上升)│   动画: 根据物品 difficulty 播放 end 或 end_hard          │    │
│  │          │   音效: 动画循环时播放 sfx_up                             │    │
│  └────┬─────┘                                                           │    │
│       │ hook_extension <= 0                                              │    │
│       ▼                                                                  │    │
│  信号: item_delivered.emit(item) ───────────────→ GameMain ──────────────┘    │
│  恢复: _restore_claw_sprite(), state = SWING                                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 状态转换条件速查

| 当前状态 | 触发条件 | 下一状态 | 对应代码位置 |
|---------|---------|---------|------------|
| SWING | `event.is_action_pressed("game_shot")` | LAUNCH | `miner.gd:78-79` |
| LAUNCH | `area_entered` (碰撞到物品) | RETRACT | `miner.gd:147, 183` |
| LAUNCH | `_is_claw_out_of_bounds()` | RETRACT | `miner.gd:107-108` |
| RETRACT | `hook_extension <= 0` | SWING | `miner.gd:115-118` |
| RETRACT | 炸弹使用成功 (`release_item()`) | RETRACT (无物品) | `miner.gd:199-213` |

> **修改入口**：
> - 摆动速度/角度 → `miner.gd` 第 19-20 行
> - 发射速度 → `miner.gd` 第 24 行
> - 基础回收速度 → `miner.gd` 第 25-26 行
> - 状态机本身 → `miner.gd` 第 65-72 行 (`_process` 中的 match)

---

## 三、信号连接总表

Miner ↔ GameMain 的信号在 `GameMain._ready()` 中连接：

```gdscript
# GameMain.gd 第 27~30 行
miner.item_hooked.connect(_on_miner_item_hooked)
miner.item_released.connect(_on_miner_item_released)
miner.item_delivered.connect(_on_miner_item_delivered)
miner.bomb_requested.connect(_on_miner_bomb_requested)
```

| 信号 | 发射者 | 接收者 | 触发时机 | 主要作用 |
|------|--------|--------|---------|---------|
| `item_hooked(item)` | Miner | GameMain | 碰撞到可抓取物品时 | 外部决定回收速度；处理爆炸桶事件 |
| `item_released()` | Miner | GameMain | 炸弹炸掉物品后 | 更新 Bomb UI 显示 |
| `item_delivered(item)` | Miner | GameMain | 钩爪完全收回时 | 计算最终分数/问号袋奖励 |
| `bomb_requested()` | Miner | GameMain | 回收中按炸弹键时 | 外部决定是否允许使用 |

> ⚠️ **重要**：`item_hooked` 发出后，GameMain 的回调里**必须调用** `miner.set_retract_speed(speed)`，否则回收速度不会更新。

---

## 四、数值与道具计算链路

### 4.1 分数计算链路

```
物品.value (如 50, 100, 600)
    │
    ▼
GameMain._on_miner_item_delivered()
    │
    ├── 问号袋? ──→ ItemManager.get_bag_reward() ──→ 金钱/力量/炸弹
    │
    └── 普通物品 ──→ ItemManager.calculate_score(base_score, category)
                          │
                          ├── 检查 Global.get_item(Global.Item.BOOK) → ROCK 类 ×3
                          ├── 检查 Global.get_item(Global.Item.BOTTLE) → DIAMOND 类 ×2
                          │
                          └── 返回最终分数
                                │
                                ▼
                          Global.total_golds += final_score
```

> **修改入口**：
> - 倍率数值 → `item_manager.gd` 第 13-17 行 (`_CATEGORY_MULTIPLIERS`)
> - 难度→速度映射 → `item_manager.gd` 第 49 行 (`_DIFFICULTY_SPEED_MAP`)
> - 力量药水加速倍率 → `item_manager.gd` 第 19 行 (`_RETRACT_SPEED_BOOST`)

### 4.2 回收速度计算链路

```
物品.difficulty (1~5)
    │
    ▼
Miner.get_item_difficulty(item)  ──→ 返回 difficulty 值
    │
    ▼
ItemManager.calculate_retract_speed(difficulty, base_speed=300.0)
    │
    ├── 难度系数: _DIFFICULTY_SPEED_MAP[difficulty-1]  (1.0, 0.7, 0.5, 0.35, 0.2)
    ├── 力量系数: 1.5 如果 Global.Item.POWER 为 true，否则 1.0
    │
    └── 结果: 300 * power_mult * difficulty_mult
                  │
                  ▼
            miner.set_retract_speed(speed)
```

> **修改入口**：`item_manager.gd` 第 48-56 行

---

## 五、物品生成链路

```
GameMain._ready()
    │
    ▼
_spawn_items()
    │
    ├── 等待一帧 (防止 Control 布局未就绪)
    ├── 获取 ItemArea 的全局矩形区域
    ├── item_count = 26 + current_level * 4  ← 关卡越高物品越多
    │
    ├── _generate_uniform_positions(area_rect, item_count)
    │       │
    │       ├── 定义安全边距 (top=30, bottom=20, h=50)
    │       ├── 椭圆中心: 水平居中, 垂直 0.45 处 (偏上)
    │       ├── 椭圆半径: rx = safe_w * 0.5, ry = safe_h * 0.65
    │       ├── 拒绝采样: 在椭圆内随机取点，保证最小间距 42px
    │       └── 返回 positions[]
    │
    ├── positions.shuffle()
    │
    └── for i in positions:
            config = _pick_random_item()  ← 按 weight 权重随机
            instance = config["scene"].instantiate()
            instance.position = positions[i]
            instance.add_to_group("grabbable_item")
            add_child(instance)
```

### 物品权重配置表 (`global.gd` 第 18-29 行)

| 物品 | weight | score | radius | 实际概率 |
|------|--------|-------|--------|---------|
| 小金块 | 5 | 50 | 9 | 5/22 ≈ 22.7% |
| 中金块 | 4 | 100 | 50 | 4/22 ≈ 18.2% |
| 岩石1 | 3 | 10 | 30 | 3/22 ≈ 13.6% |
| 岩石2 | 3 | 10 | 30 | 3/22 ≈ 13.6% |
| 钻石 | 1 | 600 | 10 | 1/22 ≈ 4.5% |
| 小猪 | 2 | 5 | 20 | 2/22 ≈ 9.1% |
| 钻石猪 | 1 | 100 | 20 | 1/22 ≈ 4.5% |
| 炸药桶 | 1 | 2 | 30 | 1/22 ≈ 4.5% |
| 问号袋 | 1 | 0 | 20 | 1/22 ≈ 4.5% |

> **修改入口**：
> - 物品池/权重 → `global.gd` 第 18-29 行 (`item_configs`)
> - 生成数量公式 → `GameMain.gd` 第 56 行 (`26 + Global.current_level * 4`)
> - 最小间距 → `GameMain.gd` 第 106 行 (`min_dist = 42.0`)
> - 椭圆形状 → `GameMain.gd` 第 89-103 行 (center, radius_x, radius_y)

---

## 六、爆炸链路（炸药桶）

```
矿工钩中炸药桶 (BombBarrel)
    │
    ▼
miner._on_claw_area_entered()
    ├── hooked_item = barrel
    ├── 替换爪子弹为 barrel.Hooked 纹理
    ├── barrel.visible = false  ← 隐藏原物品
    ├── 播放抓取音效
    └── item_hooked.emit(barrel) ──→ GameMain._on_miner_item_hooked()
                                            │
                                            ▼
                                    GameMain._trigger_explosion(barrel)
                                            │
                                            ├── 重新显示 barrel.visible = true
                                            ├── 隐藏 barrel 的 Area2D 和 Hooked 子节点
                                            ├── barrel.Event.play("explode") ← 播放爆炸动画
                                            ├── await get_tree().process_frame
                                            │
                                            └── 遍历 "grabbable_item" 组:
                                                    if target != barrel and distance <= 150:
                                                        score = target.value
                                                        category = target.category
                                                        final = ItemManager.calculate_score(score, category)
                                                        Global.total_golds += final
                                                        target.queue_free()
                                            │
                                            └── barrel 继续被回收到底 (不会被炸掉)
```

> **修改入口**：
> - 爆炸半径 → `GameMain.gd` 第 171 行 (`radius = 150.0`)
> - 爆炸动画节点名 → `GameMain.gd` 第 175 行 (`"Event"`)
> - 炸药桶属性 → `bomb_barrel.tscn` 第 47-50 行 (`hooked_event = 1` 即 EXPLODE)

---

## 七、问号袋奖励链路

```
矿工回收问号袋 (UnknownItem) 到底
    │
    ▼
miner._finish_retract()
    └── item_delivered.emit(item) ──→ GameMain._on_miner_item_delivered()
                                            │
                                            ├── 读取 item.recycle_finish_event / recycle_finish_evetn
                                            │       (兼容拼写错误的字段)
                                            │
                                            └── 如果是 GET_RANDOM_EFFECT (值为 1):
                                                    reward = ItemManager.get_bag_reward()
                                                    GameMain._play_reward_animation(reward)
                                                            │
                                                            ├── MONEY ──→ _play_money_animation() ──→ total_golds += amount
                                                            ├── STRENGTH ──→ Global.Item.POWER = true + 播放飘字动画
                                                            │                    └── 若正在回收，立即调用 miner.set_retract_speed() 加速
                                                            └── BOMB ──→ Global.add_bomb() + 播放飞入动画
```

### 问号袋奖励池 (`item_manager.gd` 第 22-31 行)

| 奖励 | 值 | weight | 概率 |
|------|-----|--------|------|
| 金钱 $10 | 10 | 4 | 4/23 |
| 金钱 $50 | 50 | 5 | 5/23 |
| 金钱 $100 | 100 | 4 | 4/23 |
| 金钱 $200 | 200 | 3 | 3/23 |
| 金钱 $400 | 400 | 2 | 2/23 |
| 金钱 $600 | 600 | 1 | 1/23 |
| Strength | — | 2 | 2/23 |
| Bomb | — | 2 | 2/23 |

> **修改入口**：`item_manager.gd` 第 22-31 行 (`_BAG_REWARD_POOL`)

---

## 八、商店购买链路

```
shop.gd _ready()
    │
    ├── weight_pool = [1,2,2,3,3,3,3,3,4,4,5]
    ├── max_items_to_sell = weight_pool.pick_random()  ← 1~5个商品
    │
    ├── 遍历 Item_1 ~ Item_5:
    │       前 max_items_to_sell 个显示，其余 hide()
    │       读取 goods_node.price_base 显示价格
    │       绑定鼠标信号 mouse_entered / pressed
    │
    └── 键盘/手柄输入:
            A/D 或 ←/→ ──→ 切换选中
            Space ───────→ _on_item_bought() 购买当前选中
            S ───────────→ next_game() 进入下一关

_on_item_bought(item_node, goods_node):
    │
    ├── 钱不够? → shop_owner_anim.play("wrath")
    │
    └── 钱够? → Global.total_golds -= price
            │
            ├── goods_node.type == BOMB? → Global.add_bomb()
            └── 其他类型? ──→ Global.set_item(type, true)
            │
            └── item_node.hide()  ← 购买后隐藏该商品
```

### 商店商品与 Global.Item 枚举对应

| 场景节点 | goods_base.type | 含义 | 价格来源 |
|---------|----------------|------|---------|
| `item_bomb.tscn` | `Global.Item.BOMB` | 炸弹 (+1) | `goods_base.price_base` |
| `item_book.tscn` | `Global.Item.BOOK` | 矿石书 (岩石×3) | `goods_base.price_base` |
| `item_bottle.tscn` | `Global.Item.BOTTLE` | 钻石瓶 (钻石×2) | `goods_base.price_base` |
| `item_power.tscn` | `Global.Item.POWER` | 力量药水 (加速) | `goods_base.price_base` |
| `item_staw.tscn` | `Global.Item.STRAW` | 幸运草 (预留) | `goods_base.price_base` |

> **修改入口**：
> - 商品数量概率 → `shop.gd` 第 46 行 (`weight_pool`)
> - 各商品价格 → 各 `item_*.tscn` 中 `goods_base.gd` 的 `price_base` 字段
> - 商店店主动画 → `shop.tscn` 中 `TextureRect2` 的 SpriteFrames

---

## 九、修改速查表

| 你想改什么 | 去改哪里 | 影响范围 |
|-----------|---------|---------|
| **开局目标分数** | `global.gd:33` (`basic_golds`) | 第1关目标分数 |
| **每关时间** | `global.gd:34` (`basic_time`) | 所有关卡时长 |
| **过关后分数增长** | `end.gd:72` (`500 + level * 100`) | 关卡难度曲线 |
| **钩爪摆动速度/角度** | `miner.gd:19-20` | 发射前手感 |
| **钩爪发射速度** | `miner.gd:24` | 发射快慢 |
| **基础回收速度** | `miner.gd:25-26` | 空钩回收速度 |
| **力量药水加速倍率** | `item_manager.gd:19` | 全局力量效果强度 |
| **难度→速度映射表** | `item_manager.gd:49` | 各难度物品回收速度 |
| **物品池/权重/分值** | `global.gd:18-29` | 关卡内物品分布 |
| **每关生成物品数量** | `GameMain.gd:56` | 关卡密度 |
| **物品最小间距** | `GameMain.gd:106` | 物品堆叠程度 |
| **爆炸桶爆炸半径** | `GameMain.gd:171` | 爆炸范围 |
| **问号袋奖励池** | `item_manager.gd:22-31` | 问号袋期望收益 |
| **各类道具倍率** | `item_manager.gd:13-17` | BOOK/BOTTLE 效果 |
| **音效文件** | `global.gd:91-98` | 所有场景音效 |
| **关卡背景图** | `global.gd:4-9` (`game_maps`) | 背景轮换 |
| **商店商品数量分布** | `shop.gd:46` (`weight_pool`) | 每次出现商品个数 |
| **商店商品价格** | 各 `item_*.tscn` 中 `price_base` | 购买成本 |
| **按键映射** | `project.godot` [input] 段 | 全游戏按键 |

---

## 十、已知遗留问题（修改建议）

1. **拼写错误**：`item_base.gd` 第 11 行 `recycle_finish_evetn` 应为 `recycle_finish_event`
   - 当前 `GameMain.gd` 第 221-224 行有兼容代码，建议统一修正后删除兼容分支。

2. **big_gold 已注释**：`global.gd` 第 21 行大金块场景被注释，如需启用取消注释即可。

3. **幸运草未实现**：`Global.Item.STRAW` 在商店可购买，但 `item_manager.gd` 第 65-66 行注释说明"后续可扩展"，目前没有任何效果。

4. **Miner 碰撞体积**：`miner.tscn` 中 `Claw/CollisionShape2D` 为 `RectangleShape2D(23, 12)`，如需调整钩爪判定大小改此处。
