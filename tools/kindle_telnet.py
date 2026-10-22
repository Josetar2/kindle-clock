import socket, sys, time

HOST = "192.168.15.244"
PORT = 23
CMD = sys.argv[1] if len(sys.argv) > 1 else "id; uname -a"

def main():
    s = socket.create_connection((HOST, PORT), timeout=5)
    s.settimeout(3)
    out = b""
    def read_avail():
        nonlocal out
        try:
            data = s.recv(4096)
            if data:
                out += data
        except socket.timeout:
            pass
    # handle telnet negotiation: reply WONT/DONT to everything
    time.sleep(0.5)
    read_avail()
    s.sendall(CMD.encode() + b"\n")
    time.sleep(1.5)
    for _ in range(6):
        read_avail()
    s.close()
    text = out.decode("utf-8", "replace")
    # strip IAC sequences
    import re
    text = re.sub(r"\xff[\xef\xfe\xfd\xfc\xfb\xfa](.?)", "", text, flags=re.S)
    print(text)

main()
