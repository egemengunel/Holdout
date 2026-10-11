#!/bin/zsh
# stills.sh <shotdir> <outdir>: grabs frames from the rendered shots and bakes them for the guide.
W=${0:h}; d=$1; o=$2; mkdir -p $o/raw
grab() { ffmpeg -loglevel error -y -ss $3 -i $d/$1.mp4 -frames:v 1 ${4:+-vf} ${4:+$4} $o/raw/$2.png; }
banner="crop=iw:iw/4:0:(ih-iw/4)/2"
grab track WelcomeAgents 5.9 $banner
grab open WelcomeSetup 4.6 $banner
grab build WelcomeButtons 2.6 $banner
grab close WelcomeDone 4.9
grab open WelcomeFilmPoster 2.0
for n in WelcomeAgents WelcomeSetup WelcomeButtons; do $W/bake.sh $o/raw/$n.png $o/$n.jpg 0.14 0.18 0.5 still; done
$W/bake.sh $o/raw/WelcomeDone.png $o/WelcomeDone.jpg 0.16 0.22 0.4 still
$W/bake.sh $o/raw/WelcomeFilmPoster.png $o/WelcomeFilmPoster.jpg 0.16 0.22 0.22 still
