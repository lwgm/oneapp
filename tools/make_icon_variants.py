"""
生成 5 个 App 图标候选。共同点：元素少、形状大、无高频细节。
输出 1024x1024 PNG 到 Files/icon-variants/。
"""
import os
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 4
W = S * SS
OUT = os.path.join("Files", "icon-variants")

GREEN_TOP = (0x16, 0x44, 0x3C)
GREEN_BOT = (0x07, 0x1A, 0x18)
GREEN_FLAT = (0x12, 0x3A, 0x33)
CREAM = (0xF7, 0xF4, 0xEC)
CREAM_DIM = (0xD9, 0xD1, 0xBE)
CYAN = (0x7F, 0xE3, 0xFF)
INK = (0x0D, 0x1F, 0x1C)


def px(v):
    return int(v * W)


def vertical_gradient(top, bottom):
    img = Image.new("RGB", (W, W), top)
    d = ImageDraw.Draw(img)
    for y in range(W):
        t = y / (W - 1)
        d.line(
            [(0, y), (W, y)],
            fill=(
                int(top[0] + (bottom[0] - top[0]) * t),
                int(top[1] + (bottom[1] - top[1]) * t),
                int(top[2] + (bottom[2] - top[2]) * t),
            ),
        )
    return img


def add_glow_highlight(img, color, cx, cy, radius, strength):
    mask = Image.new("L", (W, W), 0)
    md = ImageDraw.Draw(mask)
    md.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=strength)
    mask = mask.filter(ImageFilter.GaussianBlur(W // 7))
    return Image.composite(Image.new("RGB", (W, W), color), img, mask)


def green_base():
    img = vertical_gradient(GREEN_TOP, GREEN_BOT)
    return add_glow_highlight(img, "#2E6B61", px(0.20), px(0.06), px(0.80), 82)


def cream_base():
    img = vertical_gradient((0xFB, 0xF9, 0xF3), (0xE6, 0xE0, 0xD2))
    return add_glow_highlight(img, "#FFFFFF", px(0.22), px(0.02), px(0.82), 96)


def draw_book(layer, cx, cy, w, h, radius, fill):
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle(
        [cx - w // 2, cy - h // 2, cx + w // 2, cy + h // 2],
        radius=radius,
        fill=fill,
    )


def save(img, name):
    img.resize((S, S), Image.LANCZOS).save(os.path.join(OUT, name), "PNG")
    print("saved", name)


# ---------- A：书本 + 取景四角（沿用 App 里的扫码框语言）----------
def variant_a():
    img = green_base()
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    bw, bh = px(0.40), px(0.50)
    draw_book(layer, W // 2, W // 2, bw, bh, px(0.045), CREAM + (255,))

    # 书脊
    d.rounded_rectangle(
        [W // 2 - bw // 2, W // 2 - bh // 2, W // 2 - bw // 2 + px(0.055), W // 2 + bh // 2],
        radius=px(0.045), fill=CREAM_DIM + (255,),
    )
    d.rectangle(
        [W // 2 - bw // 2 + px(0.045), W // 2 - bh // 2 + px(0.03),
         W // 2 - bw // 2 + px(0.055), W // 2 + bh // 2 - px(0.03)],
        fill=CREAM_DIM + (255,),
    )

    # 取景四角
    inset = px(0.125)
    seg = px(0.135)
    thick = px(0.045)
    for ox, oy, sx, sy in [
        (inset, inset, 1, 1),
        (W - inset, inset, -1, 1),
        (inset, W - inset, 1, -1),
        (W - inset, W - inset, -1, -1),
    ]:
        d.rounded_rectangle(
            [min(ox, ox + sx * seg), oy - thick // 2,
             max(ox, ox + sx * seg), oy + thick // 2],
            radius=thick // 2, fill=(255, 255, 255, 255),
        )
        d.rounded_rectangle(
            [ox - thick // 2, min(oy, oy + sy * seg),
             ox + thick // 2, max(oy, oy + sy * seg)],
            radius=thick // 2, fill=(255, 255, 255, 255),
        )

    img.paste(layer, (0, 0), layer)
    save(img, "A-取景框.png")


# ---------- B：书本 + 单条扫描线 ----------
def variant_b():
    img = green_base()
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw_book(layer, W // 2, W // 2, px(0.42), px(0.52), px(0.048), CREAM + (255,))

    # 发光扫描线（先在独立层上画，再模糊叠加）
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    y = int(W * 0.545)
    gd.rounded_rectangle(
        [px(0.155), y - px(0.022), W - px(0.155), y + px(0.022)],
        radius=px(0.022), fill=CYAN + (255,),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(px(0.028)))
    layer = Image.alpha_composite(layer, glow)

    d = ImageDraw.Draw(layer)
    d.rounded_rectangle(
        [px(0.155), y - px(0.011), W - px(0.155), y + px(0.011)],
        radius=px(0.011), fill=(0xE8, 0xFA, 0xFF, 255),
    )

    img.paste(layer, (0, 0), layer)
    save(img, "B-扫描线.png")


# ---------- C：书本 + 放大镜 ----------
def variant_c():
    img = green_base()
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw_book(layer, int(W * 0.44), int(W * 0.44), px(0.40), px(0.50), px(0.045), CREAM + (255,))

    d = ImageDraw.Draw(layer)
    ccx, ccy = int(W * 0.665), int(W * 0.665)
    r_out, r_in = px(0.150), px(0.098)
    d.ellipse([ccx - r_out, ccy - r_out, ccx + r_out, ccy + r_out], fill=(255, 255, 255, 255))
    d.ellipse([ccx - r_in, ccy - r_in, ccx + r_in, ccy + r_in], fill=GREEN_FLAT + (255,))

    hx0, hy0 = int(ccx + r_out * 0.72), int(ccy + r_out * 0.72)
    hx1, hy1 = int(ccx + r_out * 1.62), int(ccy + r_out * 1.62)
    d.line([hx0, hy0, hx1, hy1], fill=(255, 255, 255, 255), width=px(0.058))
    d.ellipse([hx1 - px(0.029), hy1 - px(0.029), hx1 + px(0.029), hy1 + px(0.029)],
              fill=(255, 255, 255, 255))

    img.paste(layer, (0, 0), layer)
    save(img, "C-放大镜.png")


# ---------- D：极简书脊（横向书带）----------
def variant_d():
    img = green_base()
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    cx = W // 2
    sw, sh = px(0.30), px(0.56)
    left, top = cx - sw // 2, W // 2 - sh // 2
    d.rounded_rectangle([left, top, left + sw, top + sh], radius=px(0.040), fill=CREAM + (255,))

    # 右侧书页厚度
    d.rounded_rectangle(
        [left + sw, top + px(0.020), left + sw + px(0.038), top + sh - px(0.020)],
        radius=px(0.016), fill=CREAM_DIM + (255,),
    )

    # 三道书带
    for fy in (0.255, 0.435, 0.615):
        by = top + int(sh * fy)
        d.rounded_rectangle(
            [left + px(0.045), by, left + sw - px(0.045), by + px(0.048)],
            radius=px(0.014), fill=GREEN_FLAT + (255,),
        )

    img.paste(layer, (0, 0), layer)
    save(img, "D-书脊.png")


# ---------- E：米白底 + 深绿书（反色）----------
def variant_e():
    img = cream_base()
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    cx, cy = W // 2, W // 2
    bw, bh = px(0.42), px(0.52)
    draw_book(layer, cx, cy, bw, bh, px(0.048), GREEN_FLAT + (255,))

    # 书脊亮边
    d.rounded_rectangle(
        [cx - bw // 2, cy - bh // 2, cx - bw // 2 + px(0.050), cy + bh // 2],
        radius=px(0.048), fill=(0x2C, 0x66, 0x5B, 255),
    )
    d.rectangle(
        [cx - bw // 2 + px(0.040), cy - bh // 2 + px(0.032),
         cx - bw // 2 + px(0.050), cy + bh // 2 - px(0.032)],
        fill=(0x2C, 0x66, 0x5B, 255),
    )

    # 扫描线
    y = int(W * 0.545)
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rounded_rectangle(
        [px(0.175), y - px(0.020), W - px(0.175), y + px(0.020)],
        radius=px(0.020), fill=CYAN + (255,),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(px(0.024)))
    layer = Image.alpha_composite(layer, glow)
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle(
        [px(0.175), y - px(0.010), W - px(0.175), y + px(0.010)],
        radius=px(0.010), fill=(0xCF, 0xF4, 0xFF, 255),
    )

    img.paste(layer, (0, 0), layer)
    save(img, "E-反色.png")


os.makedirs(OUT, exist_ok=True)
variant_a()
variant_b()
variant_c()
variant_d()
variant_e()
print("done")
