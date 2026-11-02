"""生成 App 图标的深色变体（iOS 18+ 的 dark appearance）。

浅色版是深绿底 + 米白书 + 青色扫描线。深色版在同构图上做三处调整：
  - 底色压到近黑，避免在深色壁纸上「发灰」
  - 书本降到柔和的米灰，减少在暗环境里的刺眼感
  - 扫描线保留青色并略提亮，作为唯一的高光锚点

用法：python tools/make_icon_dark.py
输出：Sources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-dark.png
"""
import os
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 4
W = S * SS
OUT = os.path.join(
    "Sources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024-dark.png"
)

BG_TOP = (0x0C, 0x1F, 0x1C)
BG_BOT = (0x03, 0x07, 0x07)
BOOK = (0xE9, 0xE5, 0xDA)
LINE = (0x8A, 0xE9, 0xFF)
GLOW = (0x1E, 0x4A, 0x42)


def px(v):
    return int(v * W)


def main():
    img = Image.new("RGB", (W, W), BG_BOT)
    d = ImageDraw.Draw(img)

    for y in range(W):
        t = y / (W - 1)
        d.line(
            [(0, y), (W, y)],
            fill=(
                int(BG_TOP[0] + (BG_BOT[0] - BG_TOP[0]) * t),
                int(BG_TOP[1] + (BG_BOT[1] - BG_TOP[1]) * t),
                int(BG_TOP[2] + (BG_BOT[2] - BG_TOP[2]) * t),
            ),
        )

    # 左上柔光，让近黑底不至于死平
    mask = Image.new("L", (W, W), 0)
    md = ImageDraw.Draw(mask)
    rad = int(W * 0.72)
    cx, cy = px(0.20), px(0.05)
    md.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=70)
    mask = mask.filter(ImageFilter.GaussianBlur(W // 7))
    img = Image.composite(Image.new("RGB", (W, W), GLOW), img, mask)

    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw_book(layer, W // 2, W // 2, px(0.42), px(0.52), px(0.048))

    # 扫描线：先画软的辉光，再叠一条实心细线
    y = int(W * 0.545)
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rounded_rectangle(
        [px(0.155), y - px(0.022), W - px(0.155), y + px(0.022)],
        radius=px(0.022),
        fill=LINE + (255,),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(px(0.030)))
    layer = Image.alpha_composite(layer, glow)

    ld = ImageDraw.Draw(layer)
    ld.rounded_rectangle(
        [px(0.155), y - px(0.011), W - px(0.155), y + px(0.011)],
        radius=px(0.011),
        fill=(0xF2, 0xFC, 0xFF, 255),
    )

    img.paste(layer, (0, 0), layer)
    img.resize((S, S), Image.LANCZOS).save(OUT, "PNG")

    print("saved:", OUT)
    print("bytes:", os.path.getsize(OUT))


def draw_book(layer, cx, cy, w, h, radius):
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle(
        [cx - w // 2, cy - h // 2, cx + w // 2, cy + h // 2],
        radius=radius,
        fill=BOOK + (255,),
    )
    # 书脊留一道更暗的竖边，保留立体感
    spine = px(0.05)
    d.rounded_rectangle(
        [cx - w // 2, cy - h // 2, cx - w // 2 + spine, cy + h // 2],
        radius=radius,
        fill=(0xC9, 0xC4, 0xB6, 255),
    )
    d.rectangle(
        [
            cx - w // 2 + spine - px(0.004),
            cy - h // 2 + px(0.03),
            cx - w // 2 + spine,
            cy + h // 2 - px(0.03),
        ],
        fill=(0xC9, 0xC4, 0xB6, 255),
    )


if __name__ == "__main__":
    main()
