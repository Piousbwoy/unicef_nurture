#!/bin/bash
set -e
BIN="/c/Users/Alhaji_stunner/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-9.0.2-full_build/bin"
FF="$BIN/ffmpeg.exe"; FP="$BIN/ffprobe.exe"
D=/c/Users/Alhaji_stunner/demo
S=$D/shots; A=$D/audio; W=$D/work
cd "$W"

IMGS=("title.png" "$S/15_hub.png" "$S/19_saved.png" "$S/20_picker.png" "$S/22_q1.png" "$S/23_q2.png" "$S/27_result.png" "$S/30_asked.png" "$S/37_sync.png" "$S/61_patients.png" "$S/62_record.png" "$S/65_prio2.png" "closing.png")
CAPS=("CareBridge AI - the last mile, connected" "For caregivers, in their own language" "The family's own health record" "IMCI-aligned questions, conversational" "On-device voice - English, Dagbani, Hausa" "An alarm you can act on - never a dead end" "Do these now - even on the way" "A privacy-bounded request, queued for the network" "Offline-first sync - nothing is lost" "One workspace - the family reaches the health worker" "Honest confidence - what is known, what is missing" "The referral desk with a trace line" "Every handoff, accounted for")

"$FF" -y -f lavfi -i "color=c=0x0C2B73:s=1080x1920" -vf "drawtext=fontfile=arialbd.ttf:text='CareBridge AI':fontcolor=white:fontsize=92:x=(w-text_w)/2:y=760,drawtext=fontfile=arial.ttf:text='Every handoff, accounted for':fontcolor=0x7FA9FF:fontsize=44:x=(w-text_w)/2:y=880" -frames:v 1 title.png 2>/dev/null
"$FF" -y -f lavfi -i "color=c=0x0C2B73:s=1080x1920" -vf "drawtext=fontfile=arialbd.ttf:text='CareBridge AI':fontcolor=white:fontsize=92:x=(w-text_w)/2:y=740,drawtext=fontfile=arial.ttf:text='Recognition. Decision. Request. Handoff.':fontcolor=0xDCE9FF:fontsize=42:x=(w-text_w)/2:y=870,drawtext=fontfile=arial.ttf:text='A chain that survives the last mile.':fontcolor=0x7FA9FF:fontsize=42:x=(w-text_w)/2:y=930" -frames:v 1 closing.png 2>/dev/null

LIST="$W/concat.txt"
> "$LIST"
for i in $(seq 1 13); do
  idx=$((i-1))
  DUR=$("$FP" -show_entries format=duration -v quiet -of csv=p=0 "$A/beat_$(printf '%02d' $i).wav")
  T=$(awk "BEGIN{printf \"%.2f\", $DUR + 0.6}")
  CAP="${CAPS[$idx]}"
  "$FF" -y -loop 1 -i "${IMGS[$idx]}" -i "$A/beat_$(printf '%02d' $i).wav" \
    -vf "scale=-2:1740,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=0xF6F9FD,drawbox=x=0:y=1770:w=1080:h=150:color=0x0A1931@0.92:t=fill,drawtext=fontfile=arialbd.ttf:text='$CAP':fontcolor=white:fontsize=34:x=(w-text_w)/2:y=1822" \
    -t "$T" -c:v libx264 -pix_fmt yuv420p -r 30 -c:a aac -ar 44100 -ac 1 -shortest "clip_$i.mp4" 2>/dev/null
  echo "beat $i done (${T}s)"
  echo "file 'clip_$i.mp4'" >> "$LIST"
done

"$FF" -y -f concat -safe 0 -i concat.txt -c copy "$D/carebridge-pitch.mp4" 2>/dev/null
echo "== FINAL =="
ls -la "$D/carebridge-pitch.mp4"
