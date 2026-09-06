#!/usr/bin/env bash
# statusline-model-call 安裝腳本
#
# 不走 CC 的 plugin 途徑（本工具沒有任何 plugin 元件，只有一個 statusLine 腳本，
# 而 statusLine 屬於 settings.json 層級，plugin manifest 本來就管不到）。
#
# 依 settings.json 現況分兩種安裝形態：
#   A. 沒人用 statusLine → command 直接指向 model-call.sh
#   B. 已有其他工具佔用 → 產生統一入口 statusline-wrapper.sh，
#      把對方的指令與本工具一併納入，command 改指向入口檔
set -e

NAME="statusline-model-call"
RAW_URL="https://raw.githubusercontent.com/ayii0111/statusline-model-call/main/statusline/model-call.sh"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
TOOL_DIR="$CLAUDE_DIR/$NAME"
TOOL_SH="$TOOL_DIR/model-call.sh"
WRAPPER="$CLAUDE_DIR/statusline-wrapper.sh"

BEGIN_MARK="# >>> $NAME >>>"
END_MARK="# <<< $NAME <<<"
SELF_CMD="bash \"$TOOL_SH\""

command -v jq >/dev/null 2>&1 || {
  echo "✗ 需要 jq，請先安裝（brew install jq）。" >&2
  exit 1
}

# 把字串包成單引號 shell literal（內部單引號轉義為 '\''）
squote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# ---- 1. 放置工具腳本 ----
# 本機有原始碼就用本機的，curl | bash 的情境則從 GitHub 抓。
SRC="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/statusline/model-call.sh"
mkdir -p "$TOOL_DIR"
if [ -f "$SRC" ]; then
  cp "$SRC" "$TOOL_SH"
else
  curl -fsSL "$RAW_URL" -o "$TOOL_SH" || {
    echo "✗ 無法取得 model-call.sh。" >&2
    exit 1
  }
fi
chmod +x "$TOOL_SH"
echo "· 已安裝腳本：$TOOL_SH"

# ---- 2. 讀取現況 ----
[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
PREV=$(jq -r '.statusLine.command // empty' "$SETTINGS")
cp "$SETTINGS" "$SETTINGS.bak-$NAME"

NEW_CMD=""

case "$PREV" in
  # 已經指向本工具 → 只是更新腳本，設定不動
  *"$NAME/model-call.sh"*)
    NEW_CMD="$PREV"
    echo "· statusLine 已指向本工具，僅更新腳本。"
    ;;

  # 已經指向統一入口 → 確保入口檔裡有本工具的區塊（可重入）
  *statusline-wrapper.sh*)
    NEW_CMD="$PREV"
    if [ -f "$WRAPPER" ] && grep -qF "$BEGIN_MARK" "$WRAPPER"; then
      echo "· 入口檔已含本工具，僅更新腳本。"
    else
      [ -f "$WRAPPER" ] || { echo "✗ command 指向 $WRAPPER 但檔案不存在。" >&2; exit 1; }
      {
        printf '\n%s\n' "$BEGIN_MARK"
        printf 'run %s\n' "$(squote "$SELF_CMD")"
        printf '%s\n' "$END_MARK"
      } >> "$WRAPPER"
      echo "· 已將本工具加入既有入口檔：$WRAPPER"
    fi
    ;;

  # 沒人用 statusLine → 直接指向本工具
  "")
    NEW_CMD="$SELF_CMD"
    echo "· statusLine 原本未使用，直接指向本工具。"
    ;;

  # 有其他工具佔用 → 建立統一入口，兩者並存
  *)
    cat > "$WRAPPER" <<'WRAPPER_HEAD'
#!/usr/bin/env bash
# statusline-wrapper —— statusLine 統一入口
#
# 每個工具一行 run '<指令>'，由上而下依序輸出，各自佔一列。
# stdin（CC 給的 statusLine JSON）只能讀一次，故先緩存再分別餵給每個工具。
#
# 帶 marker 的區塊由各工具的 install / uninstall 腳本自行維護，請勿手動編輯。

input=$(cat)
run() { printf '%s' "$input" | eval "$1"; }

WRAPPER_HEAD
    printf 'run %s\n' "$(squote "$PREV")" >> "$WRAPPER"
    {
      printf '\n%s\n' "$BEGIN_MARK"
      printf 'run %s\n' "$(squote "$SELF_CMD")"
      printf '%s\n' "$END_MARK"
    } >> "$WRAPPER"
    chmod +x "$WRAPPER"
    NEW_CMD="bash \"$WRAPPER\""
    echo "· 偵測到既有 statusLine，已建立統一入口：$WRAPPER"
    echo "  納入原指令：$PREV"
    ;;
esac

# ---- 3. 寫回 settings.json ----
# refreshInterval: 1 是 loading 動畫換格的驅動來源，不要調大。
TMP=$(mktemp)
jq --arg cmd "$NEW_CMD" \
   '.statusLine = { type: "command", command: $cmd, refreshInterval: 1 }' \
   "$SETTINGS" > "$TMP"
mv "$TMP" "$SETTINGS"

echo "✓ 安裝完成（原 settings.json 已備份為 settings.json.bak-${NAME}）。"
echo "  重啟 CC 或執行 /config 後即可看到。"
