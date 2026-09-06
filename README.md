# statusline-model-call

A Claude Code statusLine add-on that reports, for the **most recent user prompt**, which capabilities the agent actually invoked.

```
~/cc-projects/new-pj ⬡ ▰▱▱▱▱▱▱▱▱▱ 7% ◆ Opus 5 ψ low 5h ▰▱▱▱▱▱▱▱▱▱ 6% ↺4h08m
⏵⏵ model-call  🔧 Bash×3 Read×2 │ 🎯 zsh-rule │ 🔌 claude_ai_Notion×2 │ 🤖 Explore │ 🪝 PreToolUse×3
```

新增的是**第二列**，你原本的 statusLine 完全不動 —— 安裝時會把它接在上面一行。

## 顯示內容

| 圖示 | 類別 | 來源 |
|---|---|---|
| 🔧 | 內建工具 | `tool_use` 名稱（排除 Skill / Agent / MCP） |
| 🎯 | skill 與 slash command | `Skill` 的 `input.skill`、prompt 中的 `<command-name>` |
| 🔌 | MCP server | `mcp__<server>__<tool>` 的 server 段 |
| 🤖 | subagent | `Agent` / `Task` 的 `subagent_type` |
| 🪝 | hook | transcript 中的 `hook_success` attachment |

重複的項目會聚合為 `名稱×次數`。沒有內容的區段整段不顯示。

