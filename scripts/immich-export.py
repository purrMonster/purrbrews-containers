#!/usr/bin/env python3
r"""Export every Immich media file of one user, with its metadata, for re-upload.

Built for the November 2026 rebuild: the new Immich gets the photos back through
the web UI's upload, so the files must carry everything the UI can read.

What it does, per asset (photos, videos, live photos):
  1. downloads the original file through the API (no disk or database access);
  2. checks it against Immich's own SHA-1 checksum;
  3. writes back into the copy, with exiftool, what was edited inside Immich and
     would otherwise be lost: description, date taken (with its time zone),
     location and star rating;
  4. sets the file's modified time to the date taken.
Live photos: the still and its motion video get the same name stem, so a new
Immich pairs them again on upload. Output: <out>/<YYYY>/<MM>/<original name>.

Not exported (the UI upload can't take them back): albums, favourites, archive
state, people/faces, tags, stacks, trash, and the Locked folder (needs a PIN
session, an API key can't open it). Run once per Immich user, with that user's key.

API key: Immich > Account settings > API keys, with asset.read and asset.download.

Linux / macOS:
  sudo apt install libimage-exiftool-perl
  export IMMICH_API_KEY=...
  python3 scripts/immich-export.py --url https://immich.${DOMAIN} --out /mnt/carry/immich-penguin --dry-run
  python3 scripts/immich-export.py --url https://immich.${DOMAIN} --out /mnt/carry/immich-penguin

Windows PowerShell (5.1 or 7):
  winget install OliverBetz.ExifTool        # then open a new PowerShell window
  py -m pip install tzdata                  # Windows Python has no time-zone database
  $env:IMMICH_API_KEY = [Net.NetworkCredential]::new('', (Read-Host -AsSecureString 'Immich API key')).Password
  py scripts\immich-export.py --url https://immich.example.org --out D:\immich-penguin --dry-run
  py scripts\immich-export.py --url https://immich.example.org --out D:\immich-penguin
  Remove-Item Env:IMMICH_API_KEY

Re-running resumes: finished files are skipped (state in <out>.state.json, next
to the output folder so the folder itself holds media only).
Needs Python 3.9+ and exiftool, unless --no-embed. Written against the Immich v3.3.3 API.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None

PAGE_SIZE = 1000
RETRIES = 4
CHUNK = 1 << 20
VIDEO_EXT = {".mov", ".mp4", ".m4v", ".3gp", ".3g2", ".avi", ".mkv", ".webm", ".mts", ".m2ts", ".wmv", ".mpg", ".mpeg"}


class Immich:
    def __init__(self, url: str, key: str):
        self.base = url.rstrip("/")
        if not self.base.endswith("/api"):
            self.base += "/api"
        self.key = key

    def _request(self, method, path, body=None, stream=False):
        data = json.dumps(body).encode() if body is not None else None
        headers = {"x-api-key": self.key, "Accept": "application/json" if not stream else "*/*"}
        if data is not None:
            headers["Content-Type"] = "application/json"
        delay = 2
        for attempt in range(RETRIES + 1):
            try:
                response = urlopen(Request(self.base + path, data=data, headers=headers, method=method), timeout=120)
                return response if stream else json.load(response)
            except HTTPError as error:
                if error.code < 500 and error.code != 429 or attempt == RETRIES:
                    detail = error.read().decode(errors="replace")[:300]
                    raise RuntimeError(f"{method} {path}: HTTP {error.code} {detail}") from None
            except (URLError, TimeoutError, ConnectionError) as error:
                if attempt == RETRIES:
                    raise RuntimeError(f"{method} {path}: {error}") from None
            time.sleep(delay)
            delay *= 2

    def me(self):
        return self._request("GET", "/users/me")

    def asset(self, asset_id):
        return self._request("GET", f"/assets/{asset_id}")

    def assets(self):
        """Every asset on the timeline or in the archive, not trashed, with EXIF."""
        body = {"size": PAGE_SIZE, "withExif": True,
                "filter": {"visibility": {"in": ["timeline", "archive"]}, "trashedAt": {"eq": None}}}
        while True:
            page = self._request("POST", "/search/metadata", body)["assets"]
            yield from page["items"]
            cursor = page.get("nextCursor")
            if not cursor:
                return
            body["cursor"] = cursor

    def download(self, asset_id, edited=False):
        return self._request("GET", f"/assets/{asset_id}/original" + ("?edited=true" if edited else ""), stream=True)


def parse_time(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def tz_offset(name, moment):
    """Immich stores time zones as IANA names ('Asia/Kolkata') or 'UTC+5:30'."""
    if not name:
        return None
    match = re.fullmatch(r"UTC([+-])(\d{1,2})(?::?(\d{2}))?", name.strip())
    if match:
        sign = 1 if match.group(1) == "+" else -1
        return sign * timedelta(hours=int(match.group(2)), minutes=int(match.group(3) or 0))
    if name.strip().upper() in ("UTC", "Z", "GMT"):
        return timedelta(0)
    if ZoneInfo:
        try:
            return moment.astimezone(ZoneInfo(name)).utcoffset()
        except Exception:
            return None
    return None


def taken(asset):
    """Date taken as an aware datetime, in the asset's own time zone when known."""
    exif = asset.get("exifInfo") or {}
    moment = parse_time(exif.get("dateTimeOriginal")) or parse_time(asset.get("fileCreatedAt"))
    if moment is None:
        return None
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    offset = tz_offset(exif.get("timeZone"), moment)
    if offset is not None:
        moment = moment.astimezone(timezone(offset))
    return moment


