"""对照实验：同一张 AI 原图在不同缩放算法 / 不同目标尺寸下的可读性。

用途：判断 32×48 这个规格能不能承载 AI 生成的图，还是需要提高像素基准。
输出：tmp_preview/scale_compare.png
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "assets" / "raw"
PREVIEW = ROOT / "tmp_preview"

# (标签, 目标宽高, 缩放算法)
VARIANTS = [
    ("32x48 NEAREST", (32, 48), Image.NEAREST),
    ("32x48 LANCZOS", (32, 48), Image.LANCZOS),
    ("48x72 LANCZOS", (48, 72), Image.LANCZOS),
    ("64x96 LANCZOS", (64, 96), Image.LANCZOS),
]

ZOOM = 6
PAD = 20
LABEL_H = 26


def crop_to_alpha(img: Image.Image) -> Image.Image:
    bbox = img.getchannel("A").getbbox()
    return img.crop(bbox) if bbox else img


def checker(size: tuple[int, int], cell: int = 8) -> Image.Image:
    canvas = Image.new("RGB", size, (58, 58, 64))
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2 == 0:
                canvas.paste((90, 90, 98), (x, y, x + cell, y + cell))
    return canvas


def main() -> None:
    PREVIEW.mkdir(exist_ok=True)
    for src_name in ["hero_wolf.png", "enemy_masked.png"]:
        src = crop_to_alpha(Image.open(RAW / src_name).convert("RGBA"))

        parts = []
        for label, size, resample in VARIANTS:
            scale = min(size[0] / src.width, size[1] / src.height)
            small = src.resize((max(1, round(src.width * scale)), max(1, round(src.height * scale))), resample)
            parts.append((label, small))

        cell_w = max(p.width for _, p in parts) * ZOOM
        cell_h = max(p.height for _, p in parts) * ZOOM
        width = (cell_w + PAD) * len(parts) + PAD
        height = cell_h + PAD * 2 + LABEL_H

        sheet = checker((width, height))
        draw = ImageDraw.Draw(sheet)
        x = PAD
        for label, small in parts:
            big = small.resize((small.width * ZOOM, small.height * ZOOM), Image.NEAREST)
            sheet.paste(big, (x + (cell_w - big.width) // 2, PAD + (cell_h - big.height) // 2), big)
            draw.text((x + 4, PAD + cell_h + 6), label, fill=(230, 230, 235))
            x += cell_w + PAD

        out = PREVIEW / f"scale_compare_{src_name.replace('.png', '')}.png"
        sheet.save(out)
        print(f"  {out.relative_to(ROOT)}  {sheet.size}")


if __name__ == "__main__":
    main()
