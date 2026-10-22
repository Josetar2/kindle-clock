#!/usr/bin/env python3
# 可靠地把 3 个时钟文件推送到 Kindle (telnet, 绕过防火墙入站限制)
# 策略:
#  - 逐行 printf '%s\n' 追加 (base64 仅含安全字符, 单引号安全), 不用脆弱的 heredoc
#  - 每行带节奏 delay, 避免设备 pty 输入缓冲溢出导致截断
#  - 推完 base64 -d 解码; 之后另开一个"干净" telnet 连接单独读取 md5sum 与本地比对
#  - md5 不符则整文件重推重验 (最多 6 次, 逐次放慢), 保证落地完整
import socket, time, base64, hashlib, os, re, gzip

HOST = "192.168.15.244"
PORT = 23
# (本地文件, 设备路径, 是否 gzip 传输) —— 大文件压缩后推送, 减少 telnet 输入量
FILES = [
    ("kindle_clock.sh",   "/mnt/us/clock/kindle_clock.sh",   False),
    ("clock_font.ttf",    "/mnt/us/clock/clock_font.ttf",    False),
    ("calendar_data.txt", "/mnt/us/clock/calendar_data.txt", True),
    ("dseg_font.ttf",     "/mnt/us/clock/dseg_font.ttf",     False),
]
LINE_W = 900
local_md5 = {}


class Telnet:
    def __init__(self, host, port):
        self.s = socket.create_connection((host, port), timeout=10)
        self.s.settimeout(0.3)
        time.sleep(0.4)
        self._negotiate()

    def _negotiate(self):
        self.s.settimeout(0.6)
        try:
            while True:
                d = self.s.recv(4096)
                if not d:
                    break
                self._handle_iac(d)
        except socket.timeout:
            pass

    def _handle_iac(self, data):
        i = 0
        while i < len(data):
            if data[i] == 0xFF:
                if i + 1 < len(data):
                    cmd = data[i + 1]
                    opt = data[i + 2] if i + 2 < len(data) else 0
                    if cmd == 0xFB:       # WILL -> DONT
                        self.s.sendall(b"\xff\xfe" + bytes([opt]))
                    elif cmd == 0xFD:     # DO   -> WONT
                        self.s.sendall(b"\xff\xfc" + bytes([opt]))
                    i += 3
                else:
                    i += 1
            else:
                i += 1

    @staticmethod
    def _strip_iac(data):
        out = bytearray()
        i = 0
        while i < len(data):
            if data[i] == 0xFF and i + 1 < len(data) and data[i + 1] in (0xFB, 0xFD, 0xFC, 0xFA):
                i += 3
            else:
                out.append(data[i])
                i += 1
        return bytes(out)

    def send_line(self, line, delay=0.02):
        self.s.sendall(line.encode("ascii", "replace") + b"\n")
        if delay:
            time.sleep(delay)

    def drain(self, t=0.3):
        self.s.settimeout(t)
        try:
            while True:
                d = self.s.recv(4096)
                if not d:
                    break
        except socket.timeout:
            pass

    def read_for(self, seconds=4):
        self.s.settimeout(seconds)
        end = time.time() + seconds
        data = b""
        while time.time() < end:
            try:
                d = self.s.recv(4096)
                if not d:
                    break
                self._handle_iac(d)
                data += d
            except socket.timeout:
                break
        return data

    def sync(self, tag="__SYNCK_"):
        self.send_line("echo %s$RANDOM" % tag, 0.05)
        self.read_for(2)
        self.drain(0.2)

    def close(self):
        try:
            self.s.close()
        except Exception:
            pass


def push_file(local, remote, gz, delay):
    with open(local, "rb") as f:
        raw = f.read()
    payload = gzip.compress(raw, 9) if gz else raw
    b64 = base64.b64encode(payload).decode("ascii")
    lines = [b64[i:i + LINE_W] for i in range(0, len(b64), LINE_W)]
    t = Telnet(HOST, PORT)
    t.sync()
    t.send_line("rm -f /tmp/_push.b64; touch /tmp/_push.b64", 0.1)
    t.drain(0.2)
    for ln in lines:
        t.send_line("printf '%%s\\n' '%s' >> /tmp/_push.b64" % ln, delay)
    t.drain(0.3)
    if gz:
        t.send_line("base64 -d /tmp/_push.b64 | gunzip -c > %s" % remote, 0.1)
    else:
        t.send_line("base64 -d /tmp/_push.b64 > %s" % remote, 0.1)
    t.drain(0.8)
    t.send_line("echo PUSHED_%d" % len(raw), 0.1)
    t.read_for(2)
    t.close()
    print("   pushed %d b64 lines (%d raw -> %d wire)" % (len(lines), len(raw), len(b64)))


def device_md5(remote):
    t = Telnet(HOST, PORT)
    t.sync()
    t.send_line("md5sum %s" % remote, 0.1)
    out = t.read_for(3)
    t.close()
    txt = Telnet._strip_iac(out).decode("utf-8", "replace")
    m = re.search(r"([0-9a-f]{32})", txt)
    return m.group(1) if m else None


def main():
    for local, remote, gz in FILES:
        local_md5[local] = hashlib.md5(open(local, "rb").read()).hexdigest()
    for local, remote, gz in FILES:
        ok = False
        print("[%s] %d bytes, gz=%s" % (local, os.path.getsize(local), gz))
        for attempt in range(1, 7):
            delay = 0.012 + attempt * 0.004
            try:
                push_file(local, remote, gz, delay)
                got = device_md5(remote)
            except Exception as e:
                got = "exc:%s" % e
            if got == local_md5[local]:
                ok = True
                print("[%s] OK  %d bytes  (attempt %d, delay %.3f)" % (local, os.path.getsize(local), attempt, delay))
                break
            else:
                print("[%s] attempt %d mismatch (got %s), retry" % (local, attempt, got))
                time.sleep(0.5)
        if not ok:
            print("[%s] FAILED after retries -> %s" % (local, remote))
    print("deploy done")


if __name__ == "__main__":
    main()
