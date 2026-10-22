#!/bin/sh
# kindle_clock.sh - 电子墨水屏时钟 (FBInk 渲染, 脱离 PC 独立运行)
# 顶: 大字时间 + 日期/星期/农历 + 天气(联网)
# 底: 月历(含农历/节气, 今日高亮) + 宜忌
# 启动: 接管屏幕(stop framework), 禁用休眠; 退出: 还原 framework (重启亦可)
# 依赖: /mnt/us/koreader/fbink, /mnt/us/clock/clock_font.ttf, /mnt/us/clock/calendar_data.txt

FB=/mnt/us/koreader/fbink
FONT=/mnt/us/clock/clock_font.ttf
FONT7=/mnt/us/clock/dseg_font.ttf
DATA=/mnt/us/clock/calendar_data.txt

# ---- 配置 (可被 /mnt/us/clock/clock.conf 覆盖) ----
LAT=34.55528
LON=117.73917
CITY="台儿庄"
BRIGHT=2        # 常亮亮度档位 0-24; 置空则不干预亮度
[ -f /mnt/us/clock/clock.conf ] && . /mnt/us/clock/clock.conf

# ---- 工具函数 ----
wname() { # 0=日 .. 6=六
  case $1 in
    0) echo 日;; 1) echo 一;; 2) echo 二;; 3) echo 三;; 4) echo 四;; 5) echo 五;; 6) echo 六;;
  esac
}

MFILE=/tmp/clock_month.txt   # 当月缓存: 全量数据 ~1.2MB, 避免每次 awk 全文件扫描
build_month() { # 把当月行抽成小文件(约31行), 之后 getf 只读它
  _Y=$(date +%Y); _M=$(date +%m)
  awk -F'\t' -v p="$_Y-$_M-" 'index($1,p)==1' "$DATA" > "$MFILE" 2>/dev/null
  [ -s "$MFILE" ] || cp "$DATA" "$MFILE" 2>/dev/null
}

getf() { # $1=YYYY-MM-DD $2=列(1起)
  awk -F'\t' -v d="$1" -v c="$2" '$1==d{print $c; exit}' "$MFILE"
}

norm() { # 去前导零, 避免 08/09 被当八进制
  v=$(echo "$1" | sed 's/^0*//')
  [ -z "$v" ] && v=0
  echo "$v"
}

set_brightness() { # 固定亮度: 座钟常亮, 启动时与每次整刷时兜底设一次
  [ -z "$BRIGHT" ] && return 0
  lipc-set-prop com.lab126.powerd flIntensity "$BRIGHT" 2>/dev/null
}

sync_time() { # 联网校时(防 RTC 长期走偏), 成功返回 0; 无网/无工具直接失败
  [ -x /usr/bin/ntpdate ] || return 1
  WIP=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
  [ -z "$WIP" ] && return 1
  ntpdate -b -s -u -t 5 pool.ntp.org  >/dev/null 2>&1 && return 0
  ntpdate -b -s -u -t 5 210.72.145.44 >/dev/null 2>&1 && return 0  # 国家授时中心
  return 1
}

first_dow() { # $1=Y $2=M -> 0=日..6=六 (Zeller)
  y=$1; m=$2
  [ $m -le 2 ] && { m=$((m+12)); y=$((y-1)); }
  q=1; K=$((y%100)); J=$((y/100))
  h=$(( (q + (13*(m+1))/5 + K + K/4 + J/4 + 5*J) % 7 ))
  echo $(( (h+6) % 7 ))
}

days_in_month() {
  y=$1; m=$2
  case $m in
    1|3|5|7|8|10|12) echo 31;;
    4|6|9|11) echo 30;;
    2) if [ $(( (y%4==0 && y%100!=0) || y%400==0 )) -eq 1 ]; then echo 29; else echo 28; fi;;
  esac
}

