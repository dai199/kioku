#!/bin/sh
# SNS共有用のカード画像（1200×630）を作る。
#
# HTMLをそのまま描画して撮る。文字は文字のまま持てるので、
# 文言や色を直したいときはテンプレートを1つ書き換えれば済む。
# 2倍で描いてから縮めるのは、縮小表示されても字が潰れないようにするため。
set -eu

cd "$(dirname "$0")/.."
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cp sites/icon-512.png "$work/"

render() {   # 出力名 タグライン 脚注
    sed -e "s|{{TAGLINE}}|$2|" -e "s|{{FOOT}}|$3|" Scripts/og.html > "$work/og.html"
    "$chrome" --headless --disable-gpu --hide-scrollbars \
        --force-device-scale-factor=2 --window-size=1200,630 \
        --screenshot="$work/raw.png" "file://$work/og.html" 2>/dev/null
    magick "$work/raw.png" -resize 1200x630 -strip "sites/$1"
}

render og.png "Translate what you read.<br>Remember what matters." "kioku.tagamidaiki.com"
render og-ja.png "読んだ英語を、覚えている英語に。" "kioku.tagamidaiki.com"

magick identify -format "%f %wx%h %b\n" sites/og.png sites/og-ja.png
