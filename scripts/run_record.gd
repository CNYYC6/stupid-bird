class_name RunRecord
extends RefCounted
## 最佳成绩的本地存档（最远距离 + 最多金币）。主场景与开始界面共用。

const RECORD_PATH: String = "user://record.cfg"
const SECTION: String = "run"
const KEY_METERS: String = "best_meters"
const KEY_COINS: String = "best_coins"


static func load_best() -> int:
	return _read(KEY_METERS)


static func load_best_coins() -> int:
	return _read(KEY_COINS)


## 只有真的破纪录才写盘
static func save_best(meters: int, coins: int) -> void:
	var changed: bool = false
	if meters > _read(KEY_METERS):
		_write(KEY_METERS, meters)
		changed = true
	if coins > _read(KEY_COINS):
		_write(KEY_COINS, coins)
		changed = true
	return


static func _read(key: String) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(RECORD_PATH) != OK:
		return 0
	return maxi(int(cfg.get_value(SECTION, key, 0)), 0)


static func _write(key: String, value: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(RECORD_PATH)		# 保留另一个字段
	cfg.set_value(SECTION, key, value)
	cfg.save(RECORD_PATH)
