"""Render the dungeon key badge (Modules/Nav/Art/DungeonKey.tga).

128x128, a gold key with a dark outline on a clear background, drawn four
times larger and scaled down so its edges stay smooth at any badge size.

  python tools/make-key-art.py
"""
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Modules", "Nav", "Art")
SIZE, SS = 128, 4


def key_mask(grow: int) -> Image.Image:
    """The key's silhouette lying flat (bow left, bit right), `grow` px fatter."""
    n = SIZE * SS
    m = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(m)
    cy = n // 2
    bow_x, bow_r, hole_r = int(n * 0.27), int(n * 0.17), int(n * 0.085)
    shaft_h, shaft_end = int(n * 0.045), int(n * 0.88)
    d.ellipse([bow_x - bow_r - grow, cy - bow_r - grow, bow_x + bow_r + grow, cy + bow_r + grow], fill=255)
    d.rounded_rectangle([bow_x, cy - shaft_h - grow, shaft_end + grow, cy + shaft_h + grow],
                        radius=shaft_h + grow, fill=255)
    for x0, x1, depth in ((0.66, 0.72, 0.13), (0.78, 0.85, 0.17)):
        d.rounded_rectangle([int(n * x0) - grow, cy, int(n * x1) + grow, cy + int(n * depth) + grow],
                            radius=int(n * 0.012) + grow, fill=255)
    hole = max(1, hole_r - grow)
    d.ellipse([bow_x - hole, cy - hole, bow_x + hole, cy + hole], fill=0)
    return m


def main() -> None:
    n = SIZE * SS
    edge = key_mask(int(n * 0.028))
    body = key_mask(0)
    # Gold, lighter towards the top, with a soft highlight along the upper edge.
    gold = Image.new("RGBA", (n, n))
    px = gold.load()
    for y in range(n):
        t = y / (n - 1)
        row = (int(255 - 40 * t), int(214 - 70 * t), int(96 - 60 * t), 255)
        for x in range(n):
            px[x, y] = row
    shine = ImageChops.subtract(body, ImageChops.offset(body, 0, int(n * 0.012)))
    shine = shine.filter(ImageFilter.GaussianBlur(n * 0.004))
    art = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    art.paste(Image.new("RGBA", (n, n), (28, 18, 6, 255)), (0, 0), edge)
    art.paste(gold, (0, 0), body)
    art.paste(Image.new("RGBA", (n, n), (255, 246, 205, 255)), (0, 0), shine.point(lambda v: int(v * 0.75)))
    art = art.rotate(45, resample=Image.BICUBIC)       # bow up-left, bit down-right
    art = art.resize((SIZE, SIZE), Image.LANCZOS)
    art.save(os.path.join(OUT, "DungeonKey.tga"))
    print("DungeonKey.tga", art.size)


if __name__ == "__main__":
    main()
