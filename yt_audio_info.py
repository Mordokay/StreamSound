#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os, sys, json, urllib.parse, subprocess, datetime

def http_error(status_code: int, message: str):
    # Minimal JSON error with proper status
    print(f"Status: {status_code}")
    print("Content-Type: application/json")
    print("Access-Control-Allow-Origin: *")
    print()
    print(json.dumps({"ok": False, "error": message}, ensure_ascii=False))
    sys.exit(0)

# Parse query string
qs = os.environ.get("QUERY_STRING", "")
params = urllib.parse.parse_qs(qs)
url = params.get("url", [None])[0]
prefer_hls = params.get("prefer_hls", ["0"])[0] in ("1", "true", "yes")

if not url:
    http_error(400, "Missing required query parameter: url")

# Build yt-dlp command
# prefer HLS if requested, else bestaudio (usually m4a progressive)
fmt = "bestaudio[protocol^=m3u8]/bestaudio" if prefer_hls else "bestaudio[ext=m4a]/bestaudio"
cmd = ["yt-dlp", "-f", fmt, "--dump-json", url]

# Ensure PATH includes Homebrew bin (CGI env can be minimal)
env = os.environ.copy()
env["PATH"] = env.get("PATH", "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

try:
    proc = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=60)
except Exception as e:
    http_error(500, f"Failed to run yt-dlp: {e}")

if proc.returncode != 0:
    http_error(502, proc.stderr.strip() or "yt-dlp failed")

# yt-dlp can print multiple JSON lines (playlists); pick last line
try:
    info = json.loads(proc.stdout.splitlines()[-1])
except Exception as e:
    http_error(500, f"Invalid yt-dlp JSON: {e}")

stream_url = info.get("url")
title = info.get("title")
uploader = info.get("uploader")
duration = info.get("duration")
ext = info.get("ext")

# Highest-res thumbnail
thumb = None
thumbs = info.get("thumbnails") or []
if thumbs:
    thumb = sorted(thumbs, key=lambda t: t.get("width", 0))[-1].get("url")

# shortDescription (fallback to trimmed description)
short_desc = info.get("shortDescription")
if not short_desc:
    full = info.get("description") or ""
    short_desc = (full[:197] + "…") if len(full) > 198 else full

# Expiration from querystring (?expire=epoch)
expire_ts = None
expire_human = None
if stream_url:
    q = urllib.parse.parse_qs(urllib.parse.urlparse(stream_url).query)
    if "expire" in q:
        try:
            expire_ts = int(q["expire"][0])
            expire_human = datetime.datetime.fromtimestamp(expire_ts).isoformat()
        except Exception:
            pass

payload = {
    "ok": True,
    "title": title,
    "uploader": uploader,
    "duration": duration,
    "ext": ext,
    "stream_url": stream_url,
    "thumbnail_url": thumb,
    "shortDescription": short_desc,
    "expire_ts": expire_ts,
    "expire_human": expire_human,
    # Useful echoes:
    "original_url": url,
    "prefer_hls": prefer_hls,
}

# Response
print("Status: 200")
print("Content-Type: application/json; charset=utf-8")
print("Access-Control-Allow-Origin: *")  # handy if you call this from apps/webviews
print()
print(json.dumps(payload, ensure_ascii=False))