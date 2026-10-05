class_name RunRecord
extends RefCounted
## 最佳成绩的本地存档（最远距离 + 最多金币）。主场景与开始界面共用。

const RECORD_PATH: String = "user://record.cfg"
const SECTION: String = "run"
const SETTINGS: String = "settings"
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


# ------------------------------------------------------------- 设置（模式 / 皮肤）
static func load_setting(key: String, fallback: int = 0) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(RECORD_PATH) != OK:
		return fallback
	return int(cfg.get_value(SETTINGS, key, fallback))


static func save_setting(key: String, value: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(RECORD_PATH)
	cfg.set_value(SETTINGS, key, value)
	cfg.save(RECORD_PATH)


## 0 = 单人闯关，1 = 双人合作，2 = 机哥带你飞
static func load_mode() -> int:
	return clampi(load_setting("mode", 0), 0, 2)


static func save_mode(mode: int) -> void:
	save_setting("mode", clampi(mode, 0, 2))


## 机哥模式的难度：0 = 臭人机，1 = 普通人机，2 = 机哥
static func load_bot_level() -> int:
	return clampi(load_setting("bot_level", 1), 0, 2)


static func save_bot_level(lv: int) -> void:
	save_setting("bot_level", clampi(lv, 0, 2))


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
