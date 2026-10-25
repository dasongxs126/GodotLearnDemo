## 行动顺序骰子。
##
## 默认骰子的面数等于场上存活人数，最少 6 面，每面数字为 1 至面数（规格书 §三）。
## 特殊战斗可以使用固定点数的骰子，例如某 BOSS 使用 4 面骰且每面都是数字 9。
##
## @author WorkBuddy AI
## @date 2026-10-01
class_name BattleDice
extends RefCounted

## 默认骰子的最少面数。
const MIN_SIDES := 6

## 骰子面数，固定点数骰子仅用于展示。
var _sides: int
## 固定点数；大于 0 时忽略随机，每次掷出都返回该值。
var _fixed_value: int
## 随机源。
var _rng: RandomNumberGenerator

## 构造骰子。
##
## 业务代码优先使用 [method create_for_battle] 与 [method create_fixed]。
##
## @param p_sides 面数，小于 1 时收敛为 1
## @param p_fixed_value 固定点数，0 表示按面数随机
## @param p_rng 随机源；为 [code]null[/code] 时新建一个
func _init(p_sides: int, p_fixed_value: int = 0, p_rng: RandomNumberGenerator = null) -> void:
	_sides = maxi(p_sides, 1)
	_fixed_value = maxi(p_fixed_value, 0)
	_rng = p_rng if p_rng != null else RandomNumberGenerator.new()

## 按场上人数创建默认骰子。
##
## @param unit_count 场上存活单位总数
## @param p_rng 随机源；为 [code]null[/code] 时新建一个
## @return 面数为 [code]max(unit_count, MIN_SIDES)[/code] 的骰子
static func create_for_battle(unit_count: int, p_rng: RandomNumberGenerator = null) -> BattleDice:
	return BattleDice.new(maxi(unit_count, MIN_SIDES), 0, p_rng)

## 创建固定点数的骰子。
##
## @param p_sides 面数，仅用于展示
## @param p_value 每次掷出的固定值
## @param p_rng 随机源，保留参数以便后续扩展
## @return 每次掷出都返回 [code]p_value[/code] 的骰子
static func create_fixed(p_sides: int, p_value: int, p_rng: RandomNumberGenerator = null) -> BattleDice:
	return BattleDice.new(p_sides, p_value, p_rng)

## 掷一次骰子。
##
## @return 本次点数；固定点数骰子恒返回其固定值
func roll() -> int:
	if _fixed_value > 0:
		return _fixed_value
	return _rng.randi_range(1, _sides)

## 骰子面数。
##
## @return 面数
func sides() -> int:
	return _sides

## 是否为固定点数骰子。
##
## @return 固定点数大于 0 时为 [code]true[/code]
func is_fixed() -> bool:
	return _fixed_value > 0
