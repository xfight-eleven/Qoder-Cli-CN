#!/usr/bin/env bash
# qodercn-acp-zed — detect Qoder CLI CN, verify ACP, optionally write Zed config.
set -euo pipefail

ENTRY_NAME="Qoder CLI CN"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

WRITE=0
CHECK_ACP=0
BIN=""

usage() {
  cat <<'USAGE'
用法: ./install.sh [选项]

  --write        备份后直接写入 Zed 的 settings.json（默认只探测并打印片段）
  --check-acp    额外做一次 ACP initialize 握手测试
  --bin PATH     指定 qodercn 可执行文件路径
  -h, --help     显示本帮助
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --write) WRITE=1 ;;
    --check-acp) CHECK_ACP=1 ;;
    --bin)
      shift
      BIN=${1:-}
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

die() {
  printf '错误: %s\n' "$*" >&2
  exit 1
}

case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux) OS=linux ;;
  MINGW*|MSYS*|CYGWIN*)
    cat >&2 <<'MSG'
本脚本只支持 macOS / Linux。
Windows 请手动编辑 %APPDATA%\Zed\settings.json，内容参考 examples/snippet-windows.json；
先运行 `where qodercn` 确认真实可执行路径。
MSG
    exit 1
    ;;
  *) OS=unknown ;;
esac

# ---------- 定位 qodercn ----------
if [ -z "$BIN" ]; then
  for cand in "$HOME/.qoder-cn/entry/qodercn" "$HOME/.local/bin/qodercn"; do
    if [ -x "$cand" ]; then
      BIN=$cand
      break
    fi
  done
fi
if [ -z "$BIN" ]; then
  BIN=$(command -v qodercn 2>/dev/null || true)
fi
if [ -z "$BIN" ]; then
  die "找不到 qodercn，请先安装 Qoder CLI CN（https://docs.qoder.cn/cli），或用 --bin 指定路径"
fi
[ -f "$BIN" ] || die "不是文件: $BIN"
[ -x "$BIN" ] || die "没有执行权限: $BIN"
case "$BIN" in
  /*) ;;
  *)
    _dir=$(cd "$(dirname "$BIN")" && pwd)
    BIN="$_dir/$(basename "$BIN")"
    ;;
esac

VER=$("$BIN" --version 2>&1 | head -n 1 || true)
printf '✓ qodercn: %s\n' "$BIN"
if [ -n "${VER:-}" ]; then
  printf '✓ 版本: %s\n' "$VER"
fi

# ---------- 定位 Zed 配置 ----------
if [ -n "${ZED_SETTINGS:-}" ]; then
  SETTINGS=$ZED_SETTINGS
elif [ -n "${XDG_CONFIG_HOME:-}" ]; then
  SETTINGS=$XDG_CONFIG_HOME/zed/settings.json
else
  SETTINGS=$HOME/.config/zed/settings.json
fi
printf '✓ Zed 配置: %s\n' "$SETTINGS"

HAS_ENTRY=0
if [ -f "$SETTINGS" ] && grep -q "\"$ENTRY_NAME\"" "$SETTINGS"; then
  HAS_ENTRY=1
  printf '! 配置里已有 "%s" 条目\n' "$ENTRY_NAME"
fi

# ---------- 片段 ----------
printf '\n把下面这段合并进 settings.json 的 "agent_servers"：\n\n'
printf '  "%s": {\n    "type": "custom",\n    "command": "%s",\n    "args": ["--acp"]\n  }\n\n' "$ENTRY_NAME" "$BIN"

if [ "$OS" != unknown ]; then
  if ! env -i PATH=/usr/local/bin:/usr/bin:/bin sh -c 'command -v qodercn' >/dev/null 2>&1; then
    printf '! qodercn 不在系统默认 PATH 中（Zed 从桌面启动时同样看不到它），所以上面必须用绝对路径。\n\n'
  fi
fi

# ---------- 可选：ACP 握手 ----------
with_timeout() {
  _secs=$1
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$_secs" "$@"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$_secs" "$@"
    return $?
  fi
  "$@" &
  _pid=$!
  ( sleep "$_secs"; kill -9 "$_pid" 2>/dev/null ) >/dev/null 2>&1 &
  _wd=$!
  _rc=0
  wait "$_pid" || _rc=$?
  kill "$_wd" 2>/dev/null || true
  return "$_rc"
}

if [ "$CHECK_ACP" = 1 ]; then
  REQ='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{"fs":{"readTextFile":true,"writeTextFile":true}}}}'
  TMP=$(mktemp 2>/dev/null || echo "/tmp/qodercn-acp-$$")
  printf '%s\n' "$REQ" >"$TMP"
  OUT=$(with_timeout 40 "$BIN" --acp <"$TMP" 2>&1 || true)
  rm -f "$TMP"
  case "$OUT" in
    *'"agentInfo"'*)
      printf '✓ ACP 握手成功: %s\n\n' "$(printf '%s' "$OUT" | head -c 240)"
      ;;
    *)
      printf '✗ ACP 握手失败，输出:\n%s\n' "$OUT" >&2
      exit 1
      ;;
  esac
fi

# ---------- 可选：写入 ----------
if [ "$WRITE" = 1 ]; then
  if [ "$HAS_ENTRY" = 1 ]; then
    printf '已存在 "%s" 条目，跳过写入。\n' "$ENTRY_NAME"
    exit 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    die "写入需要 python3（用于保留注释地修改 JSON）；也可按上面的片段手动编辑"
  fi
  python3 "$SCRIPT_DIR/scripts/patch_settings.py" \
    --settings "$SETTINGS" \
    --command "$BIN" \
    --name "$ENTRY_NAME"
fi