cdesc() { # 天气代码 -> 短描述
  case $1 in
    0|1) echo 晴;; 2) echo 多云;; 3) echo 阴;;
    45|48) echo 雾;; 51|53|55|56|57) echo 毛雨;;
    61|63|65|66|67) echo 雨;; 71|73|75|77) echo 雪;;
    80|81|82) echo 阵雨;; 85|86) echo 阵雪;;
    95) echo 雷雨;; 96|99) echo 雷雹;;
    *) echo 未知;;
  esac
}

# 天气走"文件缓存 + 后台更新": 联网(curl)绝不能挡在画屏路径上,
# 否则唤醒/开机时会先画出时间区然后干等网络, 看起来像"只剩上面的时间"。
#   get_wx()  : 联网取一次 -> 写 $WXF (只由后台循环 / 开机时调用)
#   read_wx() : 读 $WXF, 不联网不阻塞 (画屏路径只用它)
WXF=/tmp/clock_wx.txt        # 行1=温度 行2=描述 行3=三天预报

read_wx() { # 从缓存读; 还没取到过就显示占位符
  if [ -s "$WXF" ]; then
    WX_TEMP=$(sed -n 1p "$WXF"); WX_DESC=$(sed -n 2p "$WXF"); WX_FC=$(sed -n 3p "$WXF")
  else
    WX_TEMP="—"; WX_DESC=""; WX_FC=""
  fi
}

get_wx() { # 联网取一次写入缓存; 失败保留上次结果 (返回 1)
  try=0
  json=""
  while [ $try -lt 2 ]; do
    json=$(curl -s -m 6 "http://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min&forecast_days=4&timezone=auto" 2>/dev/null)
    [ -n "$json" ] && break
    try=$((try+1))
    sleep 2
  done
  [ -z "$json" ] && return 1                 # 没网: 保留上次结果
  tp=$(echo "$json" | sed -n 's/.*"current":{[^}]*"temperature_2m":\([-0-9.]*\).*/\1/p')
  ccode=$(echo "$json" | sed -n 's/.*"current":{[^}]*"weather_code":\([0-9]*\).*/\1/p')
  [ -z "$tp" ] && return 1                   # 解析失败: 同样保留上次结果
  ds=$(cdesc "$ccode")
  # daily 数组: 跳过今天(第1行), 取 2/3/4 = 明天/后天/大后天
  codes=$(echo "$json" | sed -n 's/.*"weather_code":\[\([^]]*\)\].*/\1/p' | tr ',' '\n')
  maxs=$(echo "$json" | sed -n 's/.*"temperature_2m_max":\[\([^]]*\)\].*/\1/p' | tr ',' '\n')
  mins=$(echo "$json" | sed -n 's/.*"temperature_2m_min":\[\([^]]*\)\].*/\1/p' | tr ',' '\n')
  i=2
  sep=""
  fc=""
  while [ $i -le 4 ]; do
    c=$(echo "$codes" | sed -n "${i}p" | tr -d ' ')
    mx=$(echo "$maxs" | sed -n "${i}p" | tr -d ' ')
    mn=$(echo "$mins" | sed -n "${i}p" | tr -d ' ')
    if [ -n "$c" ] && [ -n "$mx" ]; then
      case $i in
        2) lab=明天;; 3) lab=后天;; 4) lab=大后天;;
      esac
      fc="$fc$sep$lab $(cdesc "$c") ${mn%%.*}~${mx%%.*}°"
      sep="  "
    fi
    i=$((i+1))
  done
  printf '%s\n%s\n%s\n' "$tp" "$ds" "$fc" > "$WXF"
  return 0
}

