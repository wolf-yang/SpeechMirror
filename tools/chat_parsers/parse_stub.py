#!/usr/bin/env python3
"""与 assets/tools/parse_stub.py 相同，便于在开发机直接运行测试。"""
from pathlib import Path
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print("", end="")
        return 0
    p = Path(sys.argv[1])
    if not p.exists():
        print("", end="")
        return 0
    print(p.read_text(encoding="utf-8", errors="ignore"), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
