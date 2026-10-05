extends HBoxContainer
## 用点阵数字贴图显示一个非负整数。HUD 和开始界面共用。
##
## 数字走贴图而不是字体，是为了和像素美术保持同一套颗粒，
## 顺便也避开了 Godot 默认字体不含中文字形的问题。

const DIGIT_PATH: String = "res://pic/ui_digit_%d.png"

## 固定显示几位（多出来的高位隐藏）
@export var digits: int = 5

## true = 补前导零到固定宽度，false = 只显示有效位
@export var pad_zeros: bool = false

var _textures: Array[Texture2D] = []
var _cells: Array[TextureRect] = []
var _value: int = -1


func _ready() -> void:
	for i in 10:
		_textures.append(load(DIGIT_PATH % i))
	for i in maxi(digits, 1):
		var cell := TextureRect.new()
		cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.visible = false
		add_child(cell)
		_cells.append(cell)
	set_value(0)


func set_value(value: int) -> void:
	value = maxi(value, 0)
	if value == _value:
		return
	_value = value

	var text: String = str(value)
	if pad_zeros:
		text = text.pad_zeros(_cells.size())
	elif text.length() > _cells.size():
		# 超过显示位数时按里程表处理：丢掉最高位，而不是错误地显示高几位
		text = text.substr(text.length() - _cells.size())
	var shown: int = mini(text.length(), _cells.size())

	for i in _cells.size():
		var cell: TextureRect = _cells[i]
		# 右对齐：个位永远落在最后一格
		var idx: int = i - (_cells.size() - shown)
		if idx < 0:
			cell.visible = false
			continue
		cell.visible = true
		cell.texture = _textures[text.unicode_at(idx) - 48]