def safe_name(name, fallback):
    name = (name or "").replace("/", "_").replace("\\", "_").strip().lstrip(".")
    name = re.sub(r'[\x00-\x1f<>:"|?*]', "_", name)
    return name or fallback


def fmt_offset(moment):
    seconds = int(moment.utcoffset().total_seconds())
    sign = "+" if seconds >= 0 else "-"
    seconds = abs(seconds)
    return f"{sign}{seconds // 3600:02d}:{seconds % 3600 // 60:02d}"


def exiftool_args(asset, path):
    """Tags to write into the copy: only what Immich holds a value for."""
    exif = asset.get("exifInfo") or {}
    video = asset.get("type") == "VIDEO" or path.suffix.lower() in VIDEO_EXT
    args = []
    description = (exif.get("description") or "").strip()
    if description:
        args += [f"-XMP-dc:Description={description}"]
        if not video:
            args += [f"-EXIF:ImageDescription={description}", f"-IPTC:Caption-Abstract={description}"]
    moment = taken(asset) if exif.get("dateTimeOriginal") else None
    if moment:
        if video:
            utc = moment.astimezone(timezone.utc).strftime("%Y:%m:%d %H:%M:%S")
            args += [f"-QuickTime:CreateDate={utc}", f"-QuickTime:MediaCreateDate={utc}",
                     f"-Keys:CreationDate={moment.strftime('%Y:%m:%d %H:%M:%S')}{fmt_offset(moment)}"]
        else:
            local = moment.strftime("%Y:%m:%d %H:%M:%S")
            args += [f"-EXIF:DateTimeOriginal={local}", f"-EXIF:CreateDate={local}",
                     f"-EXIF:OffsetTimeOriginal={fmt_offset(moment)}"]
    lat, lon = exif.get("latitude"), exif.get("longitude")
    if lat is not None and lon is not None:
        if video:
            args += [f"-Keys:GPSCoordinates={lat}, {lon}"]
        else:
            args += [f"-EXIF:GPSLatitude={abs(lat)}", f"-EXIF:GPSLatitudeRef={'N' if lat >= 0 else 'S'}",
                     f"-EXIF:GPSLongitude={abs(lon)}", f"-EXIF:GPSLongitudeRef={'E' if lon >= 0 else 'W'}"]
    if exif.get("rating") not in (None, 0):
        args += [f"-XMP-xmp:Rating={exif['rating']}"]
    return args


