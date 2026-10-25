"""把 ImageGen 生成的原始图处理成游戏可用规格。

用法：
    <venv>/Scripts/python.exe tools/process_art.py

输入：assets/raw/*.png（AI 生成，1024×1024 或 1536×1024）
输出：
    assets/characters/<id>/idle.png      64×96  角色待机精灵
    assets/characters/<id>/shadow.png    24×12  角色影子
    assets/tiles/ground.png              32×16  等距地面 tile（程序生成）
    assets/backgrounds/battle_plaza.png  640×360  战场背景

关于缩放：AI 出的是 1024px 级插画，缩到几十像素必须用 LANCZOS（面积平均）。
用 NEAREST 等于每隔 12 个像素抽 1 个，结果是噪点——这是本项目踩过的坑。
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "assets" / "raw"
PREVIEW = ROOT / "tmp_preview"

# 目标规格（见 docs/design/art_requirements.md 第一节）
SPRITE_SIZE = (64, 96)  # 32×48 实测撑不住 AI 图，见 tmp_preview/scale_compare_*.png
SHADOW_SIZE = (24, 12)
TILE_SIZE = (32, 16)
BG_SIZE = (640, 360)

ZOOM = 4


def crop_to_alpha(img: Image.Image, margin_ratio: float = 0.02) -> Image.Image:
    """按 alpha 通道裁掉四周透明区域，留一点边距。"""
    bbox = img.getchannel("A").getbbox()
    if bbox is None:
        return img
    left, top, right, bottom = bbox
    margin = int(max(right - left, bottom - top) * margin_ratio)
    return img.crop(
        (
            max(left - margin, 0),
            max(top - margin, 0),
            min(right + margin, img.width),
            min(bottom + margin, img.height),
        )
    )


def build_sprite(src: Path, out: Path, canvas_size: tuple[int, int], anchor_y: float) -> None:
    """裁透明边 → 等比缩放到画布内 → 落到固定画布（脚底对齐，便于站位）。"""
    img = crop_to_alpha(Image.open(src).convert("RGBA"))
    scale = min(canvas_size[0] / img.width, canvas_size[1] / img.height)
    img = img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)

    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    canvas.alpha_composite(img, ((canvas_size[0] - img.width) // 2, int((canvas_size[1] - img.height) * anchor_y)))
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    print(f"  {out.relative_to(ROOT)}  {canvas.size}")


def build_background(src: Path, out: Path) -> None:
    img = Image.open(src).convert("RGBA").resize(BG_SIZE, Image.LANCZOS)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(f"  {out.relative_to(ROOT)}  {img.size}")


def build_shadow(out: Path) -> None:
    """椭圆影子。等距下影子不可省，否则角色像浮空。"""
    img = Image.new("RGBA", SHADOW_SIZE, (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse((0, 0, SHADOW_SIZE[0] - 1, SHADOW_SIZE[1] - 1), fill=(0, 0, 0, 90))
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(f"  {out.relative_to(ROOT)}  {img.size}")


def _diamond(top: tuple[int, ...], edge: tuple[int, ...]) -> Image.Image:
    """程序生成 2:1 等距菱形。

    32×16 的菱形是纯几何图形，AI 画不准（实测出的是一团灰白块），所以这里直接算：
    每行的半宽 = (1 - |y - 中心| / 半高) * 半宽。
    """
    width, height = TILE_SIZE
    img = Image.new("RGBA", TILE_SIZE, (0, 0, 0, 0))
    pixels = img.load()
    half_w, half_h = width / 2.0, height / 2.0
    for y in range(height):
        ratio = 1.0 - abs(y + 0.5 - half_h) / half_h
        span = ratio * half_w
        x0, x1 = int(round(half_w - span)), int(round(half_w + span))
        for x in range(max(x0, 0), min(x1, width)):
            pixels[x, y] = edge if y >= half_h - 1 else top
    return img


def build_tile(out: Path) -> None:
    """不透明地面砖：箱庭地形用。"""
    img = _diamond((124, 124, 130, 255), (92, 92, 98, 255))
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(f"  {out.relative_to(ROOT)}  {img.size}")


def build_grid(out: Path) -> None:
    """半透明青色战术网格：战斗场地用。

    战斗场地不能铺不透明砖——会把背景广场盖成一张地垫。改成半透明青色菱形，
    正好和背景里已有的青色全息线接上，读起来是「系统投影出的作战网格」。
    """
    img = _diamond((150, 225, 245, 30), (160, 240, 255, 78))
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(f"  {out.relative_to(ROOT)}  {img.size}")


def checker(size: tuple[int, int], cell: int = 8) -> Image.Image:
    canvas = Image.new("RGB", size, (58, 58, 64))
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2 == 0:
                canvas.paste((90, 90, 98), (x, y, x + cell, y + cell))
    return canvas


def main() -> None:
    print("处理中：")
    build_sprite(RAW / "hero_wolf.png", ROOT / "assets/characters/hero_wolf/idle.png", SPRITE_SIZE, 0.72)
    build_sprite(RAW / "enemy_masked.png", ROOT / "assets/characters/enemy_masked/idle.png", SPRITE_SIZE, 0.72)
    build_background(RAW / "bg_plaza.png", ROOT / "assets/backgrounds/battle_plaza.png")
    build_tile(ROOT / "assets/tiles/ground.png")
    build_grid(ROOT / "assets/tiles/grid.png")
    build_shadow(ROOT / "assets/characters/shadow.png")

    parts = [
        Image.open(ROOT / "assets/characters/hero_wolf/idle.png").convert("RGBA"),
        Image.open(ROOT / "assets/characters/enemy_masked/idle.png").convert("RGBA"),
        Image.open(ROOT / "assets/tiles/ground.png").convert("RGBA"),
        Image.open(ROOT / "assets/tiles/grid.png").convert("RGBA"),
    ]
    pad = 16
    big = [p.resize((p.width * ZOOM, p.height * ZOOM), Image.NEAREST) for p in parts]
    sheet = checker((sum(b.width for b in big) + pad * (len(big) + 1), max(b.height for b in big) + pad * 2))
    x = pad
    for b in big:
        sheet.paste(b, (x, pad), b)
        x += b.width + pad
    PREVIEW.mkdir(exist_ok=True)
    sheet.save(PREVIEW / "assets_preview.png")
    print(f"  {PREVIEW.relative_to(ROOT)}/assets_preview.png  {sheet.size}")


if __name__ == "__main__":
    main()
