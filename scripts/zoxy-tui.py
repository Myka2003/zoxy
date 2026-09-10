#!/usr/bin/env python3
import sys, os, time, json, urllib.request, urllib.parse, curses

def format_size(size_bytes):
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1024**2:
        return f"{size_bytes/1024:.1f} KB"
    elif size_bytes < 1024**3:
        return f"{size_bytes/(1024**2):.1f} MB"
    else:
        return f"{size_bytes/(1024**3):.2f} GB"

def format_speed(speed_bytes):
    return f"{format_size(speed_bytes)}/s"

def format_eta(seconds):
    if seconds >= 8640000 or seconds < 0:
        return "∞"
    m, s = divmod(seconds, 60)
    h, m = divmod(m, 60)
    d, h = divmod(h, 24)
    if d > 0:
        return f"{d}d {h}h"
    elif h > 0:
        return f"{h}h {m}m"
    elif m > 0:
        return f"{m}m {s}s"
    else:
        return f"{s}s"

def api_call(endpoint, data=None):
    base = os.environ.get("ZOXY_DOWNLOADER_URL", "http://127.0.0.1:8080")
    url = f"{base}/api/v2/{endpoint}"
    try:
        if data:
            encoded = urllib.parse.urlencode(data).encode("utf-8")
            req = urllib.request.Request(url, data=encoded, method="POST")
        else:
            req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=3) as resp:
            content = resp.read().decode("utf-8")
            return json.loads(content) if content else {}
    except Exception:
        return None

def safe_addstr(stdscr, y, x, text, attr=0):
    try:
        height, width = stdscr.getmaxyx()
        if y < 0 or y >= height or x < 0 or x >= width:
            return
        max_len = width - x - 1
        if max_len <= 0:
            return
        stdscr.addstr(y, x, text[:max_len], attr)
    except Exception:
        pass

