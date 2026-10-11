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
