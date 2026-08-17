#!/bin/sh
# サイト用スクリーンショットをライト・ダークの2周で撮る。
#
# ポップアップの撮影ではテキストエディットを相手にするので、
# その見た目と書式を撮影のあいだだけ揃える。設定はユーザーのものなので必ず戻す。
#
# ダークの絵はシステムの外観がダークのときだけ正しく撮れる
# （アプリを個別にダークへ倒す設定は用意されていない）。
set -eu

domain=com.apple.TextEdit
backup=$(mktemp -t textedit-prefs)
defaults export "$domain" "$backup"

restore() {
    defaults import "$domain" "$backup"
    rm -f "$backup"
    rm -f .shot-appearance
}
trap restore EXIT INT TERM

# 見本はプレーンテキストで開く。書式バーやルーラが写り込まず、
# 表示フォントもここで決められるので、利用者の設定に絵が左右されない
defaults write "$domain" RichText -bool false
defaults write "$domain" NSFixedPitchFont -string HiraginoSans-W3
defaults write "$domain" NSFixedPitchFontSize -int 20

for mode in light dark; do
    if [ "$mode" = light ]; then
        defaults write "$domain" NSRequiresAquaSystemAppearance -bool true
    else
        defaults delete "$domain" NSRequiresAquaSystemAppearance 2>/dev/null || true
    fi
    killall TextEdit 2>/dev/null || true
    echo "$mode" > .shot-appearance
    echo "==> $mode"
    "$@"
done
