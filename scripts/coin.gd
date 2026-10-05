extends Area2D
## 金币：碰到就吃掉，带 4 帧旋转动画。
##
## 帧贴图放在 static 数组里，所有金币实例共享，不会每个都重新 load。

signal collected(who: Node2D)

const FRAME_PATHS: Array[String] = [
	"res://art/coin_0.png", "res://art/coin_1.png",
	"res://art/coin_2.png", "res://art/coin_3.png",
]
const FRAME_TIME: float = 0.085

static var _frames: Array[Texture2D] = []

@onready var _sprite: Sprite2D = $Sprite

var _timer: float = 0.0
var _index: int = 0


func _ready() -> void:
	add_to_group("coin")
	if _frames.is_empty():
		for path in FRAME_PATHS:
			_frames.append(load(path))
	_sprite.texture = _frames[0]
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_timer += delta
	if _timer < FRAME_TIME:
		return
	_timer = 0.0
	_index = (_index + 1) % _frames.size()
	_sprite.texture = _frames[_index]


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	collected.emit(body)
	queue_free()
