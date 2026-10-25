## 等距（斜 45°）坐标换算。
##
## 战斗与箱庭**共用同一套投影**（见 [code]docs/design/art_requirements.md[/code] 第一节），
## 所以坐标换算抽出来单独放，避免两边各写一份、各错一处。
##
## 只做数学、不碰场景树：不需要 [Node2D]、不需要引擎运行，逻辑层与测试可以直接调用。
##
## 投影公式（2:1 菱形）：
## [codeblock]
## screen.x = origin.x + (gx - gy) * tile.x / 2
## screen.y = origin.y + (gx + gy) * tile.y / 2
## [/codeblock]
##
## 由公式可得两条常用性质：
## - [code]gx + gy[/code] 相同的格子，屏幕 y 相同——即**屏幕上的一条水平线**，
##   同时也是绘制与遮挡的排序键（值大的离镜头近，后画）；
## - 沿 [code]gx[/code] 每走 1 格，屏幕 x 变化 [code]tile.x / 2[/code]（本工程为 16px）。
##
## @author WorkBuddy AI
## @date 2026-10-01
class_name IsoGrid
extends RefCounted

## 默认等距格尺寸（菱形外接矩形），与 [code]assets/tiles/*.png[/code] 一致。
const TILE_SIZE := Vector2(32, 16)

## 网格原点在屏幕上的位置：格坐标 (0, 0) 的投影点。
var origin: Vector2

## 单格尺寸（菱形的外接矩形）。
var tile_size: Vector2


## 构造一个等距网格。
##
## @param p_origin 格坐标 (0, 0) 的屏幕位置
## @param p_tile_size 单格尺寸，默认 [constant TILE_SIZE]
func _init(p_origin: Vector2 = Vector2.ZERO, p_tile_size: Vector2 = TILE_SIZE) -> void:
	origin = p_origin
	tile_size = p_tile_size


## 格坐标 → 屏幕坐标。
##
## @param gx 格坐标 x（可为小数，便于插值）
## @param gy 格坐标 y
## @return 屏幕坐标
func to_screen(gx: float, gy: float) -> Vector2:
	return origin + Vector2((gx - gy) * tile_size.x * 0.5, (gx + gy) * tile_size.y * 0.5)


## 屏幕坐标 → 格坐标，[method to_screen] 的逆运算。
##
## 鼠标拾取（点击选人、点地面选格子）用它。
##
## @param screen 屏幕坐标
## @return 格坐标，x/y 均为小数，需要整数格时自行取整
func to_grid(screen: Vector2) -> Vector2:
	var dx := (screen.x - origin.x) / (tile_size.x * 0.5)
	var dy := (screen.y - origin.y) / (tile_size.y * 0.5)
	return Vector2((dy + dx) * 0.5, (dy - dx) * 0.5)


## 深度键：等距下按此值**升序**绘制即可得到正确的前后遮挡。
##
## 等价于 [code]gx + gy[/code]，也是 [method to_screen] 得到的屏幕 y 的单调映射。
##
## @param gx 格坐标 x
## @param gy 格坐标 y
## @return 深度键
func depth(gx: float, gy: float) -> float:
	return gx + gy


## 菱形的四个顶点，以格点为中心，可直接喂给 [Polygon2D.polygon]。
##
## @param size 菱形外接矩形，默认 [member tile_size]
## @return 依次为上、右、下、左四个顶点
func diamond_points(size: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var extent := tile_size if size == Vector2.ZERO else size
	var half_w := extent.x * 0.5
	var half_h := extent.y * 0.5
	return PackedVector2Array([
		Vector2(0.0, -half_h),
		Vector2(half_w, 0.0),
		Vector2(0.0, half_h),
		Vector2(-half_w, 0.0),
	])


## 铺一片菱形场地所需的格子，按深度升序排好。
##
## [param radius] 为菱形半径：只保留 [code]|gx| + |gy| <= radius[/code] 的格子，
## 得到的是一个菱形（而非正方形）场地，边缘与等距视角同向。
##
## @param radius 菱形半径，至少为 0
## @return 格坐标数组，已按 [method depth] 升序排列
func diamond_cells(radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for gx in range(-radius, radius + 1):
		for gy in range(-radius, radius + 1):
			if absi(gx) + absi(gy) <= radius:
				cells.append(Vector2i(gx, gy))
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x + a.y < b.x + b.y)
	return cells
