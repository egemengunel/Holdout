#!/bin/zsh
# stills.sh <shotdir> <outdir>: grabs frames from the rendered film for the guide: the film's
# poster (shown under Reduce Motion) and the setup page's banner.
W=${0:h}; d=$1; o=$2; mkdir -p $o/raw
grab() { ffmpeg -loglevel error -y -ss $3 -i $d/$1.mp4 -frames:v 1 ${4:+-vf} ${4:+$4} $o/raw/$2.png; }
banner="crop=iw:iw/4:0:(ih-iw/4)/2"
grab open WelcomeSetup 4.6 $banner
grab open WelcomeFilmPoster 2.0
for n in WelcomeSetup; do $W/bake.sh $o/raw/$n.png $o/$n.jpg 0.14 0.18 0.5 still; done
$W/bake.sh $o/raw/WelcomeFilmPoster.png $o/WelcomeFilmPoster.jpg 0.16 0.22 0.22 still
