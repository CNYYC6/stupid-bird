class_name UiLang
## 界面文字的多语言。
##
## 本作的文字是**烘进贴图**的（Godot 默认字体不含中文，写中文会变豆腐块），
## 所以多语言的做法是"同一张图生成两套"：`tools/gen_ui.py` 会同时产出
## `art/ui/en/` 和 `art/ui/zh/`，两套的**文件名完全一致**。
##
## 于是运行期换语言不需要任何映射表 —— 文件名本身就是 key，
## 把路径里的 `/ui/<lang>/` 换掉就行。见 `apply()`。

const CODES: Array[String] = ["en", "zh"]
const NAMES: Array[String] = ["English", "中文"]
## 默认英语（上架 Steam 面向全球，默认英文更合理）
const DEFAULT_ID: int = 0
const SETTING_KEY: String = "language"
const ROOT: String = "res://art/ui/"


static func lang_id() -> int:
	return clampi(RunRecord.load_setting(SETTING_KEY, DEFAULT_ID), 0, CODES.size() - 1)


static func code() -> String:
	return CODES[lang_id()]


static func set_lang(i: int) -> void:
	RunRecord.save_setting(SETTING_KEY, clampi(i, 0, CODES.size() - 1))


## 取某张界面贴图在当前语言下的完整路径。
## key 传文件名（如 "ui_btn_start.png"）或省略扩展名都行。
static func path(key: String, c: String = "") -> String:
	if not key.ends_with(".png"):
		key += ".png"
	return ROOT + (c if c != "" else code()) + "/" + key


## 把一个已经带语言的路径换成目标语言。不是界面贴图就原样返回。
static func swap_path(p: String, c: String) -> String:
	var i: int = p.find("/art/ui/")
	if i < 0:
		return p
	return "res://art/ui/%s/%s" % [c, p.get_file()]


static func swap_tex(t: Texture2D, c: String) -> Texture2D:
	if t == null:
		return null
	var p: String = t.resource_path
	if p == "" or p.find("/art/ui/") < 0:
		return t
	var np: String = swap_path(p, c)
	if np == p:
		return t
	var res: Texture2D = load(np)
	return res if res != null else t


## 遍历整棵界面树，把所有指向 art/ui/ 的贴图换成当前语言的。
## 语言切换后重新调用一次即可，可以反复调用（每次都是从文件名重建路径）。
static func apply(root: Node) -> void:
	_walk(root, code())


static func _walk(n: Node, c: String) -> void:
	if n is TextureRect:
		var tr := n as TextureRect
		tr.texture = swap_tex(tr.texture, c)
	elif n is TextureButton:
		var b := n as TextureButton
		b.texture_normal = swap_tex(b.texture_normal, c)
		b.texture_hover = swap_tex(b.texture_hover, c)
		b.texture_pressed = swap_tex(b.texture_pressed, c)
		b.texture_disabled = swap_tex(b.texture_disabled, c)
	for ch in n.get_children():
		_walk(ch, c)
