#!/usr/bin/env python3
"""占位解析器：将输入文件原样输出，便于后续替换为微信/QQ 解析逻辑。"""
import sys
from pathlib import Path


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
