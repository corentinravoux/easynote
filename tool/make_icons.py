"""Draw the easynote icon (an index card on navy) and write every size the
Android launcher and the Linux desktop entry need.

    python3 tool/make_icons.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
NAVY, CARD, CRIMSON, RULE = "#1F2A44", "#FFFFFF", "#C8344F", "#B9CBE6"


def draw(size: int, background: bool = True) -> Image.Image:
    s = 1024
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if background:
        d.rounded_rectangle([0, 0, s, s], radius=220, fill=NAVY)
    x0, y0, x1, y1 = 200, 250, 824, 774
    d.rounded_rectangle([x0, y0, x1, y1], radius=28, fill=CARD)
    d.rectangle([x0, 372, x1, 388], fill=CRIMSON)
    for y in (470, 560, 650):
        d.rectangle([x0 + 60, y, x1 - 60, y + 10], fill=RULE)
    d.rounded_rectangle([x0 + 60, 290, x0 + 380, 330], radius=20, fill=NAVY)
    return im.resize((size, size), Image.LANCZOS)


def main() -> None:
    draw(512).save(ROOT / "assets/icon/easynote.png")
    for name, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        out = ROOT / f"android/app/src/main/res/mipmap-{name}/ic_launcher.png"
        draw(px).save(out)


if __name__ == "__main__":
    main()