# ---- FBInk 封装 ----
draw_center() { # px top text  (整宽居中)
  $FB -O -b -q -t regular=$FONT,px=$1,top=$2 -m "$3"
}
draw_col_center() { # px col top text  (列内居中, 列宽153; left/right 为边距)
  lc=$(( $2 * 153 )); rc=$(( 1072 - ($2 + 1) * 153 ))
  $FB -O -b -q -t regular=$FONT,px=$1,left=$lc,right=$rc,top=$3 -m "$4"
}
draw_left() { # px left top text  (左对齐, 右侧留 30 边距防溢出)
  $FB -O -b -q -t regular=$FONT,px=$1,left=$2,right=30,top=$3 -m "$4"
}
block() { # top left w h color
  $FB -b -q -k top=$1,left=$2,width=$3,height=$4 -B $5
}
commit_full() { $FB -s -W GC16 -D ORDERED; }
commit_region() { # top left w h [waveform]
  wf=$5
  [ -z "$wf" ] && wf=GC16
  $FB -s top=$1,left=$2,width=$3,height=$4 -W $wf -D ORDERED
}

clear_screen() { $FB -c -B WHITE -W GC16 -D ORDERED; }

# ---- 绘制各部分 ----
# DSEG7: "HH:MM:SS" = 6*0.816em + 2*0.200em = 5.296em
# px=180 -> advance 954px, 墨迹 917px -> 左右边距各 59 即精确居中
T_PX=180
T_MARGIN=59
draw_time_box() { # $1=波形(默认GC16)  每秒 DU 快刷, 每分钟 GC16 清残影
  # DSEG7 px180 实测宽 937 (-E), (1072-937)/2=67 -> 固定边距精确居中
  block 0 0 1072 350 WHITE
  T=$(date +%H:%M:%S)
  $FB -O -b -q -t regular=$FONT7,px=180,left=67,right=67,top=85 "$T"
  commit_region 0 0 1072 350 "$1"
}

draw_top_info() {
  block 350 0 1072 320 WHITE
  read_wx            # 只读缓存, 不联网 -> 画屏不会被网络拖住
  Y=$(date +%Y); M=$(date +%m); D=$(date +%d)
  Mn=$(norm "$M"); Dn=$(norm "$D")
  DATESTR=$(printf "%s年%s月%s日" "$Y" "$M" "$D")
  off=$(first_dow "$Y" "$Mn")
  twd=$(( (off + Dn - 1) % 7 ))
  WN=$(wname $twd)
  # 行1: 日期 + 星期
  draw_center 46 366 "$(printf "%s年%s月%s日 星期%s" "$Y" "$M" "$D" "$WN")"
  # 行2: 干支生肖年 + 农历月日
  GZ=$(getf "$Y-$M-$D" 7); LMD=$(getf "$Y-$M-$D" 2)
  if [ -n "$GZ" ]; then L2="$GZ 农历$LMD"; else L2="农历$LMD"; fi
  draw_center 32 448 "$L2"
  # 行3: 城市天气 + 电量
  BATT=$(lipc-get-prop com.lab126.powerd battLevel 2>/dev/null)
  [ -z "$BATT" ] && BATT="--"
  draw_center 32 520 "$(printf "%s %s%s  电量%s%%" "$CITY" "$WX_TEMP" "$WX_DESC" "$BATT")"
  # 行4: 未来三天预报
  [ -n "$WX_FC" ] && draw_center 26 596 "$WX_FC"
  block 654 0 1072 6 GRAY4
}

