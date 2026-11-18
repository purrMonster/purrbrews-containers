#!/bin/bash
# make-flask.sh: build or check flask, the offline recovery kit
# (docs/recovery-kit.md). Runs on americano (macOS, its own /bin/bash is
# enough) or any Linux; no root needed. It replaces make-flask.ps1, which ran
# on roastery (deprecated/stacks/roastery/flask).
#
#   ./make-flask.sh             download, verify, and write every flask stick plugged in
#   ./make-flask.sh --prepare   download and verify only; no stick needed
#   ./make-flask.sh --check     no downloads: check each stick against its SHA256SUMS
#                               and compare the two vaults (the yearly check)
#
# A flask stick is a USB disk with Ventoy on it (its VTOYEFI partition is how
# this tells) and an exFAT data partition labelled FLASK-A or FLASK-B, mounted.
# Nothing else is ever written to, so an internal disk or an unlabelled stick
# is safe. Ventoy itself is installed once per stick from Linux; macOS has no
# Ventoy installer (docs/recovery-kit.md, "Building it").
#
# What goes on each stick:
#
#   debian-live-<ver>-amd64-xfce.iso   Ventoy boots it
#   tools/linux-amd64/                 restic, rclone, KeePassXC AppImage
#   tools/windows-amd64/               restic.exe, rclone.exe, KeePassXC/ (portable)
#   tools/darwin-arm64/, darwin-amd64/ restic, rclone, KeePassXC .dmg
#   RECOVERY.md, VERSIONS.txt
#   ventoy/ventoy.json, ventoy/flask_injection.tar.gz
#                                      Ventoy LiveInjection: at boot, copies live/ (beside
#                                      this script) into the live system, which then mounts
#                                      the kit at /mnt/flask and has KeePassXC, restic and
#                                      rclone in its menu and PATH
#   SHA256SUMS                         every file above; `shasum -a 256 -c SHA256SUMS`
#
# flask.kdbx is never read, written or listed in SHA256SUMS: fill-vault.sh and
# KeePassXC fill it. --check only compares its hash between the sticks, so you
# know whether B still matches A.
#
# Trust: every download is checked against its project's signed checksums, and
# the signature against the key fingerprints pinned below (from each project's
# own docs, 2026-09-28). A key is fetched from a keyserver but only accepted if
# its fingerprint matches. Anything that doesn't verify stops the run before a
# stick is touched. Needs gpg (macOS: brew install gnupg); curl, shasum, unzip,
# bzip2 and tar come with macOS and Debian.
#
# The versions are pinned too; bump them at the yearly check (runbook).
#
set -euo pipefail

DEBIAN_VERSION="${FLASK_DEBIAN_VERSION:-13.7.0}"
RESTIC_VERSION="${FLASK_RESTIC_VERSION:-0.19.1}"
RCLONE_VERSION="${FLASK_RCLONE_VERSION:-1.76.0}"
# 2.7.12, not 2.8.0 (2026-11-04): 2.7's AppImage is the one proven in the live
# system (runbook, 2026-09-30). Try 2.8 at the next yearly check, with a boot.
KEEPASSXC_VERSION="${FLASK_KEEPASSXC_VERSION:-2.7.12}"
# Ventoy's LiveInjection framework. Its releases aren't signed, so the archive
# is pinned by SHA-256 (from the release, 2026-09-29).
LI_VERSION=1.1
LI_SHA256=59eef2d8ae13185c702cf99efeb86f9ec77beb98a790ca9491251973411cfd62
LI_ID=live_injection_7ed136ec_7a61_4b54_adc3_ae494d5106ea   # the folder name its hooks look for

KEY_DEBIAN=DF9B9C49EAA9298432589D76DA87E80D6294BE9B      # Debian CD signing key (debian.org/CD/verify)
KEY_RESTIC=CF8F18F2844575973F79D4E191A6868BD3F7A907      # Alexander Neumann (restic docs, Installation)
KEY_RCLONE=FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA      # Nick Craig-Wood (rclone.org/release_signing)
KEY_KEEPASSXC=BF5A669F2272CF4324C1FDA8CFB4C2166397D0D2   # KeePassXC master key (keepassxc.org/verifying-signatures)

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$(uname -s)" == Darwin ]]; then
  OS=mac
  CACHE="${FLASK_CACHE:-$HOME/Library/Caches/purrbrews-flask}"
