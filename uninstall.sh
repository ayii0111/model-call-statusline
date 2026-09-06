#!/usr/bin/env bash
# statusline-model-call 移除腳本
#
# 對應安裝時的兩種形態：
#   A. command 直接指向本工具 → 刪腳本，並移除 statusLine 欄位
#   B. command 指向統一入口   → 只從入口檔裡刪掉本工具的 marker 區塊，
#      入口檔與其他工具原封不動
#
# 使用者自訂的 config.sh 一律保留。
set -e

NAME="statusline-model-call"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
TOOL_DIR="$CLAUDE_DIR/$NAME"
TOOL_SH="$TOOL_DIR/model-call.sh"
WRAPPER="$CLAUDE_DIR/statusline-wrapper.sh"

BEGIN_MARK="# >>> $NAME >>>"
END_MARK="# <<< $NAME <<<"

command -v jq >/dev/null 2>&1 || {
  echo "✗ 需要 jq。" >&2
  exit 1
}

PREV=""
[ -f "$SETTINGS" ] && PREV=$(jq -r '.statusLine.command // empty' "$SETTINGS")

# 是否要清掉 settings.json 的 statusLine 欄位
DROP_FIELD=0

case "$PREV" in
  *statusline-wrapper.sh*)
    if [ -f "$WRAPPER" ] && grep -qF "$BEGIN_MARK" "$WRAPPER"; then
      TMP=$(mktemp)
      sed "/^$BEGIN_MARK\$/,/^$END_MARK\$/d" "$WRAPPER" > "$TMP"
      mv "$TMP" "$WRAPPER"
      chmod +x "$WRAPPER"
      echo "· 已從入口檔移除本工具區塊：$WRAPPER"
    fi
    # 入口檔已無任何工具 → 留著只會讓 statusLine 變空白，一併清掉
    if [ -f "$WRAPPER" ] && ! grep -q '^run ' "$WRAPPER"; then
      rm -f "$WRAPPER"
      DROP_FIELD=1
      echo "· 入口檔已無其他工具，一併移除。"
    fi
    ;;
  *"$NAME/model-call.sh"*)
    DROP_FIELD=1
    ;;
esac

if [ "$DROP_FIELD" = 1 ] && [ -f "$SETTINGS" ]; then
  TMP=$(mktemp)
  jq 'del(.statusLine)' "$SETTINGS" > "$TMP"
  mv "$TMP" "$SETTINGS"
  echo "· 已移除 settings.json 的 statusLine 欄位。"
fi

# config.sh 是使用者自己的配色覆寫，保留不刪；目錄空了才移除。
rm -f "$TOOL_SH"
if rmdir "$TOOL_DIR" 2>/dev/null; then
  echo "· 已移除 $TOOL_DIR"
elif [ -d "$TOOL_DIR" ]; then
  printf '· 保留 %s （內有你的 config.sh）\n' "$TOOL_DIR"
fi

echo "✓ 已移除 ${NAME}。重啟 CC 套用。"
