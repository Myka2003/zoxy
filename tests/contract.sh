#!/usr/bin/env bash
# zoxy 契约测试：**真的运行脚本**，断言行为，而不是 grep 源码文本。
#
# 重点覆盖 zoxy-stream-session 的请求校验 —— 那是整个工具的安全边界：
# 它决定一个 JSON 请求文件能不能让主机在没有人工确认的情况下执行一个 exe。
set -euo pipefail

zoxy=${1:?usage: contract.sh /nix/store/...-zoxy}
bin="$zoxy/bin"

export HOME=$(mktemp -d)
export XDG_STATE_HOME="$HOME/.local/state"
state="$HOME/.local/state/zoxy"
games="$HOME/Games"
mkdir -p "$state" "$games/Demo"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok: %s\n' "$*"; }

# ── 1. 所有 bin 存在且可执行 ────────────────────────────────────────────────
for b in zoxy zoxy-download zoxy-list-games zoxy-run zoxy-search zoxy-source-sync \
         zoxy-stream-request zoxy-stream-session zoxy-stream-sway zoxy-stream-wait-wayland zoxy-tui; do
  [ -x "$bin/$b" ] || fail "missing bin: $b"
done
ok "11 个 bin 可执行"

# ── 1b. Python 脚本语法 ─────────────────────────────────────────────────────
# 这两个脚本是从 Nix 缩进字符串里抽出来的，shebang/缩进最容易在这一步坏掉，
# 而坏了只有在用户真的打开 TUI 时才会发现。
for py in zoxy-list-games zoxy-tui; do
  python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$bin/$py" \
    || fail "$py 语法错误"
done
ok "Python 脚本语法正确"

# ── 2. 没有配置文件时给出明确错误（而不是静默继续）────────────────────────
export ZOXY_CONFIG="$HOME/absent.json"
if out=$("$bin/zoxy-stream-request" t /tmp/x.exe 2>&1); then
  fail "zoxy-stream-request 应该在没有配置时报错"
fi
printf '%s' "$out" | grep -q 'configuration file not found' \
  || fail "错误信息不含 'configuration file not found': $out"
ok "缺配置时报错清晰"

# ── 3. config.json schema 被真正读取 ────────────────────────────────────────
cat > "$HOME/config.json" <<JSON
{
  "user": "tester",
  "gameRoots": ["$games"],
  "targets": {
    "remote": { "type": "moonlight-client", "clientHost": "nope.invalid", "clientUser": "nobody" },
    "local": { "type": "local" }
  },
  "stream": { "sunshineHost": "host.invalid", "sunshineApp": "Zoxy Session" }
}
JSON
export ZOXY_CONFIG="$HOME/config.json"

# gameRoots 决定能发现哪些游戏
touch "$games/Demo/game.exe"
listed=$("$bin/zoxy-list-games")
printf '%s' "$listed" | grep -q 'Demo' || fail "zoxy-list-games 没读到 gameRoots: $listed"
ok "gameRoots 被 zoxy-list-games 读取"

# targets 里 non-moonlight 的目标会被 request 拒绝
if out=$("$bin/zoxy-stream-request" local /tmp/x.exe 2>&1); then
  fail "请求一个 local 目标应该被拒绝"
fi
printf '%s' "$out" | grep -q 'is not a moonlight-client' || fail "错误信息不符: $out"
ok "非 moonlight 目标被拒绝"

# ── 4. 请求文件的校验（安全边界）────────────────────────────────────────────
write_request() {  # write_request <json>
  printf '%s\n' "$1" > "$state/remote-request.json"
  : > /tmp/zoxy-stream-session.log
}

run_session() {  # 返回退出码；输出在 /tmp/zoxy-stream-session.log
  "$bin/zoxy-stream-session" >/dev/null 2>&1 && return 0 || return $?
}

now=$(date +%s)

# 4a. 合法形状但路径不存在 → 必须走到 "does not exist" 而不是通过
write_request "{\"version\":1,\"path\":\"$games/Demo/missing.exe\",\"nonce\":\"0123456789abcdef\",\"created_at\":$now}"
run_session || true
grep -q 'game file does not exist' /tmp/zoxy-stream-session.log \
  || fail "合法形状的请求没有被接受并继续检查（log: $(tail -2 /tmp/zoxy-stream-session.log))"
ok "合法请求通过校验并检查文件存在性"

# 4b. 路径越界 → 必须被拒（不能执行 gameRoots 之外的 exe）
outside=$(mktemp -d)/evil.exe
touch "$outside"
write_request "{\"version\":1,\"path\":\"$outside\",\"nonce\":\"0123456789abcdef\",\"created_at\":$now}"
run_session || true
grep -q 'outside configured roots' /tmp/zoxy-stream-session.log \
  || fail "越界路径没有被拒绝（log: $(tail -2 /tmp/zoxy-stream-session.log))"
ok "gameRoots 之外的路径被拒绝"

# 4c. 过期请求（重放）→ 必须被拒
write_request "{\"version\":1,\"path\":\"$games/Demo/game.exe\",\"nonce\":\"0123456789abcdef\",\"created_at\":$((now - 600))}"
run_session || true
grep -q 'invalid or expired game request' /tmp/zoxy-stream-session.log \
  || fail "过期请求没有被拒绝（log: $(tail -2 /tmp/zoxy-stream-session.log))"
ok "过期请求被拒绝（防重放）"

# 4d. 非 .exe → 必须被拒
write_request "{\"version\":1,\"path\":\"$games/Demo/game.txt\",\"nonce\":\"0123456789abcdef\",\"created_at\":$now}"
run_session || true
grep -q 'invalid or expired game request' /tmp/zoxy-stream-session.log \
  || fail "非 .exe 路径没有被拒绝（log: $(tail -2 /tmp/zoxy-stream-session.log))"
ok "非 .exe 被拒绝"

# ── 5. 未定义的程序行为：无参数、错参数 ──────────────────────────────────────
for b in zoxy-download zoxy-stream-request; do
  if "$bin/$b" >/dev/null 2>&1; then fail "$b 无参数时应报 usage 并失败"; fi
done
ok "参数校验生效"

printf '\nzoxy contract: PASS\n'
