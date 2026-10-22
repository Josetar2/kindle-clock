#!/usr/bin/env python3
# 生成农历/节气/宜忌数据集 (城市无关, 基于日期)
# 输出 TSV: YYYY-MM-DD <TAB> 农历月日 <TAB> 农历日 <TAB> 节气 <TAB> 宜 <TAB> 忌 <TAB> 干支生肖年
import datetime
from lunar_python import Solar, Lunar

START = datetime.date(2026, 1, 1)
END   = datetime.date(2045, 12, 31)   # 20 年, 长期放置不断电也能一直查到农历/宜忌

rows = []
d = START
while d <= END:
    s = Solar.fromYmd(d.year, d.month, d.day)
    l = s.getLunar()
    lunar_md = l.getMonthInChinese() + "月" + l.getDayInChinese()   # 九月初十
    lunar_d  = l.getDayInChinese()                            # 初十
    jieqi    = l.getJieQi() or ""                             # 立春 / 空
    yi       = " ".join(l.getDayYi())       # 词组间留空格, 便于阅读
    ji       = " ".join(l.getDayJi())
    try:
        ganzhi = l.getYearInGanZhi() + l.getYearShengXiao() + "年"   # 丙午马年
    except Exception:
        ganzhi = ""
    rows.append("\t".join([d.isoformat(), lunar_md, lunar_d, jieqi, yi, ji, ganzhi]))
    d += datetime.timedelta(days=1)

out = "\n".join(rows) + "\n"
# 必须 newline="\n": Windows 下默认会把 \n 写成 \r\n, 导致最后一列带 \r (FBInk 会当成换行!)
with open("calendar_data.txt", "w", encoding="utf-8", newline="\n") as f:
    f.write(out)
print(f"written {len(rows)} days -> calendar_data.txt")
print("sample:")
for r in rows[:2] + rows[31:33]:
    print(r)
