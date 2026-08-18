#!/bin/sh
# サイト用のアイコン素材をアプリアイコンから作る。
#
# アプリとサイトで別々に絵を持つと必ずずれるので、`Assets/Kioku.icns` を唯一の出所にする。
# 生成物は sites/ に置いてコミットする（滅多に変わらないので配信時には作らない）。
#
# ImageMagick が要る:  brew install imagemagick
set -eu

cd "$(dirname "$0")/.."
out=sites
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

iconutil -c iconset Assets/Kioku.icns -o "$work/Kioku.iconset"
# macOSのアイコンは1024のキャンバスに824の作画（周囲は影のための余白）。
# サイトでは余白が要らないので作画だけ取り出す
magick "$work/Kioku.iconset/icon_512x512@2x.png" -trim +repage "$work/art.png"

field() { echo "$1" | sed -E 's/([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)/\1 \2 \3 \4/'; }

# 16pxでは吹き出しの線が潰れてKが読めなくなるので、この大きさだけ
# 「角丸＋白いK」に簡略化する。Kはアプリの絵から切り出すので書体は変わらない。
#
# 白と絵柄の切り分けは明度ではなく彩度で行う。地の色を変えても壊れないため
# （透明な角が白と誤判定されないよう、先に彩度の高い色で埋めておく）
magick "$work/art.png" -background red -alpha remove -alpha off "$work/flat.png"

set -- $(field "$(magick "$work/flat.png" -colorspace HSL -channel G -separate +channel \
  -threshold 25% -negate -format "%@" info:)")
bw=$1 bh=$2 bx=$3 by=$4
inside="$(( bw * 83 / 100 ))x$(( bh * 62 / 100 ))+$(( bx + bw * 9 / 100 ))+$(( by + bh * 9 / 100 ))"
magick "$work/flat.png" -crop "$inside" +repage "$work/inside.png"

# 吹き出しの内側で色が乗っている塊がK（尻尾は上側だけ見るので入らない）
set -- $(field "$(magick "$work/inside.png" -colorspace HSL -channel G -separate +channel \
  -threshold 25% -format "%@" info:)")
kw=$1 kh=$2 kx=$3 ky=$4
magick "$work/inside.png" -crop "${kw}x${kh}+${kx}+${ky}" +repage \
  -colorspace HSL -channel G -separate +channel -threshold 25% "$work/kmask.png"

# 板の色はアイコン自身から取る（塗り足しても色が浮かない）
size=$(magick "$work/art.png" -format "%w" info:)
top=$(magick "$work/art.png" -format "%[pixel:p{$(( size * 12 / 100 )),$(( size * 12 / 100 ))}]" info:)
bottom=$(magick "$work/art.png" -format "%[pixel:p{$(( size * 88 / 100 )),$(( size * 88 / 100 ))}]" info:)

# macOSのアイコンの角丸は一辺の約22.4%
magick -size 128x128 xc:black -fill white -draw "roundrectangle 0,0,127,127,29,29" "$work/mask.png"
magick -size 128x128 "gradient:$top-$bottom" "$work/mask.png" \
  -alpha off -compose CopyOpacity -composite "$work/plate.png"
kh16=74
kw16=$(( kw * kh16 / kh ))
magick -size "${kw16}x${kh16}" xc:white \
  \( "$work/kmask.png" -resize "${kw16}x${kh16}!" -alpha off \) \
  -compose CopyOpacity -composite "$work/kwhite.png"
magick "$work/plate.png" "$work/kwhite.png" -gravity center -composite \
  -resize 16x16 "$work/favicon-16.png"

magick \( "$work/art.png" -resize 48x48 \) \( "$work/art.png" -resize 32x32 \) \
  "$work/favicon-16.png" "$out/favicon.ico"

# 角丸の外側は透明なので、そのまま置くとiOSのマスク下で角が黒く出る。
# アイコン自身を拡大したものを下に敷いて埋める（色が必ず合う）
opaque() {
  magick \
    \( "$work/art.png" -resize "$(( $1 * 13 / 10 ))x$(( $1 * 13 / 10 ))" \
       -gravity center -extent "${1}x${1}" \) \
    \( "$work/art.png" -resize "${1}x${1}" \) \
    -gravity center -composite -alpha off "$2"
}

opaque 180 "$out/apple-touch-icon.png"
opaque 192 "$out/icon-192.png"
opaque 512 "$out/icon-512.png"

magick identify "$out/favicon.ico"
ls -l "$out"/apple-touch-icon.png "$out"/icon-192.png "$out"/icon-512.png
