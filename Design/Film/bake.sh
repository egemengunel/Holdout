#!/bin/zsh
# bake.sh <in> <out> <fadeX> <fadeTop> <fadeBottom> [still]: dissolves a render into pure black.
# Edges fade out (smoothstep over the given fractions of width/height) and blur progressively on the way.
in=$1; out=$2; fx=$3; ft=$4; fb=$5
read w h <<< "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $in | tr , ' ')"
ss() { echo "(st(0,clip(($1)/($2),0,1));ld(0)*ld(0)*(3-2*ld(0)))"; }
dx="min(X/W,1-X/W)"; top="Y/H"; bot="1-Y/H"
fade="255*$(ss $dx $fx)*$(ss $top $ft)*$(ss $bot $fb)"
# Sharp in the middle, blurred toward the edges: the blur mask leads the fade.
sharp="255*$(ss $dx "($fx*1.6)")*$(ss $top "($ft*1.6)")*$(ss $bot "($fb*1.6)")"
mk() { ffmpeg -loglevel error -y -f lavfi -i "color=black:s=${w}x${h},format=gray,geq=lum='$1'" -frames:v 1 $2; }
mk "$fade" ${out%.*}.fade.png; mk "$sharp" ${out%.*}.sharp.png
filter="[0]format=gbrp,split[a][b];[b]gblur=sigma=$(( w / 60 ))[bl];[1]format=gbrp[ms];[2]format=gbrp[mf];[bl][a][ms]maskedmerge[m];[m][mf]blend=all_mode=multiply,scale=out_color_matrix=bt709:out_range=tv,format=yuv420p[o]"
if [[ -n $6 ]]; then
  ffmpeg -loglevel error -y -i $in -i ${out%.*}.sharp.png -i ${out%.*}.fade.png -filter_complex "$filter" -map "[o]" -frames:v 1 -q:v 3 $out
else
  ffmpeg -loglevel error -y -i $in -i ${out%.*}.sharp.png -i ${out%.*}.fade.png -filter_complex "$filter" -map "[o]" -c:v libx265 -tag:v hvc1 -crf 24 -preset slow -pix_fmt yuv420p -color_primaries bt709 -color_trc bt709 -colorspace bt709 -an -movflags +faststart $out
fi
rm -f ${out%.*}.fade.png ${out%.*}.sharp.png
