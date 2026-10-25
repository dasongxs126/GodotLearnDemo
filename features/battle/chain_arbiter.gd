## 连携仲裁器。
##
## 负责在阶段进入时判断"场上是否存在可触发技能的可能"，从而决定是否开启子弹时间（规格书 §七）。
##
## 骨架阶段只提供接口与配置，不接入任何技能：未注册触发候选时恒不开启窗口。
## 后续接入技能系统时，把技能的"触发阶段"通过 [method register_triggers] 注册进来即可。
##
## @author WorkBuddy AI
## @date 2026-10-01
class_name ChainArbiter
extends RefCounted

## 连携响应模式，全局设置（规格书 §七）。
enum Mode {
	## 手动：开启子弹时间，等待玩家在限时内响应，超时视为不触发。
	MANUAL,
	## 自动：按技能优先级编号自动执行。
	AUTO,
}

## 子弹时间时长，单位秒。
##
## 规格书 §七：可配但配成固定值（⏳）。子弹时间是慢放演出，用于给玩家反应时间。
var bullet_time_seconds: float = 2.0

## 当前响应模式。
var mode: Mode = Mode.MANUAL

## 阶段编号到可触发技能 ID 列表的映射。
var _triggers: Dictionary = {}

## 注册某个阶段的连携触发候选。
##
## 同一阶段重复注册会覆盖上一次的结果。
##
## @param phase 阶段编号，取 [enum BattlePhase.Id]
## @param skill_ids 该阶段可触发的技能 ID 列表；传空数组等价于注销该阶段
func register_triggers(phase: int, skill_ids: Array) -> void:
	if skill_ids.is_empty():
		_triggers.erase(phase)
		return
	_triggers[phase] = skill_ids.duplicate()

## 清空全部触发候选。
func clear() -> void:
	_triggers.clear()

## 判断某阶段是否存在可触发技能。
##
## 这是"是否开启子弹时间"的唯一判据：只要存在触发可能就开启（规格书 §七）。
##
## @param phase 阶段编号
## @return 存在候选时为 [code]true[/code]
func has_trigger(phase: int) -> bool:
	return not _triggers.get(phase, []).is_empty()

## 取某阶段需要响应的技能 ID。
##
## 玩家只能看到"某技能可触发"，看不到具体效果与代价（规格书 §七）。
##
## @param phase 阶段编号
## @return 技能 ID 列表副本；无候选时为空数组
func candidates(phase: int) -> Array:
	return _triggers.get(phase, []).duplicate()

## 判断某次连携是否因为超时而不触发。
##
## @param elapsed_seconds 玩家响应耗时
## @return 超过子弹时间时为 [code]true[/code]
func is_timed_out(elapsed_seconds: float) -> bool:
	return elapsed_seconds > bullet_time_seconds
