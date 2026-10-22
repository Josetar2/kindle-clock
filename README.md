# kindle-clock

把一块触屏损坏（上半 1/3 失灵 + 幽灵触摸）的 **Kindle Paperwhite 4 (KPW4, 固件 5.18.1.1.1)** 改造成常驻电子墨水屏座钟。

不再当阅读器：开机即时钟，息屏保留画面，断网照常显示。

## 硬件与环境

- 设备：Kindle Paperwhite 4，固件 5.18.1.1.1
- root + USB 网络（RNDIS），PC 端 telnet `192.168.15.244:23`
- 屏幕渲染依赖 **KOReader** 自带的 `FBInk`（`/mnt/us/koreader/fbink`）直接写 framebuffer
- 触屏已坏，仅保留「电源键 + 时钟」用途

## 特性

- 数码管字体时间 `HH:MM:SS`（DSEG7 Classic Bold），精确居中
- 日期 / 星期 / 干支生肖年 / 农历月日
- 联网天气（Open-Meteo）：当前温度+天气 + 未来三天预报 + 电量百分比；**断网保留最后一次成功值**
- 月历：今日描边高亮，含农历日、节气、宜忌
- 开机自动进入时钟（upstart job `kindle_clock.conf`，无需手动拉起）
- 息屏后画面保留、不白屏；电源键短按 = 整屏重绘清残影
- 每天 03:00 自动 NTP 对时（防 RTC 长期走偏）
- 亮度固定 2 档（可在 `clock.conf` 改 `BRIGHT`）

## 原理

- 启动后 `stop framework`，由脚本接管屏幕，脱离 Kindle 原生 GUI
- 主循环每 1 秒：`draw_time_box` 用 DU 波形快刷时间区，分钟切换时整屏 GC16 清残影
- **天气走文件缓存 + 后台进程**：`/tmp/clock_wx.txt` 由后台循环每 10 分钟联网写入，画屏路径只 `read` 缓存、完全不碰网络——避免唤醒时因联网卡住而「先出时间、后出其他」
- 农历数据预生成到 2045 年底（见 `data/calendar_data.txt`），运行时用月份缓存只读当月 31 行，避免每次全文件扫描

## 文件结构

```
kindle_clock.sh      主脚本（设备端 /mnt/us/clock/）
kindle_clock.conf     upstart 自启 job（设备端 /etc/init/）
fonts/
  clock_font.ttf     子集化中文黑体（含农历/节气/宜忌用字）
  dseg_font.ttf      数码管字体 DSEG7（仅 0-9 与 :）
data/
  calendar_data.txt  农历/节气/宜忌数据集 2026-01-01 .. 2045-12-31
tools/
  gen_calendar.py    重新生成 data/calendar_data.txt（依赖 lunar-python）
  subset_font.py     重新子集化 fonts/（依赖 fonttools）
  deploy_clock2.py   通过 telnet 可靠推送文件到设备（大文件走 gzip）
  install_job.py     把 kindle_clock.conf 装到设备 /etc/init/
  cap_now.py         抓取当前 framebuffer 存为 PNG（PC 端校验用）
  kindle_telnet.py   telnet 执行单条命令
  restart_verify.py  重启时钟并验证运行状态
```

## 部署（到真机）

前置：设备已 root、已开 USB 网络、已装 KOReader（提供 FBInk）。

```bash
# 1. 推送脚本/字体/数据/自启 job 到设备
python tools/deploy_clock2.py        # 推送 kindle_clock.sh + 字体 + 数据
python tools/install_job.py           # 安装 /etc/init/kindle_clock.conf 并 reload

# 2. 建立自启开关（U 盘里 /mnt/us/clock/ENABLED 存在 = 开机进时钟）
touch /mnt/us/clock/ENABLED

# 3. 重启设备，应自动进入纯时钟界面
```

可选本地调试（设备已 telnet 可达）：

```bash
python tools/kindle_telnet.py "date"          # 单条命令
python tools/restart_verify.py                # 重启并验证
python tools/cap_now.py && open clock_live.png # 抓屏
```

## 重新生成数据 / 字体

```bash
pip install lunar-python fonttools
python tools/gen_calendar.py      # 生成 data/calendar_data.txt
python tools/subset_font.py       # 生成 fonts/clock_font.ttf
```

> 默认数据到 2045-12-31；要撑更久改 `gen_calendar.py` 的 `END` 重跑即可（2046 年起农历/宜忌会空白）。

## 已知限制

- 农历数据有截止日期（2025→2045 共 20 年）
- 依赖 KOReader 的 FBInk；若未装 KOReader 需另寻 FBInk 二进制
- 自动对时与天气需要 WiFi；长期离线时间靠 RTC 走偏（每天几秒内），靠每天 03:00 联网纠正
- 锂电池长期插电供电，硬件层面建议偶尔留意鼓包

## License

MIT