def embed(asset, path):
    args = exiftool_args(asset, path)
    if not args:
        return None
    # Tags and path go through a UTF-8 argument file: on Windows, exiftool reads
    # command-line arguments in the ANSI code page and would mangle non-ASCII text.
    argfile = path.with_name(path.name + ".args")
    lines = ["-q", "-m", "-P", "-overwrite_original", "-api", "QuickTimeUTC=1", "-charset", "filename=UTF8",
             "-charset", "iptc=UTF8", "-IPTC:CodedCharacterSet=UTF8", *args, str(path)]
    argfile.write_text("\n".join(line.replace("\n", " ") for line in lines) + "\n", encoding="utf-8")
    try:
        result = subprocess.run(["exiftool", "-@", str(argfile)], capture_output=True,
                                text=True, encoding="utf-8", errors="replace")
    finally:
        argfile.unlink(missing_ok=True)
    if result.returncode != 0:
        return (result.stderr or result.stdout).strip().splitlines()[-1:] or ["exiftool failed"]
    return None


class Exporter:
    def __init__(self, api, out, use_embed, edited):
        self.api, self.out, self.use_embed, self.edited = api, out, use_embed, edited
        self.state_path = out.parent / (out.name + ".state.json")
        self.state = json.loads(self.state_path.read_text()) if self.state_path.exists() else {}
        self.claimed = {v["path"]: k for k, v in self.state.items() if "path" in v}
        self.stats = {"exported": 0, "skipped": 0, "failed": 0, "live_motion": 0, "embed_warn": 0, "bytes": 0}
        self.failures = []

    def save_state(self):
        tmp = self.state_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.state))
        tmp.replace(self.state_path)

    def target(self, asset, stem=None, folder=None):
        moment = taken(asset)
        if folder is None:
            folder = Path(f"{moment:%Y}/{moment:%m}") if moment else Path("undated")
        name = safe_name(asset.get("originalFileName"), asset["id"])
        base, ext = os.path.splitext(name)
        base = stem or base
        candidate, n = folder / f"{base}{ext}", 1
        while self.claimed.get(str(candidate), asset["id"]) != asset["id"]:
            n += 1
            candidate = folder / f"{base} ({n}){ext}"
        self.claimed[str(candidate)] = asset["id"]
        return candidate

    def fetch(self, asset, relative, verify):
        destination = self.out / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        part = destination.with_name(destination.name + ".part")
        digest = hashlib.sha1()
        with self.api.download(asset["id"], edited=self.edited and asset.get("isEdited")) as response, open(part, "wb") as handle:
            while chunk := response.read(CHUNK):
                digest.update(chunk)
                handle.write(chunk)
        expected = asset.get("checksum")
        if verify and expected and not (self.edited and asset.get("isEdited")):
            got = base64.b64encode(digest.digest()).decode()
            if got != expected and digest.hexdigest() != expected:
                part.unlink(missing_ok=True)
                raise RuntimeError(f"checksum mismatch (Immich {expected}, got {got})")
        warning = embed(asset, part) if self.use_embed else None
        if warning:
            self.stats["embed_warn"] += 1
            print(f"  ! metadata not written to {relative}: {warning[0]}", file=sys.stderr)
        moment = taken(asset)
        if moment:
            stamp = moment.timestamp()
            os.utime(part, (stamp, stamp))
        part.replace(destination)
        return destination.stat().st_size

    def one(self, asset, relative, verify=True):
        record = self.state.get(asset["id"])
        if record and record.get("done") and (self.out / record["path"]).exists():
            self.stats["skipped"] += 1
            return Path(record["path"])
        try:
            size = self.fetch(asset, relative, verify)
        except Exception as error:  # keep going; report at the end
            self.stats["failed"] += 1
            self.failures.append(f"{asset.get('originalFileName')} ({asset['id']}): {error}")
            print(f"  x {asset.get('originalFileName')}: {error}", file=sys.stderr)
            return None
        self.state[asset["id"]] = {"path": str(relative), "done": True}
        self.stats["exported"] += 1
        self.stats["bytes"] += size
        return relative

    def run(self, assets):
        for index, asset in enumerate(assets, 1):
            relative = Path(self.state.get(asset["id"], {}).get("path") or self.target(asset))
            if self.one(asset, relative) and asset.get("livePhotoVideoId"):
                motion_id = asset["livePhotoVideoId"]
                try:
                    motion = self.api.asset(motion_id)
                except Exception as error:
                    self.stats["failed"] += 1
                    self.failures.append(f"motion part of {asset.get('originalFileName')} ({motion_id}): {error}")
                    continue
                if not motion.get("exifInfo"):
                    motion["exifInfo"] = {k: v for k, v in (asset.get("exifInfo") or {}).items()
                                          if k in ("dateTimeOriginal", "timeZone", "latitude", "longitude")}
                motion_relative = Path(self.state.get(motion_id, {}).get("path") or self.target(
                    motion, stem=relative.stem, folder=relative.parent))
                before = self.stats["exported"]
                if self.one(motion, motion_relative) and self.stats["exported"] > before:
                    self.stats["live_motion"] += 1
            if index % 25 == 0:
                self.save_state()
                print(f"  {index} assets: {self.stats['exported']} exported, {self.stats['skipped']} skipped, "
                      f"{self.stats['failed']} failed, {self.stats['bytes'] / 1e9:.2f} GB")
        self.save_state()


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--url", required=True, help="Immich address, e.g. https://immich.example.org")
    parser.add_argument("--out", required=True, type=Path, help="output folder (media files only)")
    parser.add_argument("--dry-run", action="store_true", help="count assets and size; download nothing")
    parser.add_argument("--no-embed", action="store_true", help="skip exiftool; files exactly as uploaded")
    parser.add_argument("--edited", action="store_true", help="export Immich-edited versions where they exist (default: originals)")
    args = parser.parse_args()

    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")  # odd file names must not crash a Windows console
        except AttributeError:
            pass
    if ZoneInfo is not None:
        try:
            ZoneInfo("Asia/Kolkata")
        except Exception:
            parser.error("no time-zone database: run `py -m pip install tzdata` (Windows) and try again")
    key = os.environ.get("IMMICH_API_KEY", "").strip()
    if not key:
        parser.error("set IMMICH_API_KEY in the environment (not on the command line)")
    if not args.no_embed and not args.dry_run and not shutil.which("exiftool"):
        parser.error("exiftool not found: apt install libimage-exiftool-perl (or pass --no-embed)")

    api = Immich(args.url, key)
    try:
        user = api.me()
    except RuntimeError as error:
        print(f"Can't reach Immich or the key was refused: {error}", file=sys.stderr)
        return 2
    print(f"Immich user: {user.get('name')} <{user.get('email')}>")
    try:
        assets = list(api.assets())
    except RuntimeError as error:
        print(f"Listing assets failed: {error}", file=sys.stderr)
        return 2
    live = sum(1 for a in assets if a.get("livePhotoVideoId"))
    size = sum((a.get("exifInfo") or {}).get("fileSizeInByte") or 0 for a in assets)
    kinds = {}
    for a in assets:
        kinds[a.get("type")] = kinds.get(a.get("type"), 0) + 1
    print(f"Found {len(assets)} assets {kinds}, {live} live photos (+{live} motion files), "
          f"~{size / 1e9:.2f} GB before motion files. Locked folder not included.")
    if args.dry_run:
        return 0

    args.out.mkdir(parents=True, exist_ok=True)
    free = shutil.disk_usage(args.out).free
    if free < size * 1.05:
        print(f"Not enough space in {args.out}: {free / 1e9:.2f} GB free, ~{size / 1e9:.2f} GB needed.", file=sys.stderr)
        return 2
    exporter = Exporter(api, args.out, not args.no_embed, args.edited)
    exporter.run(assets)
    s = exporter.stats
    print(f"Done: {s['exported']} exported, {s['skipped']} already there, {s['failed']} failed, "
          f"{s['live_motion']} live-photo motion files, {s['embed_warn']} without written metadata, "
          f"{s['bytes'] / 1e9:.2f} GB written to {args.out}")
    for line in exporter.failures:
        print("  failed:", line, file=sys.stderr)
    return 1 if s["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
