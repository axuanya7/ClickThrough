"""生成 ClickThrough 的图标：深蓝紫渐变圆角底 + 两层窗口轮廓 + 鼠标指针，暗示"穿透到下层"。"""
import sys
from PIL import Image, ImageDraw

S = 256
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# 渐变底
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
c1 = (59, 130, 246)    # blue-500
c2 = (109, 40, 217)    # violet-700
for y in range(S):
    t = y / (S - 1)
    gd.line([(0, y), (S, y)], fill=(
        round(c1[0] + (c2[0] - c1[0]) * t),
        round(c1[1] + (c2[1] - c1[1]) * t),
        round(c1[2] + (c2[2] - c1[2]) * t),
        255,
    ))

# 圆角遮罩
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=56, fill=255)
img.paste(grad, (0, 0), mask)

d = ImageDraw.Draw(img)

# 底层窗口（半透明白，代表游戏）
d.rounded_rectangle([34, 52, 168, 168], radius=14, outline=(255, 255, 255, 110), width=7)
d.line([(34, 76), (168, 76)], fill=(255, 255, 255, 110), width=5)

# 顶层窗口（实白，代表浮层）
d.rounded_rectangle([86, 96, 222, 214], radius=14, outline=(255, 255, 255, 245), width=8)
d.line([(86, 124), (222, 124)], fill=(255, 255, 255, 245), width=6)
for i, x in enumerate((104, 121, 138)):
    dd = 5 - i
    d.ellipse([x - dd, 109 - dd, x + dd, 109 + dd], fill=(255, 255, 255, 225))

# 鼠标指针（穿透箭头，落在两层之间）
arrow = [
    (150, 150), (150, 214), (166, 198), (178, 224),
    (192, 217), (180, 192), (202, 192),
]
d.polygon(arrow, fill=(255, 255, 255, 255))
d.line(arrow + [arrow[0]], fill=(30, 41, 59, 255), width=6, joint="curve")

sizes = [16, 24, 32, 48, 64, 128, 256]
out = sys.argv[1] if len(sys.argv) > 1 else "icon.ico"
img.save(out, format="ICO", sizes=[(s, s) for s in sizes])
print("wrote", out)
