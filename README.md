# cat game (prototype)

first person cat puzzle game, godot 4.3. everything is procedural (no imported assets yet):
the cat model, its animation, the level.

open the folder in godot 4.3+ and hit play (f5).

## controls
- wasd moves relative to where you look (same as the orbit cam in every view), the cat turns to run that way and its head follows your look. backing up is slow, a/d = short sideways hop, hold shift = canter (6 m/s), double tap shift + hold = full gallop (11 m/s), ctrl/c stalk (crouch)
- space: hop (1 m), in the air next to a wall: wall kick (2 per jump)
- grip: paws only push so hard. wood/tile is slippy, carpet/rug grippy, grass in between. hard turns or stops at speed make the cat skid, scrabble and tear up grass/dirt/hay
- hunting: crouch to stalk (hud shows pounce range), pounce onto prey or claw it to catch, it sits in the cat's mouth, e drops it. swats stun prey, and things close to the crosshair get auto swatted
- default cat is a black cat with yellow eyes, 1-9 swaps coats
- push into a wall while falling: claws out, slow wall slide
- hold space while running into a wall in the air: scramble up it
- hold c + hold space, release: charged pounce (0.6 to 1.8 m)
- mouse1: swat with a random paw, auto aims at the loose thing nearest the crosshair, real impulse (light stuff flies, barrels barely rock)
- hold mouse2: claws out. hook a loose object and drag it around by looking, let go to fling. on a surface the claws dig in and drag marks

## parkour (the easy way)
- hold q (or mouse3), look where you want to be, let go: the cat crouches, wiggles and leaps
  on a real ballistic arc that lands exactly there (green ring + arc preview, red = can't reach)
- look at the side of a table/counter/fridge and it finds the top for you
- too high to land on (up to ~2.2 m)? the ring turns yellow: it leaps to grab the edge,
  hangs on the forepaws, hind paws scrabble, and it hauls itself up (hold w, or s/c to let go)
- run or jump into a low ledge (< 0.3 m) and it just hops up; up to 0.85 m it grabs + clambers
- jump at anything rough holding w (cat tree post, sisal post, curtains): claws in, climb.
  w up (in bounds), s down, a/d sideways, space leaps off backwards, c lets go.
  climbing into an overhang (a perch) reaches around the lip and pulls up onto it
- f (hold) facing a wall/couch/post: stand up and scratch. leaves claw marks, fluff flies off soft stuff
- pounce (c + space, or an aimed leap): forepaws slam down together and pin whatever is under them.
  there's a wind up toy mouse to hunt: stalk slow (rushing spooks it), aim at it, pounce
- v: third person (see the whole cat), esc: free the mouse

## numbers (real cat scale, meters)
- body 0.46 m, shoulder 0.25 m, eye height 0.25 m
- stalk 0.7 m/s, trot 3.2 m/s, canter 6 m/s, gallop 11 m/s (~40 km/h)
- gravity 9.8, hop 1.0 m, pounce up to 1.8 m

## files
- `scripts/cat_rig.gd` procedural low poly cat + ik gait system: walk/trot/gallop/climbing bound,
  single track paw placement, wrist flick + heel lift, scapula ride, front first landings,
  spring chain tail, stretch/groom/loaf/scratch/hang/climb/pin poses (5 model styles, one rig)
- `scripts/toy_mouse.gd` prey toy
- `scripts/paw_view.gd` first person front legs
- `scripts/cat_player.gd` movement controller
- `scripts/level.gd` living room gym + gait reference studio
- `scripts/npc_cat.gd` wandering cats
- `scripts/preview.gd` scripted showcase (run with `godot -- --preview`, add `--showcase` for
  the slow-mo animation study + parkour run, `--posetest` for a row of pose stills)

## animation (footfall solver)
- `scripts/cat_gait.gd` plants every paw at a fixed spot in the world and only moves it when it lifts.
  the body (shoulder and hip height, rock, lean, shoulder blades, head) is solved from the planted paws
  in `cat_rig.gd animate()`. gait timing comes from real cat numbers: stride length and time on the
  ground by speed, walk to trot is a smooth change, gallop kicks in above 3.9 m/s (so the default 3.2 run is a trot)
- paws find the ground with a ray (steps, cushions), re-step when the body turns on the spot,
  and settle after a stop. first person paws follow the same planted paws
- `CatRig.use_planting = false` gives the old cheap legs back
- gait lab: `godot --path . res://gaitlab.tscn -- --only walk,trot,run,turn --view side --slow 0.5 --report out.json`
  drives a cat over a checker floor and prints paw slide, time on ground, stride rate, head steadiness

## views + levels

- v cycles first person, third person and orbit cam. in orbit, the mouse orbits the cat, the scroll wheel zooms, wasd is camera relative and the cat turns to face where it goes. the camera never clips through walls.
- the gap in the west yard fence (and f6) goes to the forest level. f7 goes to the stealth level.

## forest (res://forest.tscn)
walk out the gap in the west yard fence (or f6 from the main map). f5 / the gate behind you goes back.
- `scripts/forest_level.gd` 80 x 80 m valley: stream + stepping stones, log bridge, pond, meadow, rock outcrop
  with ledges, ~95 pines/oaks/birches (trunks + limbs climbable, limbs are perches), fallen + hollow logs,
  stumps, a deer stand with a ladder, bushes to hide in
- `scripts/wildlife.gd` (Critter) deer, rabbits, birds, squirrels, foxes, frogs, butterflies, each with a
  small state machine that reads the cat's distance / speed / crouch / height. stalk to sneak up, rush to scatter them
- `scripts/field_mouse.gd` huntable prey (pounce = caught)
- t teleports between landmarks. `-- --tour` renders the flythrough

## install + auto updates (windows)

- grab **CatGame-Setup.exe** from the [latest release](https://github.com/ArthurJClack/catgame/releases/latest) and run it.
  one click, no admin prompt: it installs to `%LOCALAPPDATA%\Programs\CatGame`, adds a start menu +
  desktop shortcut and starts the game. it's not code signed yet, so windows smartscreen may say
  "windows protected your pc": hit "more info" then "run anyway".
- the installed game checks github releases on launch. if there's a newer one it downloads it in the
  background while you play (little banner top right). then f9 restarts into the new version, or just quit
  and it installs silently on the way out. offline / no release / anything weird = it quietly keeps the
  version you have. skip the check with `CatGame.exe -- --no-update`.
- it never runs in the editor, the web build or preview renders.

### how releases happen

`.github/workflows/release.yml`: every push to `main` exports the windows build with godot 4.3, wraps it
in an inno setup installer (`installer/catgame.iss`) and publishes release `v0.1.<run number>` with
`CatGame-Setup.exe` + a plain `CatGame-windows.zip`. merge a pr = everyone gets it next launch. pull requests
build the installer too (download it from the run's artifacts) but don't publish. readme-only pushes are skipped.

- updater: `scripts/updater.gd` (autoload `Updater`), version lives in `application/config/version`
  (ci stamps it, the repo copy stays `0.1.0`)
- logic test: `godot --headless --path . -s tests/updater_test.gd`