else
  OS=linux
  CACHE="${FLASK_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/purrbrews-flask}"
fi
# Never write these: the vault, our own sums file, and what macOS and Windows
# leave on any volume they touch (indexes, trash, AppleDouble ._ files).
EXCLUDED='^(flask\.kdbx.*|SHA256SUMS|System Volume Information/.*|\.fseventsd/.*|\.Spotlight-V100/.*|\.Trashes/.*|\.TemporaryItems/.*|\.metadata_never_index|(.*/)?\.DS_Store|(.*/)?\._.*)$'
export COPYFILE_DISABLE=1   # macOS tar and cp: no ._ files

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'make-flask: %s\n' "$*" >&2; exit 1; }

MODE='write'
case "${1:-}" in
  '') ;;
  --prepare) MODE=prepare ;;
  --check) MODE=check ;;
  -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "unknown option '$1' (--prepare, --check)" ;;
esac

sha256() {  # sha256 <file>: its hex digest
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
sha512() {
  if command -v sha512sum >/dev/null 2>&1; then sha512sum "$1" | cut -d' ' -f1
  else shasum -a 512 "$1" | cut -d' ' -f1; fi
}
copy() {  # copy <src> <dest>: no extended attributes, so no ._ files on exFAT
  if [[ $OS == mac ]]; then cp -X "$1" "$2"; else cp "$1" "$2"; fi
}
copy_tree() {  # copy_tree <src-dir> <dest-dir>: contents of src into dest
  mkdir -p "$2"
  if [[ $OS == mac ]]; then cp -RX "$1/." "$2/"; else cp -R "$1/." "$2/"; fi
}

# ── sticks ────────────────────────────────────────────────────────────────────
# One line per flask stick: <label> TAB <mount point> TAB <what it is>.
# FLASK_TEST_STICKS="FLASK-A=/some/dir ..." stands in for real sticks (tests).
find_sticks() {
  local label root disk
  if [[ -n "${FLASK_TEST_STICKS:-}" ]]; then
    for pair in $FLASK_TEST_STICKS; do
      printf '%s\t%s\t%s\n' "${pair%%=*}" "${pair#*=}" 'test folder'
    done
    return
  fi
  for label in FLASK-A FLASK-B; do
    if [[ $OS == mac ]]; then
      root="/Volumes/$label"
      [[ -d "$root" ]] || continue
      local info proto fs
      info="$(diskutil info -plist "$root" 2>/dev/null)" || { warn "$label: diskutil can't read it; skipped."; continue; }
      proto="$(plutil -extract BusProtocol raw -o - - <<< "$info" 2>/dev/null || true)"
      fs="$(plutil -extract FilesystemType raw -o - - <<< "$info" 2>/dev/null || true)"
      disk="$(plutil -extract ParentWholeDisk raw -o - - <<< "$info" 2>/dev/null || true)"
      [[ "$proto" == USB ]] || { warn "$label isn't on a USB disk ($proto); skipped."; continue; }
      [[ "$fs" == exfat ]] || { warn "$label is $fs, not exFAT; skipped."; continue; }
      diskutil list "$disk" 2>/dev/null | grep -q VTOYEFI \
        || { warn "$label has no Ventoy on it (no VTOYEFI partition on $disk); install Ventoy first. Skipped."; continue; }
    else
      local part
      part="$(blkid -L "$label" 2>/dev/null || true)"
      [[ -n "$part" ]] || continue
      disk="/dev/$(lsblk -no PKNAME "$part" | head -n 1)"
      [[ "$(lsblk -ndo TRAN "$disk")" == usb ]] || { warn "$label isn't on a USB disk; skipped."; continue; }
      [[ "$(lsblk -no FSTYPE "$part")" == exfat ]] || { warn "$label isn't exFAT; skipped."; continue; }
      lsblk -nro LABEL "$disk" | grep -qx VTOYEFI \
        || { warn "$label has no Ventoy on it (no VTOYEFI partition on $disk); install Ventoy first. Skipped."; continue; }
      root="$(lsblk -no MOUNTPOINT "$part" | head -n 1)"
      [[ -n "$root" ]] || { warn "$label ($part) isn't mounted: udisksctl mount -b $part, then run again. Skipped."; continue; }
    fi
    printf '%s\t%s\t%s\n' "$label" "$root" "$disk"
  done
}

tree_sums() {  # tree_sums <root>: "<sha256>  <relative path>" for every kit file, sorted
  local root="$1" file rel
  (cd "$root" && find . -type f -print0) | while IFS= read -r -d '' file; do
    rel="${file#./}"
    printf '%s\n' "$rel" | grep -Eq "$EXCLUDED" && continue
    printf '%s  %s\n' "$(sha256 "$root/$rel")" "$rel"
  done | LC_ALL=C sort -k2
}

check_stick() {  # check_stick <label> <root>: does it read back as SHA256SUMS says?
  local label="$1" root="$2" want have names bad=0 rel
  if [[ ! -f "$root/SHA256SUMS" ]]; then
    warn "$label: no SHA256SUMS; it has never been built."
    return 1
  fi
  want="$(LC_ALL=C sort -k2 "$root/SHA256SUMS")"
  have="$(tree_sums "$root")"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    rel="${line#*  }"
    grep -qxF "$line" <<< "$have" || { warn "$label: changed or missing: $rel"; bad=1; }
  done <<< "$want"
  # Something added by hand (a second ISO, say) is only a note: it isn't part
  # of the kit, and nothing here should make you delete it.
  names="$(sed 's/^[0-9a-f]*  //' <<< "$want")"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    rel="${line#*  }"
    grep -qxF "$rel" <<< "$names" || say "  $label: not part of the kit (left alone): $rel"
  done <<< "$have"
  [[ $bad -eq 0 ]] || return 1
  say "  $label: all $(grep -c . <<< "$want") files match SHA256SUMS"
}

compare_vaults() {  # compare_vaults < sticks
  local label root disk sums='' n=0
  while IFS="$(printf '\t')" read -r label root disk; do
    if [[ -f "$root/flask.kdbx" ]]; then
      sums="$sums$(sha256 "$root/flask.kdbx")"$'\n'; n=$((n + 1))
    else
      warn "$label: no flask.kdbx yet."
    fi
  done
  if [[ $n -eq 2 ]]; then
    if [[ "$(printf '%s' "$sums" | sort -u | grep -c .)" -eq 1 ]]; then
      say '  flask.kdbx: the same on both sticks'
    else
      warn 'flask.kdbx differs between the sticks: copy the newer one (A, by the runbook) over the other.'
    fi
  fi
}

STICKS="$(find_sticks)"
if [[ $MODE == check ]]; then
  step 'Checking the sticks'
  [[ -n "$STICKS" ]] || die 'no flask stick plugged in (FLASK-A or FLASK-B, with Ventoy, mounted).'
  ok=1
  while IFS="$(printf '\t')" read -r label root disk; do
    check_stick "$label" "$root" || ok=0
  done <<< "$STICKS"
  compare_vaults <<< "$STICKS"
  [[ $ok -eq 1 ]] || die 'at least one stick failed its check: rebuild it with ./make-flask.sh, then refill or copy its vault.'
  say ''
  say 'All good. Eject them and put them back in their places.'
  exit 0
fi
if [[ $MODE == write && -z "$STICKS" ]]; then
  die 'no flask stick plugged in (FLASK-A or FLASK-B, with Ventoy, mounted). --prepare downloads and verifies without one.'
fi

# ── download and verify ──────────────────────────────────────────────────────
for tool in curl gpg unzip bzip2 tar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    if [[ $tool == gpg ]]; then die "gpg isn't installed (macOS: brew install gnupg)."; fi
    die "$tool isn't installed."
  fi
done
DOWNLOADS="$CACHE/downloads"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/flask-work.XXXXXX")"
GNUPGHOME="$WORK/gnupg"
mkdir -p "$DOWNLOADS" "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
cleanup() {
  gpgconf --homedir "$GNUPGHOME" --kill all >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

download() {  # download <url> <dest>: once; -C - resumes a broken one
  [[ -f "$2" ]] && return 0
  say "  downloading $(basename "$2")"
  curl -fL --retry 3 -C - --progress-bar -o "$2.part" "$1" || { rm -f "$2.part"; return 1; }
  mv -f "$2.part" "$2"
}

import_key() {  # import_key <fingerprint>: only if it imports as exactly that key
  local fpr="$1" file="$WORK/$1.asc"
  curl -fsSL --retry 3 -o "$file" "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x$fpr" \
    || die "couldn't fetch key $fpr from keyserver.ubuntu.com."
  gpg --homedir "$GNUPGHOME" --batch --quiet --import "$file" 2>/dev/null || true
  gpg --homedir "$GNUPGHOME" --batch --with-colons --fingerprint "$fpr" 2>/dev/null \
    | awk -F: '$1 == "fpr" { print $10 }' | grep -qx "$fpr" \
    || die "key $fpr didn't import as that fingerprint; not trusting it."
}

assert_sig() {  # assert_sig <what> <allowed fingerprint> -- <gpg args...>
  # Good only if gpg says GOODSIG and VALIDSIG's primary-key fingerprint (its
  # last field) is the one pinned. Not good enough: any key in the keyring.
  local what="$1" allowed="$2" out primary; shift 3
  out="$(gpg --homedir "$GNUPGHOME" --batch --status-fd 1 "$@" 2>&1)" || true
  primary="$(printf '%s\n' "$out" | awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $NF }' | head -n 1)"
  if ! printf '%s\n' "$out" | grep -q '^\[GNUPG:\] GOODSIG ' || [[ "$primary" != "$allowed" ]]; then
    printf '%s\n' "$out" | grep -v '^\[GNUPG:\]' | sed 's/^/    /' >&2
    die "$what: signature not good, or not by the pinned key. Stopping; no stick was touched."
  fi
  say "  $what: signature good ($primary)"
}

sum_for() {  # sum_for <sums file> <name>: the hash listed for that file name
  awk -v n="$2" '{ f = $2; sub(/^\*/, "", f); sub(/^\.\//, "", f); if (f == n) { print tolower($1); exit } }' "$1"
}

assert_hash() {  # assert_hash <file> <expected> <256|512>
  local name got
  name="$(basename "$1")"
  [[ -n "$2" ]] || die "no published checksum for $name."
  if [[ "$3" == 512 ]]; then got="$(sha512 "$1")"; else got="$(sha256 "$1")"; fi
  if [[ "$got" != "$2" ]]; then
    rm -f "$1"
    die "$name: checksum mismatch (deleted; run again to download it fresh)."
  fi
  say "  $name: SHA-$3 matches"
}

step 'Signing keys (pinned fingerprints)'
for k in "$KEY_DEBIAN" "$KEY_RESTIC" "$KEY_RCLONE" "$KEY_KEEPASSXC"; do import_key "$k"; done
say '  4 keys imported, fingerprints match'

# Debian Live: the current release sits in debian-cd/, older ones in archive/.
step "Debian Live $DEBIAN_VERSION (xfce)"
ISO="debian-live-$DEBIAN_VERSION-amd64-xfce.iso"
dd="$DOWNLOADS/debian-$DEBIAN_VERSION"; mkdir -p "$dd"
base=''
for b in "https://cdimage.debian.org/debian-cd/$DEBIAN_VERSION-live/amd64/iso-hybrid" \
         "https://cdimage.debian.org/cdimage/archive/$DEBIAN_VERSION-live/amd64/iso-hybrid"; do
  if download "$b/SHA512SUMS" "$dd/SHA512SUMS.$$" 2>/dev/null; then
    mv -f "$dd/SHA512SUMS.$$" "$dd/SHA512SUMS"; base="$b"; break
  fi
done
[[ -n "$base" ]] || die "Debian $DEBIAN_VERSION live isn't on cdimage.debian.org (current or archive)."
rm -f "$dd/SHA512SUMS.sign"
download "$base/SHA512SUMS.sign" "$dd/SHA512SUMS.sign"
assert_sig 'Debian SHA512SUMS' "$KEY_DEBIAN" -- --verify "$dd/SHA512SUMS.sign" "$dd/SHA512SUMS"
download "$base/$ISO" "$dd/$ISO"
assert_hash "$dd/$ISO" "$(sum_for "$dd/SHA512SUMS" "$ISO")" 512
ISO_PATH="$dd/$ISO"

step "restic $RESTIC_VERSION"
rd="$DOWNLOADS/restic-$RESTIC_VERSION"; mkdir -p "$rd"
rbase="https://github.com/restic/restic/releases/download/v$RESTIC_VERSION"
download "$rbase/SHA256SUMS" "$rd/SHA256SUMS"
download "$rbase/SHA256SUMS.asc" "$rd/SHA256SUMS.asc"
assert_sig 'restic SHA256SUMS' "$KEY_RESTIC" -- --verify "$rd/SHA256SUMS.asc" "$rd/SHA256SUMS"
for f in "restic_${RESTIC_VERSION}_linux_amd64.bz2" "restic_${RESTIC_VERSION}_darwin_arm64.bz2" \
         "restic_${RESTIC_VERSION}_darwin_amd64.bz2" "restic_${RESTIC_VERSION}_windows_amd64.zip"; do
  download "$rbase/$f" "$rd/$f"
  assert_hash "$rd/$f" "$(sum_for "$rd/SHA256SUMS" "$f")" 256
done

step "rclone $RCLONE_VERSION"
cd_="$DOWNLOADS/rclone-$RCLONE_VERSION"; mkdir -p "$cd_"
cbase="https://downloads.rclone.org/v$RCLONE_VERSION"
download "$cbase/SHA256SUMS" "$cd_/SHA256SUMS.signed"
# Clearsigned: take the hashes from what gpg says was signed, never from the
# file itself, where unsigned lines could sit around the signed block.
assert_sig 'rclone SHA256SUMS' "$KEY_RCLONE" -- -o "$WORK/rclone-SHA256SUMS" --decrypt "$cd_/SHA256SUMS.signed"
for f in "rclone-v$RCLONE_VERSION-linux-amd64.zip" "rclone-v$RCLONE_VERSION-osx-arm64.zip" \
         "rclone-v$RCLONE_VERSION-osx-amd64.zip" "rclone-v$RCLONE_VERSION-windows-amd64.zip"; do
  download "$cbase/$f" "$cd_/$f"
  assert_hash "$cd_/$f" "$(sum_for "$WORK/rclone-SHA256SUMS" "$f")" 256
done

step "KeePassXC $KEEPASSXC_VERSION"
kd="$DOWNLOADS/keepassxc-$KEEPASSXC_VERSION"; mkdir -p "$kd"
kbase="https://github.com/keepassxreboot/keepassxc/releases/download/$KEEPASSXC_VERSION"
APPIMAGE="KeePassXC-$KEEPASSXC_VERSION-x86_64.AppImage"
WINZIP="KeePassXC-$KEEPASSXC_VERSION-Win64.zip"
DMG_ARM="KeePassXC-$KEEPASSXC_VERSION-arm64.dmg"
DMG_X86="KeePassXC-$KEEPASSXC_VERSION-x86_64.dmg"
for f in "$APPIMAGE" "$WINZIP" "$DMG_ARM" "$DMG_X86"; do
  download "$kbase/$f.sig" "$kd/$f.sig"
  download "$kbase/$f" "$kd/$f"
  ( assert_sig "$f" "$KEY_KEEPASSXC" -- --verify "$kd/$f.sig" "$kd/$f" ) || { rm -f "$kd/$f"; exit 1; }
done

step "Ventoy LiveInjection $LI_VERSION"
ld="$DOWNLOADS/live-injection-$LI_VERSION"; mkdir -p "$ld"
LI_TAR="live-injection-$LI_VERSION.tar.gz"
download "https://github.com/ventoy/LiveInjection/releases/download/$LI_VERSION/$LI_TAR" "$ld/$LI_TAR"
assert_hash "$ld/$LI_TAR" "$LI_SHA256" 256

# ── stage: the tree exactly as it goes on the stick ──────────────────────────
step 'Staging the tools'
STAGE="$CACHE/stage"
rm -rf "$STAGE"
T="$STAGE/tools"
mkdir -p "$T/linux-amd64" "$T/windows-amd64" "$T/darwin-arm64" "$T/darwin-amd64"
for p in linux_amd64 darwin_arm64 darwin_amd64; do
  bzip2 -dc "$rd/restic_${RESTIC_VERSION}_$p.bz2" > "$T/${p/_/-}/restic"
  chmod 755 "$T/${p/_/-}/restic"
done
unzip -q -o -j "$rd/restic_${RESTIC_VERSION}_windows_amd64.zip" '*.exe' -d "$WORK/restic-win"
mv "$WORK/restic-win/"*.exe "$T/windows-amd64/restic.exe"
for pair in linux-amd64:linux-amd64 osx-arm64:darwin-arm64 osx-amd64:darwin-amd64; do
  unzip -q -o -j "$cd_/rclone-v$RCLONE_VERSION-${pair%%:*}.zip" '*/rclone' -d "$T/${pair#*:}"
  chmod 755 "$T/${pair#*:}/rclone"
done
unzip -q -o -j "$cd_/rclone-v$RCLONE_VERSION-windows-amd64.zip" '*/rclone.exe' -d "$T/windows-amd64"
copy "$kd/$APPIMAGE" "$T/linux-amd64/$APPIMAGE"; chmod 755 "$T/linux-amd64/$APPIMAGE"
copy "$kd/$DMG_ARM" "$T/darwin-arm64/$DMG_ARM"
copy "$kd/$DMG_X86" "$T/darwin-amd64/$DMG_X86"
# The zip holds one KeePassXC-<ver>-Win64 folder; copy what's inside it.
mkdir -p "$WORK/kpx"
unzip -q -o "$kd/$WINZIP" -d "$WORK/kpx"
inner="$WORK/kpx"
if [[ "$(find "$WORK/kpx" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 1 ]] \
   && [[ -d "$(find "$WORK/kpx" -mindepth 1 -maxdepth 1)" ]]; then
  inner="$(find "$WORK/kpx" -mindepth 1 -maxdepth 1)"
fi
copy_tree "$inner" "$T/windows-amd64/KeePassXC"
copy "$HERE/RECOVERY.md" "$STAGE/RECOVERY.md"

# Ventoy LiveInjection, packed the way its pack.sh does: an outer archive
# holding a live_injection_<id>/ folder with the framework's hook.sh and
# distro/ hooks, plus sysroot.tar.gz (our live/ files, copied over / at boot).
step 'Staging the live-system injection'
li="$WORK/li"; mkdir -p "$li/out/$LI_ID" "$li/sys"
tar -xzf "$ld/$LI_TAR" -C "$li"
li_src="$li/live-injection-$LI_VERSION/internal"
[[ -f "$li_src/hook.sh" && -d "$li_src/distro" ]] || die "$LI_TAR doesn't have internal/hook.sh and distro/ where expected."
cp "$li_src/hook.sh" "$li/out/$LI_ID/"
cp -R "$li_src/distro" "$li/out/$LI_ID/"
cp -R "$HERE/live" "$li/sys/sysroot"
# Modes as the live system needs them, whatever the checkout or umask did;
# owned by root in the archive, whoever built it.
find "$li/sys/sysroot" -type d -exec chmod 755 {} +
find "$li/sys/sysroot" -type f -exec chmod 644 {} +
find "$li/sys/sysroot/usr/local/bin" "$li/sys/sysroot/usr/local/sbin" -type f -exec chmod 755 {} +
if tar --version 2>/dev/null | grep -q bsdtar; then
  ROOT_OWNED=(--uid 0 --gid 0 --uname root --gname root)
else
  ROOT_OWNED=(--owner=0 --group=0 --numeric-owner)
fi
tar "${ROOT_OWNED[@]}" -czf "$li/out/$LI_ID/sysroot.tar.gz" -C "$li/sys" sysroot
mkdir -p "$STAGE/ventoy"
tar "${ROOT_OWNED[@]}" -czf "$STAGE/ventoy/flask_injection.tar.gz" -C "$li/out" "$LI_ID"
# make-flask owns ventoy.json: it points the injection at this build's ISO.
printf '%s\n' '{' '    "injection": [' \
  "        { \"image\": \"/$ISO\", \"archive\": \"/ventoy/flask_injection.tar.gz\" }" \
  '    ]' '}' > "$STAGE/ventoy/ventoy.json"
say "  ventoy/flask_injection.tar.gz: $(find "$HERE/live" -type f | wc -l | tr -d ' ') files into the live system"

printf '%s\n' \
  "flask built $(date +%Y-%m-%d) by recovery/make-flask.sh on $(uname -s)" \
  "Debian Live $DEBIAN_VERSION (xfce)   $ISO" \
  "restic      $RESTIC_VERSION" \
  "rclone      $RCLONE_VERSION" \
  "KeePassXC   $KEEPASSXC_VERSION" \
  "Ventoy LiveInjection $LI_VERSION (mount-flask, flask-keepassxc, restic/rclone wrappers)" \
  "Every file was checked against its project's signed checksums; SHA256SUMS lists them all." \
  > "$STAGE/VERSIONS.txt"
say "  staged in $STAGE"

if [[ $MODE == prepare ]]; then
  say ''
  say 'Everything downloaded and verified. Plug in the sticks and run ./make-flask.sh to write them.'
  exit 0
fi

# ── write each stick ─────────────────────────────────────────────────────────
STAGE_SUMS="$(tree_sums "$STAGE")"
ISO_SUM="$(sha256 "$ISO_PATH")"
while IFS="$(printf '\t')" read -r label root disk; do
  step "Writing $label ($root, $disk)"
  # tools/ is replaced (old versions go); nothing else on the stick is removed
  # except older Debian ISOs. flask.kdbx is never touched.
  rm -rf "$root/tools"
  copy_tree "$STAGE/tools" "$root/tools"
  copy "$STAGE/RECOVERY.md" "$root/RECOVERY.md"
  copy "$STAGE/VERSIONS.txt" "$root/VERSIONS.txt"
  # ventoy/ isn't replaced: anything else kept there (another plugin's config)
  # stays. Only our two files are written.
  mkdir -p "$root/ventoy"
  copy "$STAGE/ventoy/ventoy.json" "$root/ventoy/ventoy.json"
  copy "$STAGE/ventoy/flask_injection.tar.gz" "$root/ventoy/flask_injection.tar.gz"
  for old in "$root"/debian-live-*.iso; do
    if [[ -f "$old" && "$(basename "$old")" != "$ISO" ]]; then rm -f "$old"; fi
  done
  if [[ ! -f "$root/$ISO" ]] || [[ "$(sha256 "$root/$ISO")" != "$ISO_SUM" ]]; then
    say "  copying $ISO (a few minutes)"
    copy "$ISO_PATH" "$root/$ISO"
  fi
  { printf '%s  %s\n' "$ISO_SUM" "$ISO"; printf '%s\n' "$STAGE_SUMS"; } > "$root/SHA256SUMS"
  if [[ $OS == mac ]]; then
    # Spotlight would index the stick and leave its database there.
    touch "$root/.metadata_never_index"
    mdutil -i off "$root" >/dev/null 2>&1 || true
  fi
  sync
  # Read everything back from the stick: a bad write shows up now, not on the worst day.
  check_stick "$label" "$root" \
    || die "$label doesn't read back what was written. Try another USB port; if it happens again, replace the stick."
done <<< "$STICKS"

step 'Vaults'
compare_vaults <<< "$STICKS"
say ''
say 'Done. Next (docs/recovery-kit.md): fill flask.kdbx on A (fill-vault.sh), copy it to B,'
say 'run ./make-flask.sh --check, then eject both before pulling them out.'
