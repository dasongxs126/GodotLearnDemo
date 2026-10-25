## 参战单位。
##
## 一场战斗中的角色数据载体，只承载数据与轻量规则（资源点收支、生命值增减），
## 不负责决策、不负责阶段流程。
##
## @author WorkBuddy AI
## @date 2026-10-01
class_name BattleUnit
extends RefCounted

## 所属阵营。
enum Team {
	## 玩家方。
	PLAYER,
	## 敌方。
	ENEMY,
}

## 资源点开局值（规格书 §四）。
const RESOURCE_INITIAL := 3
## 资源点上限，溢出不再增长（规格书 §四）。
const RESOURCE_MAX := 5

## 显示名，仅用于日志与调试。
var display_name: String
## 所属阵营，取 [enum Team]。
var team: Team
## 站位编号，同队内为 1/2/3；掷骰同数字时用于排序（规格书 §三）。
var slot: int
## 当前生命值。
var hp: int
## 生命值上限。
var hp_max: int
## 当前资源点，角色私有，不与其他角色共用（规格书 §四）。
var resource: int

## 构造一个参战单位。
##
## @param p_display_name 显示名
## @param p_team 阵营，取 [enum Team]
## @param p_slot 站位编号，同队内建议从 1 开始递增
## @param p_hp_max 生命值上限，同时作为初始生命值
func _init(p_display_name: String, p_team: Team, p_slot: int, p_hp_max: int) -> void:
	display_name = p_display_name
	team = p_team
	slot = p_slot
	hp_max = p_hp_max
	hp = p_hp_max
	resource = RESOURCE_INITIAL

## 是否存活。
##
## @return 生命值大于 0 时为 [code]true[/code]
func is_alive() -> bool:
	return hp > 0

## 增加资源点。
##
## 超过上限的部分直接丢弃，不会溢出保留（规格书 §四）。
##
## @param amount 增加量，非正值不产生效果
func gain_resource(amount: int) -> void:
	if amount <= 0:
		return
	resource = mini(resource + amount, RESOURCE_MAX)

## 扣除资源点。
##
## 资源不足时不产生任何改动（规格书 §四：不足不能触发）。
##
## @param amount 扣除量
## @return 资源充足并完成扣除时为 [code]true[/code]，否则返回 [code]false[/code]
func spend_resource(amount: int) -> bool:
	if amount < 0 or resource < amount:
		return false
	resource -= amount
	return true

## 受到伤害。
##
## @param amount 伤害值，非正值不产生效果
func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	hp = maxi(hp - amount, 0)

## 恢复生命值。
##
## @param amount 恢复量，非正值不产生效果
func heal(amount: int) -> void:
	if amount <= 0:
		return
	hp = mini(hp + amount, hp_max)

## 判断是否与另一个单位同阵营。
##
## @param other 另一个单位
## @return 同阵营时为 [code]true[/code]
func is_ally_of(other: BattleUnit) -> bool:
	return other != null and team == other.team