draw_calendar() {
  block 668 0 1072 772 WHITE
  i=0
  while [ $i -lt 7 ]; do
    ch=$(wname $i)
    draw_col_center 40 $i 674 "$ch"
    i=$((i+1))
  done
  Y=$(date +%Y); M=$(date +%m); D=$(date +%d)
  Mn=$(norm "$M"); Dn=$(norm "$D")
  off=$(first_dow "$Y" "$Mn")
  dim=$(days_in_month "$Y" "$Mn")
  rows=$(( (off + dim - 1) / 7 + 1 ))
  case $rows in
    5) y0=730; rh=104;;
    6) y0=718; rh=86;;
    *) y0=724; rh=95;;
  esac
  d=1
  while [ $d -le $dim ]; do
    pos=$(( off + d - 1 ))
    col=$(( pos % 7 )); row=$(( pos / 7 ))
    cx=$(( col * 153 )); cy=$(( y0 + row * rh ))
    if [ $d -eq $Dn ]; then
      block $cy $cx 153 3 BLACK
      block $(( cy + rh - 3 )) $cx 153 3 BLACK
      block $cy $cx 3 $rh BLACK
      block $cy $(( cx + 150 )) 3 $rh BLACK
    fi
    draw_col_center 44 $col $(( cy + 14 )) "$d"
    fdate=$(printf "%s-%s-%02d" "$Y" "$M" "$d")
    JQ=$(getf "$fdate" 4)
    if [ -n "$JQ" ]; then LD="$JQ"; else LD=$(getf "$fdate" 3); fi
    draw_col_center 22 $col $(( cy + rh - 34 )) "$LD"
    d=$((d+1))
  done
  fdate=$(printf "%s-%s-%02d" "$Y" "$M" "$D")
  YI=$(getf "$fdate" 5); JI=$(getf "$fdate" 6)
  draw_left 32 30 1282 "宜  $YI"
  draw_left 32 30 1352 "忌  $JI"
}

draw_static() {
  set_brightness     # 整刷时兜底固定亮度, 防止被其它进程改掉
  draw_time_box
  draw_top_info
  draw_calendar
  commit_full
}

# ---- 主流程 ----
CLEANED=0
cleanup() {
  [ "$CLEANED" = "1" ] && return
  CLEANED=1
  [ "$TEST" = "1" ] && return
  # 若还有别的时钟主进程在跑(重启竞态), 不要恢复 KOReader/framework
  others=0
  for pid in $(ps -ef | grep 'kindle_clock.sh' | grep -v grep | awk '{print $2}'); do
    [ "$pid" != "$$" ] && [ "$pid" != "$WPID1" ] && [ "$pid" != "$WPID2" ] && [ "$pid" != "$WPID3" ] && [ "$pid" != "$WPID4" ] && others=$((others+1))
  done
  if [ "$others" -le 0 ]; then
    kill $WPID1 $WPID2 $WPID3 $WPID4 2>/dev/null
    # 注意: 不能删 ENABLED —— 重启时 SIGTERM 也会走到这里,
    # 删了会导致下次开机不再自动进时钟。ENABLED 只由用户手动开关
    # (U盘里 \clock\ENABLED: 删掉=不自启, 新建空文件=开机进时钟)
    for p in $(pidof luajit 2>/dev/null); do kill -CONT $p 2>/dev/null; done
    start framework 2>/dev/null
    lipc-set-prop com.lab126.powerd preventAutoSleep 0 2>/dev/null
  fi
}
trap cleanup EXIT
trap 'cleanup; exit 0' TERM INT HUP

ensure_usbnet() { # 维护通道: telnet(23) 不在监听则拉起 USB 网络
  netstat -ln 2>/dev/null | grep -q ':23 ' && return
  [ -f "/mnt/us/documents/USB网络.sh" ] || return
  /bin/sh "/mnt/us/documents/USB网络.sh" >/dev/null 2>&1
}

if [ "$TEST" != "1" ]; then
  # 自启动标记: 存在 -> 下次开机由 upstart 自动进时钟; 退出时自动清除
  touch /mnt/us/clock/ENABLED
  ensure_usbnet
  echo "kindle_clock: freezing koreader (SIGSTOP)..."
  for p in $(pidof luajit 2>/dev/null); do kill -STOP $p 2>/dev/null; done
  echo "kindle_clock: stopping framework..."
  stop framework 2>/dev/null
  lipc-set-prop com.lab126.powerd preventAutoSleep 1 2>/dev/null
  set_brightness
  # 等待 WiFi 拿到 IP (重启后 wifid 需要几秒), 最多 20s
  i=0
  while [ $i -lt 20 ]; do
    WIP=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
    [ -n "$WIP" ] && break
    sleep 1; i=$((i+1))
  done
  sync_time          # 开机先校一次时(有网才成功)
  get_wx             # 开机同步取一次天气; 之后交给后台循环, 不再阻塞画屏
