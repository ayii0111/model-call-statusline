#!/usr/bin/env bash
# model-call —— Claude Code statusLine 附加列
#
# 顯示「最近一輪 user prompt」所觸發的：
#   🔧 內建工具 / 🎯 skill + slash command / 🔌 MCP / 🤖 subagent / 🪝 hook
# agent 尚未走到 Stop 時，行尾（或無資料時的原位）顯示 loading 動畫。
#
# stdin : Claude Code 的 statusLine JSON
# stdout: 一行 "⏵⏵ model-call  ..."（無資料時為 "⏵⏵ model-call  -"）

# ============================================================
# 使用者設定檔（可選）
# ~/.claude/statusline-model-call/config.sh 若存在會被載入，
# 可覆寫下方任何一個變數，重跑 install.sh 更新時不會被蓋掉。
# ============================================================
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
USER_CONFIG="$CLAUDE_DIR/statusline-model-call/config.sh"

# ============================================================
# 配色（"R;G;B" truecolor）
# ============================================================
C_PREFIX="204;113;120"   # #CC7178 玫瑰 — 前綴 ⏵⏵ model-call
C_SPIN="189;237;224"     # #BDEDE0 薄荷 — loading 動畫
C_DIM="124;135;156"      # 暗灰       — ×次數
C_SEP="76;86;106"        # 更暗       — 分隔線 │

# 色盤：不綁定特定類別，而是「依實際出現的區段順序」由前往後取用。
# 例如只有 🔧 和 🪝 有內容時，🔧 取第 1 色、🪝 取第 2 色。
PALETTE=(
  "237;194;196"  # #EDC2C4 淡粉
  "164;190;243"  # #A4BEF3 霧藍
  "199;217;183"  # #C7D9B7 淡綠
  "155;194;200"  # #9BC2C8 霧青
  "190;183;164"  # #BEB7A4 灰卡其
)

# loading frame 序列，取自 revolver (molovo/revolver) 的 "simpleDots"：
#   'simpleDots' '0.4 ".  " ".. " "..." "   "'
# revolver 本身是背景常駐進程、自行往終端寫入，無法用於 statusline
# （statusline 每次被呼叫只輸出一行靜態文字），故此處沿用它的 frame，
# 由 statusLine 的 refreshInterval 驅動換格。
# 不想要第 4 格空拍的話，把最後一個 "   " 刪掉即成三格連續循環。
SPINNER_FRAMES=(".  " ".. " "..." "   ")

# FAKE_DEMO=1 會忽略真實 transcript，輸出一行涵蓋全部五個類別的假資料，
# 用來檢視配色；調完改回 0。
FAKE_DEMO=0

# ============================================================
# 排除規則（關鍵字陣列；空陣列 = 不排除）
#
# 每個類別各自一份清單，填入的是「純關鍵字」不是正則 —— 只要目標字串
# 含有其中任一個關鍵字就整筆略過。不需要跳脫，寫什麼就比對什麼。
#
# 分類別而非單一全域清單，是為了避免誤殺：填 "Bash" 想擋 hook 時，
# 不會連 🔧 的 Bash 一起消失。
#
# 排除發生在統計之前（逐筆篩掉），不是事後扣次數，混雜時也不會算錯。
# 某類別全被排光時，該區段整段不顯示，後面區段的顏色自動往前遞補。
#
# 實際填法見 config.sh。
# ============================================================
EXCLUDE_HOOK=()    # 🪝 比對 hook 的「指令全文 + 事件名」
EXCLUDE_TOOL=()    # 🔧 比對工具名，如 "TodoWrite"
EXCLUDE_SKILL=()   # 🎯 比對 skill 名與 slash command 名
EXCLUDE_MCP=()     # 🔌 比對 MCP server 名，如 "claude_ai_Notion"
EXCLUDE_AGENT=()   # 🤖 比對 subagent 名，如 "Explore"

# shellcheck source=/dev/null
[ -f "$USER_CONFIG" ] && . "$USER_CONFIG"

# ============================================================

fallback() {
  printf '\033[38;2;%sm⏵⏵ model-call\033[0m  \033[38;2;%sm-\033[0m\n' "$C_PREFIX" "$C_DIM"
}

command -v jq >/dev/null 2>&1 || { fallback; exit 0; }

