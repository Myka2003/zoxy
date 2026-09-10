#!/usr/bin/env python3
import json, os, re, sys

config_path = os.environ.get("ZOXY_CONFIG", "/etc/zoxy/config.json")
search_dirs = []
if os.path.exists(config_path):
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            c = json.load(f)
            search_dirs = [os.path.expanduser(d) for d in c.get("gameRoots", [])]
    except Exception:
        pass
if not search_dirs:
    search_dirs = [os.path.expanduser("~/Games")]

ignored_dirs = {
    "umu", ".umu-prefixes", "drive_c", "dosdevices", "pfx", "prefix",
    "tmp", "temp", "dlc", "patch", "redist", "directx", "windows", "system32",
    "node_modules", ".git"
}

ignored_patterns = re.compile(
    r"(crash|handler|unins|quicksfv|dxsetup|vcredist|createdump|redist|dotnet|directx|vc_redist|patch_|patch\.exe|poer|visualggpk|poestring|cgef|stockfish|setup|is-.*\.tmp|rtvoicett|regrouplog|bugreporter|scriptinterpreter|gmlive)",
    re.IGNORECASE
)

games = {}
for sdir in search_dirs:
    if not os.path.exists(sdir):
        continue
    for root, dirs, files in os.walk(sdir):
        # Prune directory search in-place so os.walk avoids large Wine prefix trees
        dirs[:] = [d for d in dirs if d.lower() not in ignored_dirs and not d.startswith(".")]

        exe_files = [f for f in files if f.lower().endswith(".exe") and not ignored_patterns.search(f)]
        if not exe_files:
            continue

        rel = os.path.relpath(root, sdir)
        top_folder = rel.split(os.sep)[0] if rel != "." else ""

        display_name = top_folder if top_folder else os.path.splitext(exe_files[0])[0]
        display_name = re.sub(r"\[(Repack|GOG|FitGirl|Portable|Scene|GoodOldGames|Awasaky|SeleZen|LinguaLatina|Sharity|InsaneRamZes|dixen18|Merded)[^\]]*\]", "", display_name, flags=re.I)
        display_name = re.sub(r"v?\d+\.\d+.*", "", display_name).strip(" _-.")
        if not display_name:
            display_name = top_folder or exe_files[0]

        def exe_priority(f):
            fpath = os.path.join(root, f)
            try:
                sz = os.path.getsize(fpath)
            except OSError:
                sz = 0
            f_low = f.lower()
            match_score = 0
            clean_disp = re.sub(r"[^a-zA-Z0-9]", "", display_name.lower())
            clean_f = re.sub(r"[^a-zA-Z0-9]", "", f_low)
            if clean_f == clean_disp or clean_disp in clean_f or clean_f in clean_disp:
                match_score += 100000000
            if "shipping" in f_low:
                match_score -= 50000000
            return (match_score, sz)

        best_exe = sorted(exe_files, key=exe_priority, reverse=True)[0]
        best_path = os.path.join(root, best_exe)
        try:
            best_sz = os.path.getsize(best_path)
        except OSError:
            best_sz = 0

        tag = "🎮 纯净游戏"
        games[display_name] = (tag, display_name, best_exe, best_path, best_sz)

for gname in sorted(games.keys(), key=lambda s: s.lower()):
    tag, name, exe, path, sz = games[gname]
    sz_str = f"{sz/(1024*1024):.1f} MB" if sz < 1024**3 else f"{sz/(1024**3):.2f} GB"
    print(f"{tag}\t{name}\t{exe}\t{sz_str}\t{path}")
