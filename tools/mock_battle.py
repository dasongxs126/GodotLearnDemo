"""合成一张等距战斗假想图，验证规格是否成立。

不是游戏里的实现，只是给「这套规格能不能用」一个视觉答案：
背景 + 地面 tile 网格 + 3v3 站位 + 影子 + 按 y 排序遮挡。

用法：
    <venv>/Scripts/python.exe tools/mock_battle.py
输出：
    tmp_preview/mock_battle.png（640×360，再放大 2× 便于查看）
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
PREVIEW = ROOT / "tmp_preview"

VIEW = (640, 360)  # 内部渲染分辨率
TILE = (32, 16)  # 等距格
ORIGIN = (320, 132)  # 网格原点（屏幕坐标）
ZOOM = 2

# 地面范围：以原点为中心铺一块菱形场地
GROUND_RADIUS = 7


def iso_to_screen(gx: float, gy: float) -> tuple[float, float]:
    """等距格坐标 → 屏幕坐标（2:1 菱形投影）。"""
    return (ORIGIN[0] + (gx - gy) * TILE[0] / 2, ORIGIN[1] + (gx + gy) * TILE[1] / 2)


def draw_ground(view: Image.Image, tile: Image.Image) -> None:
    """铺菱形场地。越靠前的格子越晚画，天然形成前后遮挡。"""
    cells = [(gx, gy) for gx in range(-GROUND_RADIUS, GROUND_RADIUS + 1) for gy in range(-GROUND_RADIUS, GROUND_RADIUS + 1)]
    cells = [c for c in cells if abs(c[0]) + abs(c[1]) <= GROUND_RADIUS]
    cells.sort(key=lambda c: c[0] + c[1])
    for gx, gy in cells:
        x, y = iso_to_screen(gx, gy)
        view.alpha_composite(tile, (round(x - TILE[0] / 2), round(y - TILE[1] / 2)))


def main() -> None:
    bg = Image.open(ASSETS / "backgrounds/battle_plaza.png").convert("RGBA")
    tile = Image.open(ASSETS / "tiles/grid.png").convert("RGBA")
    shadow = Image.open(ASSETS / "characters/shadow.png").convert("RGBA")
    hero = Image.open(ASSETS / "characters/hero_wolf/idle.png").convert("RGBA")
    enemy = Image.open(ASSETS / "characters/enemy_masked/idle.png").convert("RGBA")

    view = bg.copy()
    draw_ground(view, tile)

    # 3v3 站位：每排沿等距轴排列（gx+gy 相同 → 屏幕上同一水平线）。
    # 单位间隔 2 格（64px），因为 64px 宽的精灵隔 1 格会重叠 50%——精灵允许
    # 超出脚下那一格（站位只由脚底那个格点决定），但同排不能互相压住。
    ENEMY_ROW, PLAYER_ROW = -3, 3
    placements = [(enemy, ENEMY_ROW, i) for i in range(3)] + [(hero, PLAYER_ROW, i) for i in range(3)]
    # 先算屏幕坐标，再按 y 排序 → 远的先画，近的后画
    drawables = []
    for sprite, row, i in placements:
        gx = (i - 1) * 2
        gy = row - gx
        x, y = iso_to_screen(gx, gy)
        drawables.append((y, sprite, x, y))
    drawables.sort(key=lambda d: d[0])

    for _sort_y, sprite, x, y in drawables:
        view.alpha_composite(shadow, (round(x - shadow.width / 2), round(y - shadow.height / 2)))
        view.alpha_composite(sprite, (round(x - sprite.width / 2), round(y - sprite.height)))

    PREVIEW.mkdir(exist_ok=True)
    big = view.resize((VIEW[0] * ZOOM, VIEW[1] * ZOOM), Image.NEAREST)
    out = PREVIEW / "mock_battle.png"
    big.save(out)
    print(f"  {out.relative_to(ROOT)}  {big.size}")


if __name__ == "__main__":
    main()
