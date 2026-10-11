# The Touch Bar film

The Welcome guide's film and stills (`Nudge/Resources/Welcome`) are renders of a MacBook Pro model
with real recordings of Nudge's Touch Bar on its bar.

1. **Record the bar.** `record.sh <name> <seconds>` captures the real Touch Bar (`screencapture -b`,
   about 25 fps) into `recordings/<name>.mp4`. Stage the state first: put an app in front, then
   `demo.py <id> <agent> <event> …` writes a fake session Nudge picks up (`demo.py x x remove`
   clears them), `quiet.py` shows the real sessions idle, and a real `xcodebuild` makes the build
   flashes. Trim takes into `clips/`, starting and ending on the same state so they loop.
2. **Build the scene.** `setup.sh "<model>/Macbook Pro.blend"` opens the lid, puts the clip on the
   bar as an emissive screen, adds the bezel lettering, a black surface and the lights.
3. **Render.** `film-all.sh <percent> renders/` renders the shots in `film.py` with EEVEE (about
   1–2 s a frame at 40%, 6 s at 75%) and cuts them with dissolves into `renders/nudge-film.mp4`.
4. **Bake.** `bake.sh renders/nudge-film.mp4 WelcomeFilm.mp4 0.16 0.22 0.22` blurs and fades the
   edges into pure black; `stills.sh renders <out>` grabs and bakes the poster and page stills.

## The live bar

Most pages don't play the film: they show a **plate**, a render with the Touch Bar switched off,
and the app draws onto its bar (`TouchBarStage`): a recording of the real bar, real pieces of
captured strips, or controls that follow your choices (`LiveBars.swift`).

5. **Plates.** `plates.py <dir> 100 [Bar,Strip,Right,Wide]` renders each framing with Cycles and
   writes where the bar's screen lands in it; `plates-bake.py <dir> ../../Nudge/Resources/Welcome`
   crops them around the bar, bakes their edges into black and writes `Plates.json`.
6. **The strip.** `record-strip.sh` records what needs the strip open or a state that can't happen
   on demand (sessions arriving, the Project tab, a memory alert, a CPU heads-up). It drives a
   copy of Nudge launched with `-NudgeDemoControl YES` through `nudge-demo` (`open`, `close`,
   `tab <n>`, `scroll start|end`, `pulse alert|cpu|off`), quits and restores yours, and keeps your
   sessions and settings out of it. Keep touching the trackpad while it runs: the Touch Bar
   switches off when the Mac is idle, and only a real touch wakes it. Then `ingest.sh` trims the
   takes into the app's clips.
