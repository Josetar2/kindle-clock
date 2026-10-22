#!/usr/bin/env python3
# 只抓当前帧(不重画), 用于查看正在运行的时钟实际显示
import time, sys, socket, base64, zlib, struct, gzip
sys.path.insert(0, "D:/studay/AI/WorkBuddy_cache/2026-10-17-18-08-03")
from deploy_clock2 import Telnet

HOST, PORT = "192.168.15.244", 23
STRIDE, VISW, H = 1088, 1072, 1448

def read_idle(t, max_idle=3.0, max_total=40):
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

def main():
    t = Telnet(HOST, PORT)
    t.sync()
    t.send_line("dd if=/dev/fb0 of=/tmp/fb.raw bs=%d count=%d 2>/dev/null; gzip -c /tmp/fb.raw >/tmp/fb.gz; echo CAPDONE" % (STRIDE, H), 0.1)
    o = read_idle(t, max_idle=3.0, max_total=30)
    t.drain(0.2)
    t.send_line("echo B64START; base64 /tmp/fb.gz; echo B64END", 0.1)
    b64t = Telnet._strip_iac(read_idle(t, max_idle=3.0, max_total=45)).decode("utf-8", "replace")
    t.close()
    lines = [ln.strip() for ln in b64t.replace("\r", "").split("\n")]
    s = lines.index("B64START") + 1
    e = lines.index("B64END", s)
    body = "".join(lines[s:e])
    raw = gzip.decompress(base64.b64decode(body + "=" * ((4 - len(body) % 4) % 4)))
    rows = [raw[y * STRIDE:(y * STRIDE) + VISW] for y in range(H)]
    def chunk(typ, data):
        c = typ + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    idat = zlib.compress(b"".join(b"\x00" + r for r in rows), 9)
    p = "D:/studay/AI/WorkBuddy_cache/2026-10-17-18-08-03/clock_live.png"
    with open(p, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", VISW, H, 8, 0, 0, 0, 0)))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))
    print("live capture saved:", p, "raw", len(raw))

main()
