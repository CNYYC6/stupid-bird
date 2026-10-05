extends CanvasLayer
## HUD：飞行距离与金币数。
##
## 速度读数被删掉了：跑酷里距离和金币才是目标，速度是玩家能直接感觉到的，
## 而且三块读数并排会超出 1920 宽度。速度仍然在后台驱动升力。

@onready var _distance: HBoxContainer = $Root/Bar/DistancePlate/Distance/Digits
@onready var _coins: HBoxContainer = $Root/Bar/CoinPlate/Coin/Digits


## 飞行距离（米）
func set_distance(meters: float) -> void:
	_distance.set_value(floori(meters))


## 金币数
func set_coins(count: int) -> void:
	_coins.set_value(count)