FAKE_TRANSCRIPT='{"type":"user","message":{"role":"user","content":"demo"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"},{"type":"tool_use","name":"Bash"},{"type":"tool_use","name":"Bash"},{"type":"tool_use","name":"Read"},{"type":"tool_use","name":"Read"},{"type":"tool_use","name":"Edit"},{"type":"tool_use","name":"WebSearch"},{"type":"tool_use","name":"Skill","input":{"skill":"zsh-rule"}},{"type":"tool_use","name":"Skill","input":{"skill":"code-review"}},{"type":"tool_use","name":"mcp__claude_ai_Notion__notion-search"},{"type":"tool_use","name":"mcp__claude_ai_Notion__notion-fetch"},{"type":"tool_use","name":"Agent","input":{"subagent_type":"Explore"}},{"type":"tool_use","name":"Agent","input":{"subagent_type":"Plan"}}]}}
{"type":"attachment","attachment":{"type":"hook_success","hookName":"PreToolUse:Bash"}}
{"type":"attachment","attachment":{"type":"hook_success","hookName":"PreToolUse:Read"}}
{"type":"attachment","attachment":{"type":"hook_success","hookName":"PreToolUse:Edit"}}
{"type":"attachment","attachment":{"type":"hook_success","hookName":"PostToolUse:Bash"}}
{"type":"attachment","attachment":{"type":"hook_success","hookName":"Stop"}}'

input=$(cat)
TRANSCRIPT=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

