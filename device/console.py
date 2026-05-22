import fcntl
import os
import pty
import select
import shlex
import shutil
import subprocess
import sys


class ConsoleDevice:
    """Host-backed console device for KR32 emulator.

    The guest kernel uses a simple console device table entry with
    read/write function pointers. The emulator intercepts those
    guest handler entry addresses and forwards I/O to this class.
    """

    def __init__(self, input_source=None, output_sink=None, dedicated_window=False):
        self.input_source = input_source or sys.stdin.buffer
        self.output_sink = output_sink or sys.stdout.buffer
        self.pending_input = b""
        self.dedicated_window = dedicated_window
        self.master_fd = None
        self.slave_fd = None
        self.slave_name = None

        if self.dedicated_window:
            self._create_pty()
            self._open_dedicated_window()

    def reset(self):
        self.pending_input = b""

    def _create_pty(self):
        self.master_fd, self.slave_fd = pty.openpty()
        self.slave_name = os.ttyname(self.slave_fd)
        # Keep master FD blocking so writes don't get partially written.
        # Some systems default to blocking; avoid forcing non-blocking here.
        try:
            flags = fcntl.fcntl(self.master_fd, fcntl.F_GETFL)
            if flags & os.O_NONBLOCK:
                fcntl.fcntl(self.master_fd, fcntl.F_SETFL, flags & ~os.O_NONBLOCK)
        except Exception:
            # If we can't change flags, proceed — we'll handle partial writes below.
            pass

    def _open_dedicated_window(self):
        if sys.platform == "darwin":
            self._open_dedicated_window_mac()
        elif shutil.which("xterm"):
            self._open_dedicated_window_xterm()
        else:
            print("[CONSOLE] dedicated terminal window unsupported on this platform")

    def _open_dedicated_window_mac(self):
        python_exe = shlex.quote(sys.executable)
        script_path = shlex.quote(os.path.abspath(__file__))
        slave_path = shlex.quote(self.slave_name)
        cmd = f"{python_exe} {script_path} pty_bridge {slave_path}"
        applescript = (
            'tell application "Terminal"\n'
            '    activate\n'
            f'    do script "{cmd}"\n'
            'end tell'
        )
        try:
            subprocess.Popen(["osascript", "-e", applescript])
        except Exception:
            print("[CONSOLE] failed to open dedicated Terminal window")

    def _open_dedicated_window_xterm(self):
        python_exe = shlex.quote(sys.executable)
        script_path = shlex.quote(os.path.abspath(__file__))
        slave_path = shlex.quote(self.slave_name)
        cmd = f"{python_exe} {script_path} pty_bridge {slave_path}"
        subprocess.Popen(["xterm", "-e", cmd])

    def read(self, cpu, paddr, length):
        if length <= 0:
            return 0

        if self.dedicated_window:
            if self.pending_input and b"\n" in self.pending_input:
                newline_pos = self.pending_input.index(b"\n") + 1
                chunk = self.pending_input[: min(newline_pos, length)]
            else:
                while True:
                    try:
                        ready, _, _ = select.select([self.master_fd], [], [])
                    except Exception:
                        return 0
                    if not ready:
                        continue
                    try:
                        data = os.read(self.master_fd, 4096)
                    except BlockingIOError:
                        continue
                    except OSError:
                        return 0
                    if not data:
                        return 0
                    self.pending_input += data
                    if b"\n" in self.pending_input or len(self.pending_input) >= length:
                        break
                newline_pos = self.pending_input.find(b"\n")
                if newline_pos >= 0:
                    chunk = self.pending_input[: min(newline_pos + 1, length)]
                else:
                    chunk = self.pending_input[:length]

            count = len(chunk)
            if count == 0:
                return 0
            cpu.check_physical_mem(paddr, count)
            cpu.physical_memory[paddr:paddr + count] = chunk
            self.pending_input = self.pending_input[count:]
            return count

        if not self.pending_input:
            try:
                data = self.input_source.readline()
            except Exception:
                data = b""
            if data is None:
                data = b""
            if isinstance(data, str):
                data = data.encode("utf-8", errors="replace")
            self.pending_input = data

        if b"\n" in self.pending_input:
            newline_pos = self.pending_input.index(b"\n") + 1
            chunk = self.pending_input[: min(newline_pos, length)]
        else:
            chunk = self.pending_input[:length]

        count = len(chunk)
        if count > 0:
            cpu.check_physical_mem(paddr, count)
            cpu.physical_memory[paddr:paddr + count] = chunk
            self.pending_input = self.pending_input[count:]
        return count

    def write(self, cpu, paddr, length):
        cpu.check_physical_mem(paddr, length)
        data = bytes(cpu.physical_memory[paddr:paddr + length])
        if self.dedicated_window:
            # Log the exact bytes we will write to the PTY master for diagnosis
            try:
                hexpart = " ".join(f"{b:02x}" for b in data[:64])
                preview = data[:64].decode("utf-8", errors="replace")
                print(f"[CONSOLE MASTER WRITE] len={len(data)} data={hexpart} preview={preview!r}")
            except Exception:
                pass
            total = 0
            L = len(data)
            while total < L:
                try:
                    n = os.write(self.master_fd, data[total:])
                except BlockingIOError:
                    continue
                except InterruptedError:
                    continue
                except Exception:
                    break
                if n is None or n == 0:
                    break
                total += n
            return total
        try:
            self.output_sink.write(data)
            self.output_sink.flush()
        except Exception:
            pass
        return length


def _run_pty_bridge(slave_name):
    try:
        slave_fd = os.open(slave_name, os.O_RDWR)
    except Exception:
        return

    try:
        while True:
            rlist, _, _ = select.select([sys.stdin.fileno(), slave_fd], [], [])
            if sys.stdin.fileno() in rlist:
                data = os.read(sys.stdin.fileno(), 1024)
                if not data:
                    break
                os.write(slave_fd, data)
            if slave_fd in rlist:
                data = os.read(slave_fd, 1024)
                if not data:
                    break
                os.write(sys.stdout.fileno(), data)
    finally:
        os.close(slave_fd)


if __name__ == "__main__" and len(sys.argv) >= 3 and sys.argv[1] == "pty_bridge":
    _run_pty_bridge(sys.argv[2])