agent 還沒走到 Stop 時，行尾會出現 loading 動畫（frame 序列取自
[molovo/revolver](https://github.com/molovo/revolver) 的 `simpleDots`）；
這一輪沒有任何工具紀錄時，動畫會顯示在 `⏵⏵ model-call` 後面原本 `-` 的位置。

## 已知限制

- **CLAUDE.md 規則的遵循與否無法偵測。** transcript 沒有任何對應訊號，這是資料面的限制，不是實作沒做。
- **plugin 只能半偵測。** 只有當 skill 名稱帶 plugin 前綴（如 `custom-skills:zsh-rule`）時才看得出來。
- 動畫換格由 `refreshInterval` 驅動，CC 的下限是 1 秒，所以比 revolver 原生的 0.4 秒慢一些。

## 安裝

```bash
git clone https://github.com/ayii0111/statusline-model-call
cd statusline-model-call
./install.sh
```

或

```bash
curl -fsSL https://raw.githubusercontent.com/ayii0111/statusline-model-call/main/install.sh | bash
```

需要 `jq`。安裝後重啟 CC 套用。

install.sh 會把腳本放到 `~/.claude/statusline-model-call/model-call.sh`，
接著依 `settings.json` 的現況分兩種形態接管 `statusLine`
（兩種都會先備份為 `settings.json.bak-statusline-model-call`）：

**A. 原本沒有 statusLine** —— `command` 直接指向本工具：

```json
"statusLine": { "type": "command", "command": "bash \"~/.claude/statusline-model-call/model-call.sh\"", "refreshInterval": 1 }
```

**B. 已有其他工具佔用 statusLine** —— 建立統一入口 `~/.claude/statusline-wrapper.sh`，
把對方的指令與本工具一併納入、各佔一列，`command` 改指向這個入口檔。
對方的功能完全不受影響：

```bash
input=$(cat)
run() { printf '%s' "$input" | eval "$1"; }

run 'bash "/path/to/your-original-statusline.sh"'

# >>> statusline-model-call >>>
run 'bash "/Users/you/.claude/statusline-model-call/model-call.sh"'
# <<< statusline-model-call <<<
```

重跑 install.sh 即為更新，兩種形態都可重入，不會重複寫入。

## 移除

```bash
./uninstall.sh
```

對應安裝時的兩種形態：

- **形態 A** —— 刪除腳本，並移除 `settings.json` 的 `statusLine` 欄位。
- **形態 B** —— **只**從入口檔裡刪掉本工具的 marker 區塊，入口檔本身與其他工具原封不動，
  `statusLine` 欄位維持指向入口檔。唯一例外：若移除後入口檔已無任何工具，
  留著只會讓 statusLine 變空白，此時會一併刪除入口檔並清空該欄位。

`config.sh` 是你自己的設定，一律保留不刪。

## 設定檔

install.sh 會在 `~/.claude/statusline-model-call/config.sh` 放一份設定檔，
**裡面所有項目預設都是註解**，拿掉 `#` 才生效，沒動就是本工具的預設行為。

它一旦存在，重跑 install.sh 更新時**不會**被覆蓋，uninstall 也不刪。

## 排除不想看的項目

有些工具（如 Orca）會註冊 hook 掛在每一次工具呼叫上，導致 🪝 區段長期被
`PreToolUse×13 PostToolUse×12` 這類雜訊佔滿。五個類別都可以各自排除：

```bash
EXCLUDE_HOOK=( ".orca/agent-hooks" )   # 🪝 比對「指令全文 + 事件名」
EXCLUDE_TOOL=( "TodoWrite" )           # 🔧 工具名
EXCLUDE_SKILL=( "artifact-design" )    # 🎯 skill 與 slash command 名
EXCLUDE_MCP=( "claude_ai_Notion" )     # 🔌 MCP server 名
EXCLUDE_AGENT=( "general-purpose" )    # 🤖 subagent 名
```

填的是**純關鍵字不是正則** —— 目標字串含有其中任一個就整筆略過，不用跳脫，
大小寫要一致。一個類別可填多個，任一命中即排除。

hook 之所以要比對「指令全文」，是因為 transcript 的 hook 紀錄沒有「誰註冊的」
這種欄位，但每筆都帶著它實際執行的指令，第三方工具的指令裡通常含有自己的
安裝路徑 —— 比對那段就能精準排掉，且不會誤傷同名事件底下你自己的 hook。

分類別而非單一全域清單，是為了避免誤殺：填 `Bash` 想擋 hook 時，不會連
🔧 的 Bash 一起消失。

排除發生在統計之前（逐筆篩掉），不是事後扣次數，混雜時也不會算錯。
某類別全被排光時，該區段整段不顯示，後面區段的顏色自動往前遞補。

## 自訂配色

一樣寫在 `config.sh`：

```bash
C_PREFIX="204;113;120"   # #CC7178 前綴
C_SPIN="189;237;224"     # #BDEDE0 loading 動畫
C_DIM="124;135;156"      # ×次數
C_SEP="76;86;106"        # 分隔線 │

# 色盤依「實際出現的區段順序」由前往後取用，不綁定類別。
# 例如只有 🔧 和 🪝 有內容時，🔧 取第 1 色、🪝 取第 2 色。
PALETTE=(
  "237;194;196"  # #EDC2C4
  "164;190;243"  # #A4BEF3
  "199;217;183"  # #C7D9B7
  "155;194;200"  # #9BC2C8
  "190;183;164"  # #BEB7A4
)

# loading 動畫；刪掉最後的空拍即成三格連續循環
SPINNER_FRAMES=(".  " ".. " "..." "   ")

# 設為 1 會輸出涵蓋全部五個類別的假資料，方便一次檢視所有顏色
FAKE_DEMO=0
```

## 為什麼不做成 CC plugin

CC plugin 的元件只涵蓋 `commands / agents / skills / hooks / mcpServers`，
`statusLine` 屬於 `settings.json` 層級，plugin manifest 管不到。
做成 plugin 等於掛一個零元件的空殼 manifest，還得反查 `known_marketplaces.json`
才能湊出 statusLine 需要的絕對路徑（`statusLine` 吃不到 `${CLAUDE_PLUGIN_ROOT}`），
而 directory source 形態下 `claude plugin update` 又形同無效。
換來的只有 marketplace 曝光，不划算，因此改為純腳本安裝：路徑固定、無需反查、不依賴 `claude` CLI。

## License

MIT
