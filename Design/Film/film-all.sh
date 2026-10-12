#!/bin/zsh
# film-all.sh <percent> <outdir>: renders every shot, then cuts them together with short dissolves.
W=${0:h}; B=/Applications/Blender.app/Contents/MacOS/Blender; out=$2; mkdir -p $out
shots=(open track build finish fail close)
for sh in $shots; do
  [[ -n $(ls $out/${sh}_*.png(N)) ]] || $B -b $W/nudge.blend --python $W/film.py -- $sh $1 $out > $out/$sh.log 2>&1
  ffmpeg -loglevel error -y -framerate 30 -i $out/${sh}_%04d.png -vf "crop=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -crf 14 -pix_fmt yuv420p $out/$sh.mp4
done
# 0.4 s dissolves between shots, fade up from and down to black
python3 - $out <<'PY'
import subprocess, sys, json
out = sys.argv[1]; shots = ['open','track','build','finish','fail','close']; X = 0.4
durs = [float(subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','json',f'{out}/{s}.mp4'],capture_output=True,text=True).stdout and json.loads(subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','json',f'{out}/{s}.mp4'],capture_output=True,text=True).stdout)['format']['duration']) for s in shots]
args = []; [args.extend(['-i', f'{out}/{s}.mp4']) for s in shots]
f = []; prev = '[0]'; t = durs[0]
for i in range(1, len(shots)):
    t -= X; lab = f'[v{i}]'
    f.append(f'{prev}[{i}]xfade=transition=fade:duration={X}:offset={t:.3f}{lab}'); prev = lab; t += durs[i]
f.append(f'{prev}fade=t=in:st=0:d=0.6,fade=t=out:st={t-0.8:.3f}:d=0.8[out]')
subprocess.run(['ffmpeg','-loglevel','error','-y',*args,'-filter_complex',';'.join(f),'-map','[out]','-c:v','libx264','-crf','16','-pix_fmt','yuv420p',f'{out}/nudge-film.mp4'], check=True)
print('film', round(t,2), 's')
PY
