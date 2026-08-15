#!/usr/bin/env bash
set -euo pipefail

AUDIO_BITRATE=192k

usage() {
    echo "用法: $0 <视频文件或目录>"
    echo "  用 NVENC 把同名 .ass 字幕压制进视频, 输出同名 .mp4"
    exit 1
}

log() { echo -e "\033[36m[burn]\033[0m $*"; }
err() { echo -e "\033[31m[burn]\033[0m $*" >&2; }

[ $# -ge 1 ] || usage
command -v ffmpeg >/dev/null || { err "未找到 ffmpeg"; exit 1; }
encoders="$(ffmpeg -hide_banner -encoders 2>/dev/null)"
case "$encoders" in
    *h264_nvenc*) ;;
    *) err "ffmpeg 未编译 h264_nvenc, 无法使用 GPU 压制"; exit 1 ;;
esac

fc-match "Noto Sans CJK SC" | grep -qi "Noto Sans SC" || \
    err "警告: 未找到 Noto Sans SC 字体, 中文字幕可能显示为方框"

mapfile -t targets < <(for arg in "$@"; do
    if [ -d "$arg" ]; then
        find "$arg" -maxdepth 1 -name "*.mkv" -o -maxdepth 1 -name "*.mp4" -o -maxdepth 1 -name "*.avi" -o -maxdepth 1 -name "*.ts"
    else
        echo "$arg"
    fi
done | sort -u)

[ ${#targets[@]} -gt 0 ] || { err "没有找到视频文件"; exit 1; }

for video in "${targets[@]}"; do
    sub="${video%.*}.ass"
    out="${video%.*}.mp4"

    [ -f "$video" ] || { err "跳过: 文件不存在 $video"; continue; }
    [ -f "$sub" ] || { err "跳过: 未找到字幕 $sub"; continue; }
    [ -f "$out" ] && { log "跳过: 已存在 $out"; continue; }

    log "压制: $video"
    log "  字幕: $sub"
    if ffmpeg -v error -stats -y \
        -hwaccel cuda \
        -i "$video" \
        -vf "ass='${sub}':fontsdir=" \
        -c:v h264_nvenc -preset p5 -tune hq -rc vbr -cq 28 -b:v 0 -maxrate 12M -bufsize 16M \
        -c:a aac -b:a "$AUDIO_BITRATE" \
        -movflags +faststart \
        "$out"; then
        log "完成: $out"
    else
        err "失败: $video"
        rm -f "$out"
    fi
done

log "全部完成"
