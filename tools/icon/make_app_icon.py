#!/usr/bin/env python3
"""Draw the app icon: a close-up of piano keys in the app's style (black lacquer, red felt,
ivory keys, glossy black keys) with the middle key pressed and an amber light trail rising.

Writes three 1024x1024 PNGs for the asset catalog: default, dark, and tinted (grayscale).
Usage: python3 make_app_icon.py <AppIcon.appiconset folder>      (needs Pillow)
"""
import colorsys
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

FINAL = 1024
SS = 4                     # draw at 4x and scale down for smooth edges
W = FINAL * SS


def hexc(h, a=255):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255, a)


def vgrad(w, h, stops):
    """Vertical gradient image; stops = [(position 0-1, rgba), ...]."""
    w, h = max(1, int(w)), max(1, int(h))
    column = Image.new("RGBA", (1, h))
    px = column.load()
    for y in range(h):
        t = y / max(1, h - 1)
        for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
            if p0 <= t <= p1:
                f = (t - p0) / max(1e-9, p1 - p0)
                px[0, y] = tuple(int(c0[i] + (c1[i] - c0[i]) * f) for i in range(4))
                break
    return column.resize((w, h))


def rounded_mask(w, h, r, top=False, bottom=True):
    m = Image.new("L", (int(w), int(h)), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, int(w) - 1, int(h) - 1], radius=int(r), fill=255,
                                        corners=(top, top, bottom, bottom))
    return m


def paste(base, tile, x, y, mask=None):
    if mask is None:
        base.alpha_composite(tile, (int(x), int(y)))
    else:
        clear = Image.new("RGBA", tile.size, (0, 0, 0, 0))
        base.alpha_composite(Image.composite(tile, clear, mask), (int(x), int(y)))


def draw_icon():
    img = vgrad(W, W, [(0, hexc(0x1E1E24)), (0.45, hexc(0x111115)), (1, hexc(0x07070A))])

    key_w = W / 4                      # half B | C | D | E | half F
    keys_top = W * 0.36
    keys_bottom = W * 0.94
    key_h = keys_bottom - keys_top
    gap = W * 0.010
    felt_h = W * 0.028
    amber = (250, 133, 64)

    # A light trail rising from the pressed D, out of the felt, fading toward the top.
    trails = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    for centre, bottom, top, strength, hue_t in [
        (W / 2, keys_top - felt_h, -W * 0.02, 1.0, 0.45),
    ]:
        r, g, b = colorsys.hsv_to_rgb(0.055 + 0.075 * hue_t, 0.78 - 0.28 * hue_t, 1)
        col = (int(r * 255), int(g * 255), int(b * 255))
        tw = key_w * 0.6
        tile = vgrad(tw, bottom - top, [(0, col + (0,)), (0.55, col + (int(150 * strength),)),
                                        (1, col + (int(245 * strength),))])
        paste(trails, tile, centre - tw / 2, top)
        wide = tile.resize((int(tw * 2.2), tile.height))
        paste(glow, wide, centre - tw * 1.1, top)
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(W * 0.05)))
    img.alpha_composite(trails)

    # White keys.
    xs = [-key_w / 2 + i * key_w for i in range(5)]          # B, C, D, E, F
    for i, x in enumerate(xs):
        pressed = i == 2
        w = key_w - gap
        stops = ([(0, hexc(0xD3CEC4)), (0.22, hexc(0xE7E3DA)), (1, hexc(0xEEEAE2))] if pressed else
                 [(0, hexc(0xE1DDD3)), (0.12, hexc(0xF5F2EB)), (0.72, hexc(0xFBF9F4)), (1, hexc(0xF0ECE3))])
        tile = vgrad(w, key_h, stops)
        lip = W * (0.012 if pressed else 0.026)
        tile.alpha_composite(vgrad(w, lip, [(0, hexc(0xE6E1D7)), (1, hexc(0xCFC9BC))]), (0, int(key_h - lip)))
        if pressed:
            gh = key_h * 0.70
            tile.alpha_composite(vgrad(w, gh, [(0, amber + (0,)), (1, amber + (150,))]), (0, int(key_h - gh)))
        paste(img, tile, x + gap / 2, keys_top, rounded_mask(w, key_h, W * 0.035))

    # Black keys (C# and D#) with soft shadows.
    black_w = key_w * 0.58
    black_h = key_h * 0.60
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    for boundary in (xs[1] + key_w, xs[2] + key_w):
        x0 = boundary - black_w / 2
        sd.rounded_rectangle([x0, keys_top + W * 0.012, x0 + black_w, keys_top + black_h + W * 0.018],
                             radius=W * 0.02, fill=(0, 0, 0, 140))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(W * 0.012)))
    for boundary in (xs[1] + key_w, xs[2] + key_w):
        x0 = boundary - black_w / 2
        body = Image.new("RGBA", (int(black_w), int(black_h)), hexc(0x050506))
        inset, front = black_w * 0.09, W * 0.035
        top = vgrad(black_w - 2 * inset, black_h - front,
                    [(0, hexc(0x2E2E35)), (0.55, hexc(0x18181C)), (0.93, hexc(0x30303A)), (1, hexc(0x1B1B1F))])
        paste(body, top, inset, 0, rounded_mask(top.width, top.height, W * 0.008))
        face = vgrad(black_w - 2 * SS, front - SS, [(0, hexc(0x4A4A53)), (1, hexc(0x1E1E23))])
        paste(body, face, SS, black_h - front)
        paste(img, body, x0, keys_top, rounded_mask(black_w, black_h, W * 0.016))

    # Fallboard shadow and red felt along the back of the keys.
    img.alpha_composite(vgrad(W, felt_h * 2.2, [(0, (0, 0, 0, 100)), (1, (0, 0, 0, 0))]), (0, int(keys_top)))
    img.alpha_composite(vgrad(W, felt_h, [(0, hexc(0x9A2639)), (1, hexc(0x5E1322))]), (0, int(keys_top - felt_h)))

    return img.convert("RGB").resize((FINAL, FINAL), Image.LANCZOS)


def main():
    folder = sys.argv[1]
    icon = draw_icon()
    icon.save(os.path.join(folder, "AppIcon.png"))
    icon.save(os.path.join(folder, "AppIcon-Dark.png"))          # already dark
    icon.convert("L").convert("RGB").save(os.path.join(folder, "AppIcon-Tinted.png"))


if __name__ == "__main__":
    main()
