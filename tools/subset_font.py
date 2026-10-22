#!/usr/bin/env python3
# 子集化中文字体: 仅保留 数据集用到的汉字 + 界面用字 -> 小 TTF 给 Kindle FBInk 用
from fontTools.subset import Subsetter, Options
from fontTools.ttLib import TTFont

chars = set()
with open("calendar_data.txt", encoding="utf-8") as f:
    for line in f:
        for ch in line:
            if ch.strip():
                chars.add(ch)

ui = ("0123456789:.C,-~ "
      "年月日星期农历宜忌天气台儿庄市区省"
      "日一二三四五六初十廿"
      "晴间多云阴雾毛毛雨雨雪阵雷伴冰雹未知"
      "明天后天大电量%"
      "°—")
for ch in ui:
    chars.add(ch)

text = "".join(sorted(chars))
print("unique chars:", len(chars))

src = "C:/Windows/Fonts/simhei.ttf"
font = TTFont(src)
opts = Options()
opts.glyph_names = False
opts.notdef_outline = True
ss = Subsetter(options=opts)
ss.populate(text=text)
ss.subset(font)
font.save("clock_font.ttf")
print("saved clock_font.ttf")

# 校验关键字
need = "年月日星期农历宜忌台儿庄晴雨°—"
miss = [c for c in need if c not in text]
print("missing critical:", miss if miss else "none")
