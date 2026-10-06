extends Control
## 开屏：手写体 "YYCHRER" 七个字母一个一个慢慢浮出来，然后进主菜单。
##
## 字母贴图由 tools/gen_logo.py 逐个烘出来（二值化之后才放大，边缘才是方块），
## 这里只负责摆放和动画 —— 位置是手算的，不用容器，
## 因为容器会在动画期间反复重排，和 scale 打架。

const LETTERS := 7
const TEXT_W: float = 1400.0     ## 整词宽度（1920 的 73%）
const GAP: float = 26.0          ## 字母间距（原生像素）
const STEP: float = 0.55         ## 每个字母之间的间隔（秒）
const POP: float = 0.5           ## 单个字母浮出来的时长
const HOLD: float = 1.6          ## 全部出现后停多久
const FADE: float = 0.8          ## 淡出时长

var _letters: Array[TextureRect] = []
var _elapsed: float = 0.0
var _done: bool = false


func _ready() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var tex: Array[Texture2D] = []
	for i in LETTERS:
		tex.append(load("res://art/logo/letter_%d.png" % i))

	var total: float = 0.0
	for t in tex:
		total += t.get_width()
	total += GAP * (LETTERS - 1)
	var k: float = TEXT_W / total

	var x: float = (vp.x - TEXT_W) * 0.5
	var cy: float = vp.y * 0.46
	for i in LETTERS:
		var r := TextureRect.new()
		r.texture = tex[i]
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.size = tex[i].get_size() * k
		r.position = Vector2(x, cy - r.size.y * 0.5)
		# scale 绕中心，不然字母会往右下角"长"
		r.pivot_offset = r.size * 0.5
		r.scale = Vector2(0.72, 0.72)
		r.modulate.a = 0.0
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(r)
		_letters.append(r)
		x += r.size.x + GAP * k

	# 背景淡入
	var bg: ColorRect = $Bg
	bg.modulate.a = 0.0
	create_tween().tween_property(bg, "modulate:a", 1.0, 0.6)
	var hint: TextureRect = $Hint
	hint.modulate.a = 0.0
	create_tween().tween_property(hint, "modulate:a", 0.85, 0.5).set_delay(1.8)

	UiLang.apply(self)
	_run()


## 七个字母依次浮出：淡入 + 从 0.72 倍弹到原尺寸 + 轻微上移
func _run() -> void:
	for i in _letters.size():
		var r: TextureRect = _letters[i]
		var y0: float = r.position.y
		var t := create_tween().set_parallel(true)
		t.tween_property(r, "modulate:a", 1.0, POP).set_delay(i * STEP)
		t.tween_property(r, "scale", Vector2.ONE, POP) \
			.set_delay(i * STEP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(r, "position:y", y0 - 14.0, POP) \
			.set_delay(i * STEP).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed >= LETTERS * STEP + HOLD:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_finish()
	elif event is InputEventJoypadButton and event.pressed:
		_finish()
	elif event is InputEventMouseButton and event.pressed:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	Audio.play("ui")
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, FADE)
	t.tween_callback(func() -> void:
		get_tree().change_scene_to_file("res://scenes/start_menu.tscn"))
