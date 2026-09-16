#!/usr/bin/env python3
"""把个人配置里写着的键，覆盖到系统正在用的那份配置上。没写的键一律不碰。

用法：
    apply-personal.py <个人配置> <系统配置>

个人配置就是普通的 KDE 配置文件，格式和系统那份一样，只是只留你关心的键。
段和键在系统那份里已经有的就地改值；没有的就补上（段也会补）。
两边的顺序、空行、注释都保持原样，只动该动的那几行。

"""

import sys
from pathlib import Path

def read(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    for line in lines:
        if line.rstrip().endswith("\\"):
            raise SystemExit(
                "错误：%s 里有续行（行尾反斜杠），这个脚本不敢动，先手工处理" % path
            )
    return lines

def sections_of(lines: list[str]) -> dict[str, tuple[int, int, dict[str, int]]]:
    """段名 -> (标题行下标, 段尾插入点, {键: 行下标})"""
    heads: list[tuple[str, int]] = []
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            heads.append((s[1:-1], i))

    out: dict[str, tuple[int, int, dict[str, int]]] = {}
    for n, (name, start) in enumerate(heads):
        stop = heads[n + 1][1] if n + 1 < len(heads) else len(lines)
        keys: dict[str, int] = {}
        for i in range(start + 1, stop):
            s = lines[i].strip()
            if s and not s.startswith(("#", ";")) and "=" in s:
                keys.setdefault(s.partition("=")[0], i)
        insert_at = stop
        while insert_at > start + 1 and not lines[insert_at - 1].strip():
            insert_at -= 1
        out[name] = (start, insert_at, keys)
    return out

def parse_personal(lines: list[str]) -> list[tuple[str, list[tuple[str, str]]]]:
    """读个人配置 -> [(段名, [(键, 值)])]，注释和空行丢掉。"""
    out: list[tuple[str, list[tuple[str, str]]]] = []
    cur: list[tuple[str, str]] | None = None
    for line in lines:
        s = line.strip()
        if not s or s.startswith(("#", ";")):
            continue
        if s.startswith("[") and s.endswith("]"):
            cur = []
            out.append((s[1:-1], cur))
        elif cur is not None and "=" in s:
            key, _, value = s.partition("=")
            cur.append((key, value))
    return [(name, kv) for name, kv in out if kv]

def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    src_path, dst_path = (Path(a) for a in argv)
    want = parse_personal(read(src_path))
    lines = read(dst_path)
    have = sections_of(lines)

    edits: list[tuple[int, str | None]] = []
    inserts: dict[int, list[str]] = {}
    changes = added = 0

    for name, kv in want:
        if name not in have:
            block = [""] + ["[%s]" % name] + ["%s=%s" % (k, v) for k, v in kv]
            inserts.setdefault(len(lines), []).extend(block)
            added += len(kv)
            continue

        _, insert_at, keys = have[name]
        pos = insert_at
        for key, value in kv:
            if key in keys:
                if lines[keys[key]].strip() != "%s=%s" % (key, value):
                    edits.append((keys[key], "%s=%s" % (key, value)))
                    changes += 1
            else:
                inserts.setdefault(pos, []).append("%s=%s" % (key, value))
                pos += 1
                added += 1

    for index in sorted(inserts, reverse=True):
        edits.append((index, None))

    for index, newline in sorted(edits, key=lambda e: -e[0]):
        if newline is None:
            lines[index:index] = inserts[index]
        else:
            lines[index] = newline

    if not (changes or added):
        print("  没有要改的键")
        return 0

    dst_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("  改了 %s 个键的值，补了 %s 个键" % (changes, added))
    return 0

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
