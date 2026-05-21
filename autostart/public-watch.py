import ctypes, os, struct, subprocess, sys
from pathlib import Path

IN_ACCESS      = 0x00000001
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_FROM  = 0x00000040
IN_MOVED_TO    = 0x00000080
IN_CREATE      = 0x00000100
IN_DELETE      = 0x00000200
IN_ISDIR       = 0x40000000
WATCH_MASK     = IN_ACCESS | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE | IN_DELETE

libc = ctypes.CDLL("libc.so.6", use_errno=True)
watch_dir = Path.home() / "Public"

fd = libc.inotify_init()
if fd < 0:
    sys.exit(1)

wd_to_path = {}

def add_watch(path):
    wd = libc.inotify_add_watch(fd, str(path).encode(), WATCH_MASK)
    if wd >= 0:
        wd_to_path[wd] = Path(path)

def add_recursive(path):
    add_watch(path)
    try:
        for e in os.scandir(path):
            if e.is_dir(follow_symlinks=False):
                add_recursive(e.path)
    except PermissionError:
        pass

add_recursive(watch_dir)

HEADER = struct.Struct("iIII")
HDR_SIZE = HEADER.size

def smb_clients():
    clients = []
    try:
        with open("/proc/net/tcp") as f:
            for line in f.readlines()[1:]:
                parts = line.split()
                if len(parts) < 4 or parts[3] != "01":
                    continue
                local_port = int(parts[1].split(":")[1], 16)
                if local_port != 445:
                    continue
                remote_hex = parts[2].split(":")[0]
                ip = ".".join(str(b) for b in bytes.fromhex(remote_hex)[::-1])
                clients.append(ip)
    except OSError:
        pass
    return list(dict.fromkeys(clients))

def notify(title, body):
    clients = smb_clients()
    ip_line = "\n" + ", ".join(clients) if clients else "\nlocal"
    subprocess.Popen(["notify-send", "-u", "normal",
                      "-a", "Dolphin",
                      "--hint=string:desktop-entry:org.kde.dolphin",
                      title, body + ip_line],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

buf = b""
while True:
    try:
        buf += os.read(fd, 4096)
    except OSError:
        break

    while len(buf) >= HDR_SIZE:
        wd, mask, cookie, length = HEADER.unpack_from(buf)
        if len(buf) < HDR_SIZE + length:
            break
        name = buf[HDR_SIZE:HDR_SIZE + length].rstrip(b"\x00").decode(errors="replace")
        buf = buf[HDR_SIZE + length:]

        base = wd_to_path.get(wd)
        if base is None:
            continue

        full = base / name if name else base

        if mask & IN_ISDIR:
            if mask & IN_CREATE:
                add_recursive(full)
            continue

        if not name or name.startswith(".") or name.endswith("~"):
            continue

        try:
            rel = str(full.relative_to(watch_dir))
        except ValueError:
            rel = name

        if   mask & (IN_CREATE | IN_MOVED_TO):   notify("Public: New File",      rel)
        elif mask & (IN_DELETE | IN_MOVED_FROM):  notify("Public: File Deleted",  rel)
        elif mask & IN_CLOSE_WRITE:               notify("Public: File Written",  rel)
        elif mask & IN_ACCESS:                    notify("Public: File Read",     rel)
