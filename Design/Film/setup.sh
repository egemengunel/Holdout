#!/bin/zsh
# setup.sh <path to "Macbook Pro.blend">: builds nudge.blend, the scene every shot renders from.
# The model (13" MacBook Pro 2020) isn't in the repo; its licence covers renders, not redistribution.
cd ${0:h}; B=/Applications/Blender.app/Contents/MacOS/Blender
F=/System/Library/Fonts/SFNS.ttf
ffmpeg -loglevel error -y -f lavfi -i "gradients=s=2880x1800:c0=0x0b1a3a:c1=0x3a1d5c:c2=0x0d3b4f:c3=0x1a0b2e:nb_colors=4:x0=0:y0=0:x1=2880:y1=1800:rate=1" -frames:v 1 -vf "gblur=sigma=60" wallpaper.png
$B -b "$1" --python scene/build.py -- $PWD/clips/1-typing-needs-you.mp4 $PWD/nudge.blend
$B -b nudge.blend --python scene/tune2.py -- $PWD/nudge.blend $PWD/wallpaper.png
$B -b nudge.blend --python scene/bezel.py -- $PWD/nudge.blend $F
for s in bezel2 stage relight; do $B -b nudge.blend --python scene/$s.py -- $PWD/nudge.blend; done
