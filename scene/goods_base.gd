extends Node2D

@export var price_base: int = 50                     # 分数价值
@export var type: Global.Item 
@export var detail: String =""
### 获取商品纹理的纹理
func get_goods_texture() -> Texture2D:
	var goods_texture = get_node_or_null("Item")
	if goods_texture and goods_texture is Sprite2D:
		return goods_texture.texture
	return null
