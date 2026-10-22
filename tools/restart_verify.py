#!/usr/bin/env python3
# 重启时钟并验证: 单实例 / 主循环在跑 / 月份缓存 / 天气缓存 / 亮度 / 无报错
import time, sys, re, socket
sys.path.insert(0, "D:/studay/AI/WorkBuddy_cache/2026-10-17-18-08-03")
from deploy_clock2 import Telnet

HOST, PORT = "192.168.15.244", 23


def read_idle(t, max_idle=3.0, max_total=30):
    t.s.settimeout(max_idle)
    end = time.time() + max_total
    data = b""
    while time.time() < end:
        try:
            d = t.s.recv(8192)
            if not d:
                break
            t._handle_iac(d)
            data += d
        except socket.timeout:
            break
    return data


def run(t, cmd, wait=3.0):
    t.send_line(cmd, 0.1)
    return Telnet._strip_iac(read_idle(t, max_idle=wait)).decode("utf-8", "replace")


def main():
    t = Telnet(HOST, PORT)
    t.sync()
    print("=== kill old ===")
    print(run(t, "pkill -f kindle_clock; sleep 3; echo KDONE")[-300:])
    print("=== relaunch ===")
    print(run(t, "nohup sh /mnt/us/clock/kindle_clock.sh >/tmp/clock_run.log 2>&1 & echo RDONE", 2.0)[-200:])
    print("waiting 40s ...")
    time.sleep(40)
    t.drain(0.2)

    print("=== state ===")
    print(run(t, "ps -ef|grep -c '[k]indle_clock.sh'; "
                "wc -l < /tmp/clock_month.txt; "
                "cat /tmp/clock_wx.txt; "
                "lipc-get-prop com.lab126.powerd flIntensity; "
                "initctl status framework; "
                "date '+%F %T'; echo S1", 4.0)[-600:])
    t.drain(0.2)

    # 主循环是否在推进: 用两次 CPU tick 采样 (shell 主进程)
    p1 = run(t, "cat /proc/$(ps -ef|grep '[k]indle_clock.sh'|awk 'NR==1{print $2}')/stat 2>/dev/null|awk '{print $14+$15}'; echo T1", 2.0)
    time.sleep(8)
    t.drain(0.2)
    p2 = run(t, "cat /proc/$(ps -ef|grep '[k]indle_clock.sh'|awk 'NR==1{print $2}')/stat 2>/dev/null|awk '{print $14+$15}'; echo T2", 2.0)
    t.drain(0.2)
    print("ticks sample1:", p1[-80:].strip().replace("\r", ""))
    print("ticks sample2:", p2[-80:].strip().replace("\r", ""))

    print("=== log tail ===")
    print(run(t, "tail -15 /tmp/clock_run.log; echo S2", 3.0)[-800:])
    t.close()


main()
