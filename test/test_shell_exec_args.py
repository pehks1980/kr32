#!/usr/bin/env python3
"""End-to-end regression for quoted shell arguments passed to execve."""

from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from tempfile import TemporaryDirectory

from device.nsfs import NSFSStore
from tools.assembler import Assembler
from tools.preprocess_cmacros import Preprocessor
from vmp import CPU


def main():
    root = Path(__file__).resolve().parents[1]
    source = root / "kernelshed.asm"
    processed = Preprocessor(root).process(
        source.read_text(encoding="utf-8").splitlines()
    )

    with TemporaryDirectory() as tmpdir:
        image = Path(tmpdir) / "memory.img"
        assembler = Assembler()
        with redirect_stdout(StringIO()):
            assembler.build(processed, out=str(image))

        cpu = CPU()
        store = NSFSStore(Path(tmpdir) / "nsfs_store.json")
        cpu.bmi.nsfs = store
        command = (
            b'/bin/print "a=%s b=%d c=%b d=%s" "aaa" 1222 256 "ddd"\n'
            b"/bin/cp /bin/cat /cat1\n"
            b"/bin/cp /cat1 /aaa/cat\n"
        )
        cpu.uart.rx_fifo.extend(command)
        cpu.load_image(str(image))
        cpu.quiet = True

        with redirect_stdout(StringIO()):
            cpu.run(0, max_steps=8000000)

        output = bytes(cpu.uart.tx_output).decode("ascii", errors="replace")
        assert "a=aaa b=1222 c=100000000 d=ddd" in output, output

        def read_store_file(path):
            manifest = store.data["kv"][store._path_key(0, path)]
            contents = b"".join(
                store._read_chunk(0, chunk_id)
                for chunk_id in manifest["chunks"]
            )
            return manifest["size"], contents[:manifest["size"]]

        source_size, source_contents = read_store_file("/cat1")
        copied_size, copied_contents = read_store_file("/aaa/cat")
        assert source_size > 0
        assert (copied_size, copied_contents) == (source_size, source_contents), (
            source_size,
            copied_size,
            source_contents[:32],
            copied_contents[:32],
            output,
        )

    print("Shell exec argv regression test passed")


if __name__ == "__main__":
    main()