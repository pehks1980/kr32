#!/usr/bin/env python3
"""Guard the special-device registry so /dev/null does not share console ops."""

import re
from pathlib import Path


def test_dev_null_uses_null_ops():
    source = Path(__file__).resolve().parents[1] / "kernelshed.asm"
    text = source.read_text(encoding="utf-8")

    match = re.search(
        r"dev_null:\n(?:.*\n){0,8}    \.WORD dev_null_name\n    \.WORD ([A-Za-z0-9_]+)\n    \.WORD null_device",
        text,
    )
    assert match is not None, "missing /dev/null registry entry"
    assert match.group(1) == "null_ops", (
        f"/dev/null should use null_ops, not {match.group(1)}"
    )

    assert "null_ops:" in text, "null_ops table is missing"
    assert "dev_console_ops:" in text, "console ops table is missing"


if __name__ == "__main__":
    test_dev_null_uses_null_ops()
    print("/dev/null device registry regression test passed")
