## 行动队列。
##
## 由掷骰结果排序的单位序列，配一个始终指向"当前操作人"的单指针（规格书 §三）。
##
## 排序优先级：骰子数字大 → 小；数字相同则先手方 → 后手方；同队且数字相同则站位编号小 → 大。
## 敌我同列，顺序对玩家可见。
##
## 指针语义：指针跟随当前操作人。操作人的位置被技能改变后指针随之移动，
## 其行动结束后从该位置向后推进；位于指针之前的角色本轮不再行动，且没有补偿。
##
## @author WorkBuddy AI
## @date 2026-10-01
class_name ActionQueue
extends RefCounted

## 队列顺序，元素为 [BattleUnit]。
var _units: Array[BattleUnit] = []
## 本轮各单位点数，键为 [BattleUnit]，值为 int。
var _rolls: Dictionary = {}
## 当前操作人的下标。
var _pointer: int = 0

## 用掷骰结果构建队列，并把指针重置到队首。
##
## @param units 本轮参战单位，通常只包含存活单位
## @param rolls 单位到点数的映射
## @param first_team 本局先手方，取 [enum BattleUnit.Team]
func setup(units: Array[BattleUnit], rolls: Dictionary, first_team: int) -> void:
	_rolls = rolls.duplicate()
	_units = units.duplicate()
	_units.sort_custom(_compare.bind(first_team))
	_pointer = 0

## 取当前操作人。
##
## @return 指针指向的单位；队列已走完时为 [code]null[/code]
func current() -> BattleUnit:
	if _pointer < 0 or _pointer >= _units.size():
		return null
	return _units[_pointer]

## 当前指针下标。
##
## @return 指针下标；队列为空时为 0
func pointer_index() -> int:
	return _pointer

## 队列是否已走完。
##
## @return 指针越过队尾时为 [code]true[/code]
func is_exhausted() -> bool:
	return _pointer >= _units.size()

## 队列长度。
##
## @return 队列中的单位数量
func size() -> int:
	return _units.size()

## 指针向后推进一位。
##
## @return 推进后仍有可行动单位时为 [code]true[/code]
func advance() -> bool:
	_pointer += 1
	return not is_exhausted()

## 取队列顺序快照。
##
## @return 按当前顺序排列的单位数组副本
func units() -> Array[BattleUnit]:
	return _units.duplicate()

## 取某单位本轮点数。
##
## @param unit 目标单位
## @return 本轮点数；不在队列中时返回 0
func roll_of(unit: BattleUnit) -> int:
	return _rolls.get(unit, 0)

## 交换两个单位的队列位置，指针跟随当前操作人移动。
##
## @param a 单位 A
## @param b 单位 B
## @return 两个单位都在队列中且不是同一个时为 [code]true[/code]
func swap(a: BattleUnit, b: BattleUnit) -> bool:
	var index_a := _units.find(a)
	var index_b := _units.find(b)
	if index_a < 0 or index_b < 0 or index_a == index_b:
		return false
	var actor := current()
	var temp := _units[index_a]
	_units[index_a] = _units[index_b]
	_units[index_b] = temp
	_resync_pointer(actor)
	return true

## 把单位移动到指定下标，指针跟随当前操作人移动。
##
## @param unit 被移动的单位
## @param to_index 目标下标，越界时收敛到合法范围
## @return 单位在队列中时为 [code]true[/code]
func move(unit: BattleUnit, to_index: int) -> bool:
	var from_index := _units.find(unit)
	if from_index < 0:
		return false
	var actor := current()
	_units.remove_at(from_index)
	_units.insert(clampi(to_index, 0, _units.size()), unit)
	_resync_pointer(actor)
	return true

## 从队列中移除单位，指针跟随当前操作人移动。
##
## @param unit 被移除的单位
## @return 移除成功时为 [code]true[/code]
func remove(unit: BattleUnit) -> bool:
	var index := _units.find(unit)
	if index < 0:
		return false
	var actor := current()
	_units.remove_at(index)
	_resync_pointer(actor)
	return true

## 排序比较函数，供 [method Array.sort_custom] 使用。
##
## @param a 单位 A
## @param b 单位 B
## @param first_team 本局先手方
## @return A 排在 B 之前时为 [code]true[/code]
func _compare(a: BattleUnit, b: BattleUnit, first_team: int) -> bool:
	var roll_a: int = _rolls.get(a, 0)
	var roll_b: int = _rolls.get(b, 0)
	if roll_a != roll_b:
		return roll_a > roll_b
	var a_is_first := a.team == first_team
	var b_is_first := b.team == first_team
	if a_is_first != b_is_first:
		return a_is_first
	if a.team == b.team:
		return a.slot < b.slot
	return false

## 把指针重新对齐到当前操作人的新位置。
##
## @param actor 换位前的当前操作人；为 [code]null[/code] 时保持指针不变
func _resync_pointer(actor: BattleUnit) -> void:
	if actor == null:
		return
	var index := _units.find(actor)
	if index >= 0:
		_pointer = index
