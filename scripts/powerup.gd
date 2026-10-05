extends Area2D
## 漂浮道具：磁铁 / 护盾 / 金币爆发。
##
## 判定盒比图标大一圈 —— 道具是奖励，不该因为几像素的误差错过。
## 上下浮动纯粹是为了在满屏金币里能被一眼认出来。

signal picked(kind: int)

enum Kind { MAGNET, SHIELD, BURST }

const TEX: Array[String] = [
	"res://art/pu_magnet.png",
	"res://art/pu_shield.png",
	"res://art/pu_burst.png",
]

const BOB_AMP: float = 16.0
const BOB_SPEED: float = 2.4
## 图标是 32x32 原生像素，放大 3 倍 = 96 屏幕像素，和 132 像素高的小鸟比例舒服
const ICON_SCALE: float = 3.0

var kind: int = Kind.MAGNET

@onready var _sprite: Sprite2D = $Sprite

var _t: float = 0.0
var _base_y: float = 0.0
var _taken: bool = false


func _ready() -> void:
	add_to_group("powerup")
	_sprite.texture = load(TEX[clampi(kind, 0, TEX.size() - 1)])
	_sprite.scale = Vector2(ICON_SCALE, ICON_SCALE)
	_base_y = position.y
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	position.y = _base_y + sin(_t * BOB_SPEED) * BOB_AMP
	if _taken:
		# 被吃掉之后快速放大淡出，给一个"拿到了"的反馈
		_sprite.scale += Vector2.ONE * delta * 26.0
		modulate.a = maxf(modulate.a - delta * 4.0, 0.0)
		if modulate.a <= 0.0:
			queue_free()


func _on_body_entered(body: Node2D) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	# 必须 deferred：Godot 不允许在 Area2D 的信号回调里直接改 monitoring
	set_deferred("monitoring", false)
	picked.emit(kind)