fi

build_month
clear_screen
draw_static

if [ "$TEST" = "1" ]; then
  echo "kindle_clock: TEST mode, drew once, exiting."
  exit 0
fi

# framework 停止过程中可能在屏幕上画错误弹窗, 延迟几秒再整屏盖一次
sleep 6
clear_screen
draw_static

last_day=$(date +%Y-%m-%d)
last_min="x"
last_sync=""
RD=/tmp/clock_redraw
PAUSE=/tmp/clock_pause
rm -f $RD $PAUSE

# 事件监听: 息屏 -> 暂停刷新; 唤醒 -> 恢复 (不再整屏重绘, 防闪烁)
(
  while true; do
    lipc-wait-event com.lab126.powerd goingToScreenSaver >/dev/null 2>&1
    touch $PAUSE 2>/dev/null
  done
) &
WPID1=$!
(
  while true; do
    lipc-wait-event com.lab126.powerd outOfScreenSaver >/dev/null 2>&1
    rm -f $PAUSE 2>/dev/null
  done
) &
WPID2=$!

# 电源键接管: framework 停了没人处理按键, 自己监听 event0(snvs-powerkey)
# 短按 = 立刻整屏重绘(清掉长期 DU 快刷留下的残影); 画面始终保留, 不会白屏
# 长按 = 系统关机菜单(仍由 powerd 处理)
PWR=/dev/input/event0
(
  while true; do
    ev=$(dd if=$PWR bs=16 count=1 2>/dev/null | hexdump -v -e '1/4 "%d " 1/4 "%d " 1/2 "%d " 1/2 "%d " 1/4 "%d" "\n"' 2>/dev/null)
    set -- $ev
    typ=$3; code=$4; val=$5
    if [ "$typ" = "1" ] && [ "$code" = "116" ] && [ "$val" = "1" ]; then
      rm -f $PAUSE            # 若正处息屏/暂停, 顺带恢复刷新
      build_month
      draw_static
    fi
  done
) &
WPID3=$!

# 天气后台更新: 每 10 分钟联网取一次写入缓存文件
# 必须放后台 —— 放在画屏路径上会让唤醒时先出时间、再干等网络
(
  while true; do
    sleep 600
    get_wx
  done
) &
WPID4=$!

full=0; last_wx=""
while true; do
  sleep 1
  # 息屏中: 完全不刷 (e-ink 画面保留), 唤醒后下一秒自动恢复
  [ -f $PAUSE ] && continue
  full=$((full+1))
  now_day=$(date +%Y-%m-%d)
  now_min=$(date +%M)
  now_h=$(date +%H)
  if [ "$now_day" != "$last_day" ]; then
    build_month
    draw_static
    last_day=$now_day
    full=0
    continue
  fi
  # 每天凌晨 3 点联网校时一次; 成功则重画, 失败下一分钟重试 (无网就跳过)
  if [ "$now_h" = "03" ] && [ "$last_sync" != "$now_day" ]; then
    if sync_time; then
      last_sync=$now_day
      build_month
      draw_static
      full=0
      continue
    fi
  fi
  # 时间: 每秒 DU 快刷; 换分钟时 GC16 清一次残影
  if [ "$now_min" != "$last_min" ]; then
    draw_time_box GC16
    last_min=$now_min
  else
    draw_time_box DU
  fi
  # 天气/电量: 每 10 分钟
  nmn=$(norm "$now_min")
  if [ $((nmn % 10)) -eq 0 ] && [ "$now_min" != "$last_wx" ]; then
    draw_top_info
    commit_region 350 0 1072 320
    last_wx=$now_min
  fi
  # 兜底: 每 30 分钟整刷一次, 防任何意外盖屏
  if [ $full -ge 1800 ]; then
    draw_static
    full=0
  fi
done