def main(stdscr):
    curses.curs_set(0)
    stdscr.timeout(1000)
    curses.use_default_colors()

    curses.init_pair(1, curses.COLOR_CYAN, -1)     # Header
    curses.init_pair(2, curses.COLOR_GREEN, -1)    # Downloading / OK
    curses.init_pair(3, curses.COLOR_YELLOW, -1)   # Paused / Warning
    curses.init_pair(4, curses.COLOR_MAGENTA, -1)  # Seeding
    curses.init_pair(5, curses.COLOR_BLACK, curses.COLOR_CYAN) # Highlighted
    curses.init_pair(6, curses.COLOR_RED, -1)      # Error

    selected_idx = 0
    message = ""
    msg_time = 0

    while True:
        height, width = stdscr.getmaxyx()
        stdscr.erase()

        transfer = api_call("transfer/info") or {}
        torrents = api_call("torrents/info") or []

        dl_spd = format_speed(transfer.get("dl_info_speed", 0))
        ul_spd = format_speed(transfer.get("up_info_speed", 0))
        free_space = format_size(transfer.get("free_space_on_disk", 0))

        title = " 🎮 qBittorrent CLI Dashboard "
        stats = f"⬇ {dl_spd}  ⬆ {ul_spd}  💾 剩余: {free_space} "
        safe_addstr(stdscr, 0, 0, title, curses.color_pair(1) | curses.A_BOLD)
        if len(title) + len(stats) < width:
            safe_addstr(stdscr, 0, width - len(stats) - 1, stats, curses.color_pair(1) | curses.A_BOLD)

        try:
            stdscr.hline(1, 0, curses.ACS_HLINE, width)
        except Exception:
            safe_addstr(stdscr, 1, 0, "-" * (width - 1))

        if not torrents:
            safe_addstr(stdscr, 3, 2, "暂无活跃的下载任务。按 q 退出。", curses.A_DIM)
        else:
            if selected_idx >= len(torrents):
                selected_idx = max(0, len(torrents) - 1)

            max_rows = max(1, height - 4)
            for i, t in enumerate(torrents[:max_rows]):
                row = 2 + i
                is_selected = (i == selected_idx)

                name = t.get("name", "Unknown")
                state = t.get("state", "unknown")
                prog = t.get("progress", 0.0) * 100
                dl_size = format_size(t.get("downloaded", 0))
                tot_size = format_size(t.get("total_size", 0))
                speed = format_speed(t.get("dlspeed", 0))
                eta = format_eta(t.get("eta", -1))
                seeds = t.get("num_seeds", 0)

                if "downloading" in state:
                    st_icon = "⬇"
                    st_color = curses.color_pair(2)
                elif "paused" in state:
                    st_icon = "⏸"
                    st_color = curses.color_pair(3)
                elif "uploading" in state or "seeding" in state:
                    st_icon = "⬆"
                    st_color = curses.color_pair(4)
                elif "stalled" in state:
                    st_icon = "⏳"
                    st_color = curses.color_pair(6)
                else:
                    st_icon = "•"
                    st_color = curses.color_pair(1)

                bar_len = 10
                filled = int(bar_len * (prog / 100))
                bar_str = f"[{'█' * filled}{'░' * (bar_len - filled)}] {prog:5.1f}%"

                name_max = max(10, width - 60)
                if len(name) > name_max:
                    name_disp = name[:name_max-3] + "..."
                else:
                    name_disp = name.ljust(name_max)

                line_str = f" {st_icon} {name_disp}  {bar_str}  {dl_size:>8}/{tot_size:<8}  {speed:>10}  ETA:{eta:<6}  做种:{seeds}"

                if is_selected:
                    safe_addstr(stdscr, row, 0, line_str.ljust(width - 1), curses.color_pair(5) | curses.A_BOLD)
                else:
                    safe_addstr(stdscr, row, 0, line_str, st_color)

        try:
            stdscr.hline(height - 2, 0, curses.ACS_HLINE, width)
        except Exception:
            safe_addstr(stdscr, height - 2, 0, "-" * (width - 1))

        if message and (time.time() - msg_time < 3):
            safe_addstr(stdscr, height - 1, 2, f"ℹ {message}", curses.color_pair(3) | curses.A_BOLD)
        else:
            footer = " [↑/↓/j/k] 移动 | [空格] 暂停/继续 | [d] 删除任务 | [q/Esc] 退出(后台保持下载)"
            safe_addstr(stdscr, height - 1, 0, footer, curses.A_DIM)

        stdscr.refresh()

        try:
            ch = stdscr.getch()
        except Exception:
            ch = -1

        if ch in (ord('q'), ord('Q'), 27):
            break
        elif ch in (curses.KEY_UP, ord('k')):
            if selected_idx > 0:
                selected_idx -= 1
        elif ch in (curses.KEY_DOWN, ord('j')):
            if selected_idx < len(torrents) - 1:
                selected_idx += 1
        elif ch == ord(' '):
            if torrents and selected_idx < len(torrents):
                t = torrents[selected_idx]
                h = t.get("hash")
                st = t.get("state", "")
                if "paused" in st:
                    api_call("torrents/resume", {"hashes": h})
                    message = f"已继续: {t.get('name')}"
                else:
                    api_call("torrents/pause", {"hashes": h})
                    message = f"已暂停: {t.get('name')}"
                msg_time = time.time()
        elif ch in (ord('d'), ord('D')):
            if torrents and selected_idx < len(torrents):
                t = torrents[selected_idx]
                h = t.get("hash")
                safe_addstr(stdscr, height - 1, 2, f"确认删除 {t.get('name')} ? (y/N): ", curses.color_pair(6) | curses.A_BOLD)
                stdscr.refresh()
                stdscr.timeout(-1)
                confirm = stdscr.getch()
                stdscr.timeout(1000)
                if confirm in (ord('y'), ord('Y')):
                    api_call("torrents/delete", {"hashes": h, "deleteFiles": "false"})
                    message = f"已删除任务: {t.get('name')}"
                    msg_time = time.time()

if __name__ == "__main__":
    curses.wrapper(main)
