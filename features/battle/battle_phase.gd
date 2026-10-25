## 战斗阶段定义。
##
## 阶段分两组（规格书 §八）：
## 1. 回合管线阶段（编号 1~11）：按固定顺序进入，由 [BattleController] 驱动；
## 2. 任意时刻窗口（编号 12~15）：不纳入管线，由具体事件触发。
##
## @author WorkBuddy AI
## @date 2026-10-01
class_name BattlePhase
extends RefCounted

## 阶段编号。
enum Id {
	## 投掷骰子前，同时是"回合开始"。
	ROLL_BEFORE = 1,
	## 投掷骰子后。
	ROLL_AFTER = 2,
	## 某个角色行动开始前。
	ACTION_BEFORE = 3,
	## 进攻链：进攻前。
	ATTACK_BEFORE = 4,
	## 进攻链：弹刀判定前，以结算弹刀结果为分界。
	CLASH_CHECK_BEFORE = 5,
	## 进攻链：弹刀判定后。
	CLASH_CHECK_AFTER = 6,
	## 进攻链：进攻后。
	ATTACK_AFTER = 7,
	## 防御链：防御前。
	DEFEND_BEFORE = 8,
	## 防御链：防御后。
	DEFEND_AFTER = 9,
	## 某个角色行动结束。
	ACTION_AFTER = 10,
	## 回合结束，即行动队列走完，也称一轮结束。
	ROUND_AFTER = 11,
	## 任意时刻窗口：某个技能生效前，每个技能各一个窗口。
	SKILL_BEFORE = 12,
	## 任意时刻窗口：某个技能生效后，每个技能各一个窗口。
	SKILL_AFTER = 13,
	## 任意时刻窗口：资源点变动。
	RESOURCE_CHANGED = 14,
	## 任意时刻窗口：行动序列变动。
	QUEUE_CHANGED = 15,
}

## 回合管线阶段的进入顺序。
const PIPELINE_ORDER := [
	Id.ROLL_BEFORE,
	Id.ROLL_AFTER,
	Id.ACTION_BEFORE,
	Id.ATTACK_BEFORE,
	Id.CLASH_CHECK_BEFORE,
	Id.CLASH_CHECK_AFTER,
	Id.ATTACK_AFTER,
	Id.DEFEND_BEFORE,
	Id.DEFEND_AFTER,
	Id.ACTION_AFTER,
	Id.ROUND_AFTER,
]

## 任意时刻窗口编号，不纳入回合管线。
const WINDOW_IDS := [
	Id.SKILL_BEFORE,
	Id.SKILL_AFTER,
	Id.RESOURCE_CHANGED,
	Id.QUEUE_CHANGED,
]

## 阶段编号到中文名的映射，用于日志与调试。
const NAMES := {
	Id.ROLL_BEFORE: "掷骰前（回合开始）",
	Id.ROLL_AFTER: "掷骰后",
	Id.ACTION_BEFORE: "行动开始前",
	Id.ATTACK_BEFORE: "进攻前",
	Id.CLASH_CHECK_BEFORE: "弹刀判定前",
	Id.CLASH_CHECK_AFTER: "弹刀判定后",
	Id.ATTACK_AFTER: "进攻后",
	Id.DEFEND_BEFORE: "防御前",
	Id.DEFEND_AFTER: "防御后",
	Id.ACTION_AFTER: "行动结束",
	Id.ROUND_AFTER: "回合结束",
	Id.SKILL_BEFORE: "技能生效前",
	Id.SKILL_AFTER: "技能生效后",
	Id.RESOURCE_CHANGED: "资源点变动",
	Id.QUEUE_CHANGED: "行动序列变动",
}

## 阶段总数。规格书 §八 暂定 15 个。
const COUNT := 15

## 判断是否为回合管线阶段。
##
## @param phase 阶段编号
## @return 属于管线阶段时为 [code]true[/code]
static func is_pipeline(phase: int) -> bool:
	return PIPELINE_ORDER.has(phase)

## 判断该阶段是否开启连携窗口。
##
## 规格书 §八 暂定"15 个阶段全部是连携阶段"（⏳），确认后如需区分只改这里。
##
## @param phase 阶段编号
## @return 暂定对全部合法阶段返回 [code]true[/code]
static func is_chain_window(phase: int) -> bool:
	return NAMES.has(phase)

## 取阶段中文名。
##
## @param phase 阶段编号
## @return 中文名；未知编号返回 [code]"未知阶段"[/code]
static func name_of(phase: int) -> String:
	return NAMES.get(phase, "未知阶段")
