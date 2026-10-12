#!/bin/bash
# seed-live-photo.sh <out dir> [UDID] — makes a 3 s Live Photo pair (IMG_<n>.JPG + IMG_<n>.MOV sharing one content identifier)
# in <out dir> and, with a UDID, adds it to that simulator's Photos. Needs ffmpeg and swiftc. Recipe found in a pilot run:
# the still carries the id in the Apple maker note key 17 (mkstill.swift), the MOV in com.apple.quicktime.content.identifier plus
# a still-image-time timed metadata track (mkmov.swift). A MOV with only the content identifier imports as a separate video.
# Check in Photos.sqlite: ZASSET.ZKINDSUBTYPE = 2 and ZPLAYBACKSTYLE = 3 mean Live Photo.
set -euo pipefail
out=${1:?usage: seed-live-photo.sh <out dir> [UDID]}; udid=${2:-}
here=$(cd "$(dirname "$0")" && pwd); mkdir -p "$out/bin"
for tool in mkstill mkmov; do
  [ "$out/bin/$tool" -nt "$here/$tool.swift" ] || swiftc -O -o "$out/bin/$tool" "$here/$tool.swift"
done
id=$(uuidgen); n=$((9000 + RANDOM % 999)); raw="$out/raw-$n"
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=1080x1440:rate=30:duration=3" -pix_fmt yuv420p -c:v libx264 "$raw.mov"
ffmpeg -loglevel error -y -i "$raw.mov" -frames:v 1 "$raw.jpg"
"$out/bin/mkstill" "$raw.jpg" "$out/IMG_$n.JPG" "$id"
"$out/bin/mkmov" "$raw.mov" "$out/IMG_$n.MOV" "$id" >/dev/null
rm -f "$raw.mov" "$raw.jpg"
[ -n "$udid" ] && xcrun simctl addmedia "$udid" "$out/IMG_$n.JPG" "$out/IMG_$n.MOV"
echo "$out/IMG_$n.JPG $out/IMG_$n.MOV"
