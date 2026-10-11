#!/bin/zsh
# ingest.sh: trims record-strip.sh's takes into the app's bar clips. The app plays a real
# recording when it finds one (BarAgentsArriving, BarAlert, BarCPU) and its stand-in otherwise.
F=${0:A:h}; R=$F/../../Nudge/Resources/Welcome
t() { [[ -f $F/recordings/$1.mp4 ]] && ffmpeg -loglevel error -y -ss $2 -i $F/recordings/$1.mp4 -t $3 -c:v libx264 -crf 12 -pix_fmt yuv420p $R/$4.mp4 && echo "$4 ← $1"; }
t agents-arrive 0.4 11 BarAgentsArriving
t textedit-alert 2.5 5 BarAlert
t finder-cpu 0.5 6.5 BarCPU
