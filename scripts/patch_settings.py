#!/usr/bin/env python3
"""把 Zed 的 custom agent 条目插入 settings.json，尽量保留原有注释与格式。"""

import argparse
import json
import re
import shutil
import sys
import time
from pathlib import Path

DEFAULT_ARGS = ["--acp"]


def scan(text):
    """返回 (去注释后的文本, 最后一个“有意义”字符的下标)。"""
    out = []
    i = 0
    n = len(text)
    in_str = False
    esc = False
    last = -1
    while i < n:
        ch = text[i]
        if in_str:
            out.append(ch)
            last = i
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            i += 1
            continue
        if ch == '"':
            in_str = True
            out.append(ch)
            last = i
            i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(ch)
        if not ch.isspace():
            last = i
        i += 1
    return "".join(out), last


def parses(text):
    try:
        json.loads(re.sub(r",(\s*[}\]])", r"\1", scan(text)[0]))
    except Exception:
        return False
    return True


def line_indent(text, pos):
    start = text.rfind("\n", 0, pos) + 1
    match = re.match(r"[ \t]*", text[start:])
    return match.group(0) if match else ""


def entry_lines(name, command, entry_indent, inner_indent):
    return (
        f'{entry_indent}{json.dumps(name, ensure_ascii=False)}: {{\n'
        f'{inner_indent}"type": "custom",\n'
        f'{inner_indent}"command": {json.dumps(command, ensure_ascii=False)},\n'
        f'{inner_indent}"args": {json.dumps(DEFAULT_ARGS)}\n'
        f"{entry_indent}}}"
    )


def insert_into_existing(text, name, command):
    match = re.search(r'"agent_servers"\s*:\s*\{', text)
    if not match:
        return None
    base = line_indent(text, match.start())
    body = entry_lines(name, command, base + "  ", base + "    ")

    j = match.end()
    while j < len(text) and text[j] in " \t\r\n":
        j += 1
    if j < len(text) and text[j] == "}":
        block = f"\n{body}\n{base}"
    else:
        block = f"\n{body},"
    return text[: match.end()] + block + text[match.end():]


def insert_new_section(text, name, command):
    close = text.rfind("}")
    if close == -1:
        return None
    head = text[:close]
    _, last = scan(head)
    # 逗号插在最后一个 token 之后，避免落进行尾注释里
    if last >= 0 and head[last] not in "{,":
        head = head[: last + 1] + "," + head[last + 1:]
    close_indent = line_indent(text, close)
    prop_indent = line_indent(head, last) if last >= 0 else ""
    if not prop_indent:
        prop_indent = close_indent + "  "
    body = entry_lines(name, command, prop_indent + "  ", prop_indent + "    ")
    block = (
        f'{prop_indent}"agent_servers": {{\n'
        f"{body}\n"
        f"{prop_indent}}}\n"
        f"{close_indent}"
    )
    return head.rstrip() + "\n" + block + text[close:]


def main():
    parser = argparse.ArgumentParser(description="insert a custom agent entry into Zed settings.json")
    parser.add_argument("--settings", required=True, help="settings.json 路径")
    parser.add_argument("--command", required=True, help="qodercn 的绝对路径")
    parser.add_argument("--name", default="Qoder CLI CN", help="agent 显示名称")
    parser.add_argument("--dry-run", action="store_true", help="只打印结果不写文件")
    args = parser.parse_args()

    path = Path(args.settings).expanduser()
    if path.exists():
        original = path.read_text(encoding="utf-8")
    else:
        original = "{\n}\n"
        path.parent.mkdir(parents=True, exist_ok=True)

    if re.search(r'"%s"\s*:' % re.escape(args.name), original):
        print(f'已存在 "{args.name}" 条目，跳过。')
        return 0

    patched = insert_into_existing(original, args.name, args.command)
    if patched is None:
        patched = insert_new_section(original, args.name, args.command)
    if patched is None:
        print("无法定位插入点，请手动编辑 settings.json。", file=sys.stderr)
        return 1
    if not parses(patched):
        print("插入后 JSON 校验失败，已放弃修改。结果如下：", file=sys.stderr)
        print(patched, file=sys.stderr)
        return 1

    if args.dry_run:
        print(patched)
        return 0

    if path.exists():
        backup = path.with_name(f"{path.name}.bak.{time.strftime('%Y%m%d-%H%M%S')}")
        shutil.copy2(path, backup)
        print(f"已备份: {backup}")
    path.write_text(patched, encoding="utf-8")
    print(f'已写入 "{args.name}" -> {path}')
    print("Zed 会自动重载配置，在 Agent Panel 新建线程即可选择该 agent。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
