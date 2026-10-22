import sys, hashlib, time
sys.path.insert(0, "D:/studay/AI/WorkBuddy_cache/2026-10-17-18-08-03")
from deploy_clock2 import Telnet, push_file

# 1. 推到 /tmp
push_file("kindle_clock.conf", "/tmp/kindle_clock.conf", 0.02)
time.sleep(0.5)

# 2. 另开连接安装+验证
t = Telnet("192.168.15.244", 23)
t.sync()
t.send_line("cp /tmp/kindle_clock.conf /etc/init/kindle_clock.conf && md5sum /etc/init/kindle_clock.conf && wc -l /etc/init/kindle_clock.conf && head -3 /etc/init/kindle_clock.conf; echo INST_DONE", 0.1)
out = t.read_for(4)
t.close()
txt = Telnet._strip_iac(out).decode("utf-8", "replace")
print(txt[-500:])

local = hashlib.md5(open("kindle_clock.conf", "rb").read()).hexdigest()
print("local md5:", local, "| MATCH" if local in txt else "| MISMATCH")
