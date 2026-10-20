"""Draw the easynote logo and export every icon the app needs.

The logo: a white index card with a crimson title rule, a ticked checkbox and
ruled lines, tilted over a second card, on a navy tile. SVG masters are
written to assets/icon/, PNGs are rendered with Inkscape.

    python3 tool/make_icons.py
"""
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "assets/icon"
RES = ROOT / "android/app/src/main/res"

NAVY, CARD, CRIMSON, RULE, BACK = "#1F2A44", "#FFFFFF", "#C8344F", "#B9CBE6", "#8FA9D1"


def cards(ink: str = NAVY, card: str = CARD, back: str = BACK, rule: str = RULE,
          accent: str = CRIMSON) -> str:
    """The two cards, drawn in a 1024 box centred on (512, 512)."""
    return f"""
  <rect x="250" y="236" width="560" height="420" rx="34" fill="{back}"
        transform="rotate(9 512 512)"/>
  <g transform="rotate(-5 512 512)">
    <rect x="200" y="300" width="624" height="452" rx="36" fill="{card}"/>
    <rect x="262" y="350" width="250" height="46" rx="23" fill="{ink}"/>
    <rect x="200" y="430" width="624" height="18" fill="{accent}"/>
    <rect x="268" y="498" width="62" height="62" rx="12" fill="none"
          stroke="{ink}" stroke-width="14"/>
    <path d="M281 529 l16 17 l30 -37" fill="none" stroke="{ink}"
          stroke-width="15" stroke-linecap="round" stroke-linejoin="round"/>
    <rect x="364" y="520" width="390" height="18" rx="9" fill="{rule}"/>
    <circle cx="299" cy="633" r="15" fill="{ink}"/>
    <rect x="364" y="624" width="310" height="18" rx="9" fill="{rule}"/>
  </g>"""


def mono_cards() -> str:
    """Single-colour version for Android themed icons: the card details are
    cut out of the front card, and the back card is half transparent."""
    return """
  <defs><mask id="cut" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
    <g transform="rotate(-5 512 512)">
      <rect x="200" y="300" width="624" height="452" rx="36" fill="#fff"/>
      <rect x="262" y="350" width="250" height="46" rx="23" fill="#000"/>
      <rect x="200" y="430" width="624" height="18" fill="#000"/>
      <rect x="268" y="498" width="62" height="62" rx="12" fill="none"
            stroke="#000" stroke-width="14"/>
      <path d="M281 529 l16 17 l30 -37" fill="none" stroke="#000"
            stroke-width="15" stroke-linecap="round" stroke-linejoin="round"/>
      <rect x="364" y="520" width="390" height="18" rx="9" fill="#000"/>
      <circle cx="299" cy="633" r="15" fill="#000"/>
      <rect x="364" y="624" width="310" height="18" rx="9" fill="#000"/>
    </g>
  </mask></defs>
  <rect x="250" y="236" width="560" height="420" rx="34" fill="#000" fill-opacity="0.45"
        transform="rotate(9 512 512)"/>
  <rect width="1024" height="1024" fill="#000" mask="url(#cut)"/>"""


def svg(body: str, background: bool) -> str:
    tile = f'<rect width="1024" height="1024" rx="230" fill="{NAVY}"/>' if background else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" '
            f'width="1024" height="1024">{tile}{body}\n</svg>\n')


def scaled(body: str, scale: float) -> str:
    """Shrink the drawing about the centre (adaptive icons crop to a safe zone)."""
    return f'<g transform="translate(512 512) scale({scale}) translate(-512 -512)">{body}</g>'


def export(src: Path, out: Path, px: int) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["inkscape", str(src), "--export-type=png",
                    f"--export-filename={out}", "-w", str(px), "-h", str(px)],
                   check=True, capture_output=True)


def main() -> None:
    if shutil.which("inkscape") is None:
        raise SystemExit("inkscape is needed to render the PNGs")
    ICON.mkdir(parents=True, exist_ok=True)
    full = ICON / "easynote.svg"
    full.write_text(svg(scaled(cards(), 1.0), background=True))
    # Adaptive-icon layers: the launcher keeps the central 72 of 108 dp and
    # may mask it to a circle, so the cards shrink to stay inside.
    fg = ICON / "easynote-foreground.svg"
    fg.write_text(svg(scaled(cards(), 0.74), background=False))
    mono = ICON / "easynote-monochrome.svg"
    mono.write_text(svg(scaled(mono_cards(), 0.74), background=False))

    export(full, ICON / "easynote.png", 512)
    for name, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        export(full, RES / f"mipmap-{name}/ic_launcher.png", px)
        layer = round(px * 108 / 48)
        export(fg, RES / f"mipmap-{name}/ic_launcher_foreground.png", layer)
        export(mono, RES / f"mipmap-{name}/ic_launcher_monochrome.png", layer)

    (RES / "mipmap-anydpi-v26").mkdir(exist_ok=True)
    (RES / "mipmap-anydpi-v26/ic_launcher.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
""")
    (RES / "values/colors.xml").write_text(f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">{NAVY}</color>
</resources>
""")


if __name__ == "__main__":
    main()
