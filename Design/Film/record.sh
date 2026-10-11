#!/bin/zsh
zmodload zsh/datetime
# record.sh <name> <seconds>: captures the Touch Bar as fast as it can, then makes a 30 fps clip
out=${0:h}/recordings/$1; rm -rf $out; mkdir -p $out
[[ -x ${0:h}/wake ]] || swiftc -O ${0:h}/wake.swift -o ${0:h}/wake
${0:h}/wake; sleep 0.3
end=$(( $(date +%s) + $2 ))
i=0
while (( $(date +%s) < end )); do
  t=$EPOCHREALTIME
  screencapture -b -x $out/$(printf %05d $i)_$t.png; i=$((i+1))
done
# concat list with real per-frame durations
python3 - "$out" <<'PY'
import os,sys
d=sys.argv[1]; fs=sorted(f for f in os.listdir(d) if f.endswith('.png'))
ts=[float(f.split('_')[1][:-4]) for f in fs]
with open(os.path.join(d,'list.txt'),'w') as l:
    for i,f in enumerate(fs):
        dur = ts[i+1]-ts[i] if i+1<len(fs) else 1/30
        l.write(f"file '{f}'\nduration {dur:.4f}\n")
    l.write(f"file '{fs[-1]}'\n")
print(len(fs),'frames', f"{len(fs)/(ts[-1]-ts[0]):.1f} fps")
PY
ffmpeg -loglevel error -y -f concat -safe 0 -i $out/list.txt -vf "fps=30,format=yuv420p" -c:v libx264 -crf 12 ${0:h}/recordings/$1.mp4