if [ "$FAKE_DEMO" != "1" ] && { [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; }; then
  fallback
  exit 0
fi

if [ "$FAKE_DEMO" = "1" ]; then
  JQ_INPUT=(); JQ_STDIN="$FAKE_TRANSCRIPT"
else
  JQ_INPUT=("$TRANSCRIPT"); JQ_STDIN=""
fi

PALETTE_JSON=$(printf '%s\n' "${PALETTE[@]}" | jq -Rs 'split("\n") | map(select(length > 0))')

# bash 陣列 → JSON 陣列（空陣列會得到 []）
to_json_array() { printf '%s\n' "$@" | jq -Rs 'split("\n") | map(select(length > 0))'; }
EX_HOOK_JSON=$(to_json_array "${EXCLUDE_HOOK[@]}")
EX_TOOL_JSON=$(to_json_array "${EXCLUDE_TOOL[@]}")
EX_SKILL_JSON=$(to_json_array "${EXCLUDE_SKILL[@]}")
EX_MCP_JSON=$(to_json_array "${EXCLUDE_MCP[@]}")
EX_AGENT_JSON=$(to_json_array "${EXCLUDE_AGENT[@]}")
SPINNER_FRAME="${SPINNER_FRAMES[$(( $(date +%s) % ${#SPINNER_FRAMES[@]} ))]}"

render() {
jq -rs \
  --arg     c_prefix "$C_PREFIX" \
  --arg     c_dim    "$C_DIM" \
  --arg     c_sep    "$C_SEP" \
  --arg     c_spin   "$C_SPIN" \
  --arg     spinner  "$SPINNER_FRAME" \
  --argjson palette   "$PALETTE_JSON" \
  --argjson ex_hook   "$EX_HOOK_JSON" \
  --argjson ex_tool   "$EX_TOOL_JSON" \
  --argjson ex_skill  "$EX_SKILL_JSON" \
  --argjson ex_mcp    "$EX_MCP_JSON" \
  --argjson ex_agent  "$EX_AGENT_JSON" \
  '
  # ---- 排除判定：輸入字串含有清單中任一關鍵字即為 true ----
  # 關鍵字必須先綁成 $k：直接寫 contains(.) 的話，. 會被前面的 $s| 重新綁定
  # 成待比對字串本身，變成「自己包含自己」而永遠成立。
  def excluded($list): . as $s | any($list[]; . as $k | $s | contains($k));

  # ---- 只看主線（排除 subagent 內部的 sidechain 訊息）----
  map(select(.isSidechain != true))

  # ---- 找出最後一筆「真正的 user prompt」的索引 ----
  # 條件: type=user、非 meta、content 不是 tool_result 回填
  | (to_entries
     | map(select(
         .value.type == "user"
         and (.value.isMeta != true)
         and (
           (.value.message.content | type) == "string"
           or ((.value.message.content // []) | type) == "array"
              and ((.value.message.content // []) | map(select(.type == "tool_result")) | length) == 0
         )
       ))
     | last | .key // 0) as $start

  # ---- 判斷這一輪是否仍在進行（尚未走到 Stop）----
  # 最後一筆對話訊息若是 user（剛送出 prompt，或工具結果剛回填），
  # 或是帶 tool_use 的 assistant（工具正在跑），都代表 agent 還沒收工。
  | ((map(select(.type == "user" or .type == "assistant")) | last) as $tail
     | ($tail.type == "user")
       or ($tail.type == "assistant"
           and (($tail.message.content // []) | any(.type == "tool_use")))
    ) as $running

  # ---- 取該 prompt 之後的所有事件 ----
  | .[$start:]

  # ---- 分類蒐集 ----
  | {
      builtin: [ .[] | select(.type=="assistant")
                 | (.message.content // [])[]
                 | select(.type=="tool_use")
                 | select(.name | startswith("mcp__") | not)
                 | select(.name != "Skill" and .name != "Agent" and .name != "Task")
                 | .name
                 | select(excluded($ex_tool) | not) ],

      mcp: [ .[] | select(.type=="assistant")
             | (.message.content // [])[]
             | select(.type=="tool_use")
             | select(.name | startswith("mcp__"))
             | (.name | split("__") | .[1])
             | select(excluded($ex_mcp) | not) ],

      skill: [ .[] | select(.type=="assistant")
               | (.message.content // [])[]
               | select(.type=="tool_use" and .name=="Skill")
               | (.input.skill // "?")
               | select(excluded($ex_skill) | not) ],

      cmd: [ .[] | select(.type=="user")
             | (if (.message.content|type)=="string"
                then .message.content
                else ((.message.content // []) | map(select(.type=="text") | .text) | join(" "))
                end)
             | capture("<command-name>/?(?<n>[^<]+)</command-name>"; "g")
             | .n
             | select(excluded($ex_skill) | not) ],

      agent: [ .[] | select(.type=="assistant")
               | (.message.content // [])[]
               | select(.type=="tool_use" and (.name=="Agent" or .name=="Task"))
               | (.input.subagent_type // "general-purpose")
               | select(excluded($ex_agent) | not) ],

      # hook 沒有「誰註冊的」欄位，但每筆都帶 command（該 hook 執行的指令全文），
      # 第三方工具的指令通常含自己的路徑，比對它即可精準排除。
      # 關鍵字同時比對指令全文與事件名，兩者任一含有即排除；欄位缺漏一律 // "" 保底。
      # hook_ 開頭的 attachment 有兩種語意不同的東西：
      #   hook_success        —— 執行紀錄（真的跑了一次）
      #   hook_system_message —— 該次執行要求顯示的訊息，供歷史重播用
      # 兩者成對出現，只認執行紀錄，否則凡是會吐 systemMessage 的 hook
      # 次數都會被灌成兩倍（例如 ccc-divider 的分隔線）。
      # 用排除法而非白名單，是為了讓未來新增的失敗／阻擋類事件仍算得到。
      hook: [ .[] | select(.type=="attachment")
              | select((.attachment.type // "") as $t
                       | ($t | startswith("hook_")) and $t != "hook_system_message")
              | select((((.attachment.command // "") + " " + (.attachment.hookName // ""))
                        | excluded($ex_hook)) | not)
              | (.attachment.hookName // "?" | split(":")[0]) ]
    }

  # ---- 上色 ----
  # $c = 名稱色；次數與分隔線用暗灰，避免搶眼
  | def paint($c): "[38;2;\($c)m" + . + "[0m";
    def dim: paint($c_dim);

  # ---- 聚合成 "名稱×次數"（次數為 1 時省略）----
    def tally($c): group_by(.)
      | map((.[0] | paint($c)) + (if length > 1 then ("×\(length)" | dim) else "" end))
      | join(" ");

  # ---- 區段順序固定，但顏色不綁類別 ----
  # 先濾掉空區段，剩下的再依序由 $palette 由前往後取色。
    [
      { emoji: "🔧", items: .builtin        },
      { emoji: "🎯", items: (.skill + .cmd) },
      { emoji: "🔌", items: .mcp            },
      { emoji: "🤖", items: .agent          },
      { emoji: "🪝", items: .hook           }
    ]
    | map(select(.items | length > 0))
    | to_entries
    | map(. as $seg
          | $seg.value.emoji + " "
            + ($seg.value.items | tally($palette[$seg.key % ($palette | length)])))
    | join(" " + ("│" | paint($c_sep)) + " ")

  # ---- 收尾：進行中就掛上 loading 動畫 ----
  # 有工具紀錄時動畫接在後面，還沒有紀錄時動畫取代原本的 "-"。
    | (if $running then ($spinner | paint($c_spin)) else "" end) as $spin
    | (if length > 0
       then . + (if $running then " " + $spin else "" end)
       else (if $running then $spin else ("-" | dim) end)
       end)
    | ("⏵⏵ model-call" | paint($c_prefix)) + "  " + .
' "${JQ_INPUT[@]}"
}

if [ -n "$JQ_STDIN" ]; then
  render <<< "$JQ_STDIN" 2>/dev/null || fallback
else
  render < /dev/null 2>/dev/null || fallback
fi
