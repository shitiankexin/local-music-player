#!/usr/bin/env python3
"""Generate 洪达快播 App Icon / Logo / App Store artwork (iOS 18+)."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "HongdaPlayer" / "Assets.xcassets"
APPICON = ASSETS / "AppIcon.appiconset"
LOGO_SET = ASSETS / "Logo.imageset"
ACCENT = ASSETS / "AccentColor.colorset"
STORE = ROOT / "store" / "artwork"

# Brand — midnight navy + electric teal (local music / fast play)
BG = (0x0A, 0x16, 0x28, 255)
BG_DARK = (0x05, 0x0B, 0x14, 255)
TEAL = (0x1E, 0xC8, 0xB0, 255)
TEAL_SOFT = (0x5B, 0xE0, 0xCC, 255)
GLOW = (0x1E, 0xC8, 0xB0, 70)
WHITE = (255, 255, 255, 255)
INK = (0xE8, 0xF4, 0xF8, 255)
MUTED = (0x9A, 0xB4, 0xC0, 255)


def _font(size: int, *, bold: bool = True) -> ImageFont.ImageFont:
    paths = (
        "/System/Library/Fonts/STHeiti Medium.ttc" if bold else "/System/Library/Fonts/STHeiti Light.ttc",
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/System/Library/Fonts/Supplemental/Songti.ttc",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
    )
    for path in paths:
        try:
            return ImageFont.truetype(path, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def _lerp(a: tuple[int, ...], b: tuple[int, ...], t: float) -> tuple[int, ...]:
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(a, b))


def _fill_vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        t = y / max(1, size - 1)
        c = _lerp(top, bottom, t)
        for x in range(size):
            px[x, y] = c  # type: ignore[index]
    return img.convert("RGBA")


def draw_mark(
    size: int,
    *,
    bg: tuple[int, int, int, int] | None = BG,
    teal: tuple[int, int, int, int] = TEAL,
    play: tuple[int, int, int, int] = WHITE,
    with_glow: bool = True,
) -> Image.Image:
    """Play triangle in a teal ring + radiating sound arcs."""
    if bg is None:
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    else:
        img = _fill_vertical_gradient(size, bg[:3], _lerp(bg[:3], (0, 0, 0), 0.18)[:3])

    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    cx = cy = size / 2

    # Bias mark slightly left so arcs have room on the right (safe margin ~12%).
    mark_cx = size * 0.46
    mark_cy = size * 0.50
    outer_r = size * 0.28
    stroke = max(2.0, size * 0.048)

    if with_glow and bg is not None:
        glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        gdraw = ImageDraw.Draw(glow)
        gr = outer_r * 1.35
        gdraw.ellipse(
            (mark_cx - gr, mark_cy - gr, mark_cx + gr, mark_cy + gr),
            fill=GLOW,
        )
        glow = glow.filter(ImageFilter.GaussianBlur(radius=max(1, size * 0.045)))
        layer = Image.alpha_composite(layer, glow)
        draw = ImageDraw.Draw(layer)

    # Outer ring
    bbox = (mark_cx - outer_r, mark_cy - outer_r, mark_cx + outer_r, mark_cy + outer_r)
    draw.ellipse(bbox, outline=teal, width=int(round(stroke)))

    # Soft inner fill
    inner_r = outer_r - stroke * 1.55
    draw.ellipse(
        (mark_cx - inner_r, mark_cy - inner_r, mark_cx + inner_r, mark_cy + inner_r),
        fill=(255, 255, 255, 18) if bg is not None else (255, 255, 255, 0),
    )

    # Play triangle (optically centered: nudge left of geometric center)
    tri_r = outer_r * 0.42
    # Equilateral-ish play pointing right
    tip_x = mark_cx + tri_r * 0.72
    back_x = mark_cx - tri_r * 0.48
    half_h = tri_r * 0.78
    triangle = [
        (tip_x, mark_cy),
        (back_x, mark_cy - half_h),
        (back_x, mark_cy + half_h),
    ]
    draw.polygon(triangle, fill=play)

    # Sound arcs (3) to the right of the ring
    arc_stroke = max(2, int(round(size * 0.028)))
    for i, scale in enumerate((1.18, 1.42, 1.66)):
        r = outer_r * scale
        alpha = 255 - i * 45
        color = (*teal[:3], max(120, alpha))
        # Pillow arcs: degrees, 0=east, counterclockwise... use chord-free arc
        box = (mark_cx - r, mark_cy - r, mark_cx + r, mark_cy + r)
        # Draw only right-side arc (~ -55° to +55°)
        draw.arc(box, start=-52, end=52, fill=color, width=arc_stroke)

    img = Image.alpha_composite(img, layer) if bg is not None else layer
    return img


def draw_tinted_template(size: int) -> Image.Image:
    """Grayscale / alpha template for iOS 18 tinted icons."""
    mark = draw_mark(size, bg=None, teal=(0, 0, 0, 255), play=(0, 0, 0, 255), with_glow=False)
    # Ensure pure black RGB with alpha silhouette
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = mark.load()
    opx = out.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            if a > 16:
                opx[x, y] = (0, 0, 0, a)
    return out


def draw_wordmark(
    width: int = 1024,
    height: int = 320,
    *,
    solid_bg: bool = False,
) -> Image.Image:
    """Horizontal logo: mark + 洪达快播."""
    img = Image.new(
        "RGBA",
        (width, height),
        BG if solid_bg else (0, 0, 0, 0),
    )
    mark_size = int(height * 0.78)
    mark = draw_mark(mark_size, bg=None, with_glow=False)
    disc = Image.new("RGBA", (mark_size, mark_size), (0, 0, 0, 0))
    ddraw = ImageDraw.Draw(disc)
    pad = mark_size * 0.02
    ddraw.rounded_rectangle(
        (pad, pad, mark_size - pad, mark_size - pad),
        radius=mark_size * 0.22,
        fill=BG if not solid_bg else _lerp(BG[:3], (0, 0, 0), 0.25) + (255,),
    )
    disc = Image.alpha_composite(disc, mark)
    my = (height - mark_size) // 2
    mx = int(height * 0.12)
    img.paste(disc, (mx, my), disc)

    draw = ImageDraw.Draw(img)
    text = "洪达快播"
    font = _font(int(height * 0.38), bold=True)
    tx = mx + mark_size + int(height * 0.12)
    tb = draw.textbbox((0, 0), text, font=font)
    th = tb[3] - tb[1]
    ty = height * 0.28 - tb[1]
    draw.text((tx, ty), text, font=font, fill=WHITE)

    sub = "本地无损播放"
    sfont = _font(int(height * 0.15), bold=False)
    draw.text((tx, ty + th + height * 0.05), sub, font=sfont, fill=MUTED)
    return img


def save_rgb_no_alpha(img: Image.Image, path: Path, *, fallback_bg: tuple[int, int, int] = BG[:3]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if img.mode == "RGBA":
        bg = Image.new("RGB", img.size, fallback_bg)
        bg.paste(img, mask=img.split()[3])
        bg.save(path, format="PNG", optimize=True)
    else:
        img.convert("RGB").save(path, format="PNG", optimize=True)


def save_rgba(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, format="PNG", optimize=True)


def write_appicon_contents() -> None:
    APPICON.mkdir(parents=True, exist_ok=True)
    (APPICON / "Contents.json").write_text(
        """{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "AppIcon-Dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "AppIcon-Tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
""",
        encoding="utf-8",
    )


def write_logo_contents() -> None:
    LOGO_SET.mkdir(parents=True, exist_ok=True)
    (LOGO_SET / "Contents.json").write_text(
        """{
  "images" : [
    { "filename" : "logo.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "logo.png", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "logo.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
""",
        encoding="utf-8",
    )


def write_accent() -> None:
    ACCENT.mkdir(parents=True, exist_ok=True)
    (ACCENT / "Contents.json").write_text(
        """{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.690",
          "green" : "0.784",
          "red" : "0.118"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
""",
        encoding="utf-8",
    )


def write_store_readme() -> None:
    STORE.mkdir(parents=True, exist_ok=True)
    (STORE / "README.md").write_text(
        """# 洪达快播 — 图标与上架素材

由 `scripts/generate_icons.py` 生成。重新导出：

```bash
python3 scripts/generate_icons.py
```

## 工程内

| 文件 | 用途 |
|------|------|
| `HongdaPlayer/Assets.xcassets/AppIcon.appiconset/AppIcon.png` | 默认外观 1024×1024（无透明） |
| `AppIcon-Dark.png` | iOS 18 深色外观 |
| `AppIcon-Tinted.png` | iOS 18 着色外观（模板） |
| `Logo.imageset/logo.png` | 应用内字标 |

单尺寸 1024 App Icon 即可；Xcode 会派生主屏 / 设置 / 通知等尺寸。

## store/artwork（上架与外发）

| 文件 | 尺寸 | 用途 |
|------|------|------|
| `ic_launcher_1024.png` | 1024×1024 | App Store Connect 营销图标 |
| `ic_launcher_512.png` | 512×512 | 预览 / 文档 |
| `ic_launcher_foreground_1080.png` | 1080×1080 | 透明前景层（跨端复用） |
| `logo.png` | 1024×320 | 横版字标 |
| `logo_mark.png` | 512×512 | 透明圆形标 |
| `ios/` | 常用派生预览 | 真机对照用，非必须上传 |

`screenshots/`、`creative/` 为本地生成目录（已 gitignore）。
""",
        encoding="utf-8",
    )


def main() -> None:
    any_icon = draw_mark(1024, bg=BG, with_glow=True)
    dark_icon = draw_mark(1024, bg=BG_DARK, with_glow=True)
    tinted = draw_tinted_template(1024)
    foreground = draw_mark(1080, bg=None, with_glow=False)
    wordmark = draw_wordmark(1024, 320, solid_bg=False)
    wordmark_store = draw_wordmark(1024, 320, solid_bg=True)
    mark_only = draw_mark(512, bg=None, with_glow=False)

    write_appicon_contents()
    save_rgb_no_alpha(any_icon, APPICON / "AppIcon.png")
    save_rgb_no_alpha(dark_icon, APPICON / "AppIcon-Dark.png", fallback_bg=BG_DARK[:3])
    save_rgba(tinted, APPICON / "AppIcon-Tinted.png")

    write_logo_contents()
    save_rgba(wordmark, LOGO_SET / "logo.png")

    write_accent()
    write_store_readme()

    STORE.mkdir(parents=True, exist_ok=True)
    (STORE / "screenshots").mkdir(parents=True, exist_ok=True)
    (STORE / "creative").mkdir(parents=True, exist_ok=True)

    save_rgb_no_alpha(any_icon, STORE / "ic_launcher_1024.png")
    save_rgb_no_alpha(any_icon.resize((512, 512), Image.Resampling.LANCZOS), STORE / "ic_launcher_512.png")
    save_rgba(foreground, STORE / "ic_launcher_foreground_1080.png")
    save_rgb_no_alpha(wordmark_store, STORE / "logo.png")
    save_rgba(mark_only, STORE / "logo_mark.png")

    # Common iOS derived sizes for local preview (Xcode still uses single 1024 source).
    ios_dir = STORE / "ios"
    ios_dir.mkdir(parents=True, exist_ok=True)
    for side in (180, 167, 152, 120, 87, 80, 76, 60, 58, 40, 29):
        save_rgb_no_alpha(
            any_icon.resize((side, side), Image.Resampling.LANCZOS),
            ios_dir / f"icon_{side}.png",
        )

    print("OK — 洪达快播 icons written")
    for p in (
        APPICON / "AppIcon.png",
        APPICON / "AppIcon-Dark.png",
        APPICON / "AppIcon-Tinted.png",
        LOGO_SET / "logo.png",
        STORE / "ic_launcher_1024.png",
        STORE / "ic_launcher_512.png",
        STORE / "ic_launcher_foreground_1080.png",
        STORE / "logo.png",
        STORE / "logo_mark.png",
    ):
        print(" ", p.relative_to(ROOT))


if __name__ == "__main__":
    main()
