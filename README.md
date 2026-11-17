# cat game (prototype)

first person cat puzzle game, godot 4.3. everything is procedural (no imported assets yet):
the cat model, its animation, the level.

open the folder in godot 4.3+ and hit play (f5).

## controls
- wasd moves relative to where you look (same as the orbit cam in every view), the cat turns to run that way and its head follows your look. backing up is slow, a/d = short sideways hop, hold shift = canter (6 m/s), double tap shift + hold = full gallop (11 m/s), ctrl/c stalk (crouch)
- space: hop (1 m), in the air next to a wall: wall kick (2 per jump)
- alt or mouse4: souls style dodge (`cat_dash.gd`). wasd toward the body = low dart, off to the side = startled side leap, behind = whirl round + dart, nothing held = backstep. committed once pressed, i-frames from the push off (`player.is_invulnerable()`), presses during the landing are buffered so dodges chain
- stamina bar (bottom centre, fades when full, `cat_stamina.gd`): hops, pounces, leaps, wall kicks, scrambles, swats and dodges cost a chunk, canter / gallop / climbing / claw dragging drain it while you do it. comes back after a ~0.75 s breather (full in ~2 s standing still). run it dry and the cat is winded: trot only until it's back over a third. bots get a bottomless bar unless their bot dict has `stamina: true`. tests: `-- --preview --dashtest` (headless), `--dashshow` renders the clip
- health + stamina bars top left (`souls_hud.gd`, `cat_health.gd`): health red over stamina green with pale "just lost" trails, nine lives (lose all your health = lose a life). dodge i-frames ignore hits
- f10: **the rat pit** (`arena.tscn`, `arena_main.gd`). waves of rats (`souls_rat.gd`) that can only bite what's in front of their face: a wind up tell (rears back, jaw open), a lunge, then a recovery where they can't turn. they turn slower than you can circle them, so circle, bait the bite, dodge through it, and swat them from behind (double damage + stagger). a pounce that lands on one is a heavy hit. wave 4 has a brute. r restarts. tests: `godot --headless --path . res://arena.tscn -- --arenatest`, `--arenashow` renders the clip
- grip: paws only push so hard. wood/tile is slippy, carpet/rug grippy, grass in between. hard turns or stops at speed make the cat skid, scrabble and tear up grass/dirt/hay
- hunting: crouch to stalk (hud shows pounce range), pounce onto prey or claw it to catch, it sits in the cat's mouth, e drops it. swats stun prey, and things close to the crosshair get auto swatted
- default cat is a black cat with yellow eyes, 1-9 swaps coats
- push into a wall while falling: claws out, slow wall slide
- hold space while running into a wall in the air: scramble up it
- hold c + hold space, release: charged pounce (0.6 to 1.8 m)
- paw combat (`cat_combat.gd`): mouse1 = left paw, mouse2 = right paw
  - tap: swat with that paw, auto aims at the loose thing nearest the crosshair, real impulse (light stuff flies, barrels barely rock)
  - hold: that paw keeps raking whatever's in front (a rake every 0.24 s, half a swat's damage + poise, 3 stamina each). nothing to rake = claws out instead: hook a loose object and drag it around by looking, let go to fling. on a surface the claws dig in and drag marks
  - hold both: the cat rears up on its hind legs, comes down with both fore paws on the target (heavy hit) and holds it pinned while both are held, claws squeezing every 0.4 s. a cat needs a free fore paw to walk, so while both hold it can't move, hop or dodge. let go of either to be free again. holding drains stamina, rats wriggle out after 1.6 s (the brute sooner), small prey pinned like this is caught. everything is x2 from behind
  - tests: `godot --headless --path . res://arena.tscn -- --combattest`, `--combatshow` renders the clip

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
- the gap in the west yard fence (and f6) goes to the forest level. f7 goes to the stealth level, f8 the running trail.

## forest (res://forest.tscn)
walk out the gap in the west yard fence (or f6 from the main map). f5 / the gate behind you goes back.
- `scripts/forest_level.gd` 80 x 80 m valley: stream + stepping stones, log bridge, pond, meadow, rock outcrop
  with ledges, ~95 pines/oaks/birches (trunks + limbs climbable, limbs are perches), fallen + hollow logs,
  stumps, a deer stand with a ladder, bushes to hide in
- `scripts/wildlife.gd` (Critter) deer, rabbits, birds, squirrels, foxes, frogs, butterflies, each with a
  small state machine that reads the cat's distance / speed / crouch / height. stalk to sneak up, rush to scatter them.
  panic spreads: one bird going up takes the flock, a bolting rabbit freezes the others (`alarmed()`)
- `scripts/fauna.gd` (Fauna, extends Critter) a duck pair with ducklings on the pond, dragonflies, hedgehogs that
  ball up (and roll when nudged), grasshoppers that ping out of the grass ahead of you, a hawk that circles and
  stoops at rabbits (everything in the open scatters), woodpeckers, crows that keep their distance and mob the cat
  when it's up a tree or carrying prey, lizards on the rocks, owls and bats for the night
- `scripts/swarms.gd` fish shoals, bees on the flowers, ant trails, fireflies and moths (one multimesh each)
- `scripts/field_mouse.gd` huntable prey (pounce = caught). dragonflies, grasshoppers and lizards are huntable too
- `scripts/atmos.gd` sky + sun + clouds + fog + grading and the time of day (a day is ~30 min, **n** skips ahead:
  sunset, stars and fireflies, sunrise). `scripts/foliage.gd` grass that sways and bends away from the cat, flowers,
  reeds, lily pads. `scripts/water.gd` depth tinted water with bank foam and ripples (`Water.splash(pos)`)
- `scripts/soundscape.gd` all sound is synthesised at load: wind, stream, birdsong, crickets, frogs, owl, and the
  calls the animals make (`Soundscape.play(name, pos)`). **m** mutes
- t teleports between landmarks. `-- --tour` renders the flythrough. wildlife camera for checks:
  `-- --watch duck --poke 4 --log` films an animal while a stand-in cat walks up to it (`--rush`, `--crouch`,
  `--hour 21`, `--zoo` lines up the models, `--perf` prints script cost per frame)

## trail (res://trail.tscn)
f8 from the house. a ~137 m loop of dirt singletrack built to show off running: fine grained ground
(0.5 m terrain grid with ruts and lumps, gravel, pebbles, leaf litter, twigs, moss) and sections of small stuff:
roots under old oaks, fallen logs across the path, a rock garden with flat slabs, stone steps up a ridge,
drop offs down the far side, a creek ditch, then a debris mix of stumps, logs, rocks and branches.
- running over rough ground (`scripts/run_assist.gd`, on for the player everywhere, `auto_bound`):
  - roots, branches and stone lips up to 11 cm: the body glides up while the paws step (no jump)
  - at a run (> 1.1 m/s) anything bigger up to 60 cm, or a ditch: the cat reads the ground ahead, finds the
    smallest real ballistic arc that clears it (or lands on top when the top is flat and wide enough)
    and launches at the spot that arc needs, so it keeps its pace. the rig does the takeoff + landing
  - taller than that it runs into it and the old mantle / clamber takes over
- r restart · t next section · b auto bound on/off · f5 back to the house
- `-- --runtest` (headless ok): a bot runs a lap and prints every bound and anywhere it got stuck
  (`TRAIL_DBG=s0,s1` prints the ground read between those trail distances). `-- --run` = preview video

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

## multiplayer (steam lobbies)

press **m** in game. other players show up as full cats, animated by the same procedural rig as yours.

- **host (friends)** makes a friends-only lobby, **host (public)** one anyone can find. **invite friends**
  opens the steam overlay invite list (shift+tab works too). friends accept the invite in steam and land
  in your lobby. **refresh** lists public / friends' lobbies, **join** hops in. **go to them** takes you to
  the level a friend is in (house / forest / docks): you only see cats in the same level as you.
- name tags float over everyone's cat. "x joined" / "x left" shows in the middle of the screen.
- needs steam running and logged in on every pc. no steam? lan / direct ip works too:
  host runs `CatGame.exe -- --net-host`, friends run `CatGame.exe -- --net-join <host ip>` (udp 24680,
  `--net-port` to change, `--net-name` to set your tag).

### how the cats stay identical

nobody streams bones. `CatRig` animates itself from a few inputs (position, velocity, floor contact and the
pose dials: crouch, charge, climb, clamber, scratch, sit, loaf, groom, stretch, claws, look, ...), so each game
sends those ~30 times a second (`scripts/net/cat_net_state.gd`, ~6 kB/s per player) and every other game
feeds them into its own copy of your rig (`scripts/net/remote_cat.gd`), played back ~0.1 s in the past so
it's smooth through lag. on top of that it sends:

- the rig's own clocks (breathing / wiggle / tail lash time and the gait phase), so the same paw lifts on
  the same beat
- everything the rig does at random, as events: glances, blinks, ear flicks, tail twitches, plus swats
  and sounds it heard (`CatRig.life_log`). the remote copy has `remote_life` on and never rolls its own dice
- what's in its mouth (a brainless copy of the same critter)

the levels, props, prey and npc cats are still each player's own (not synced yet), and cats don't collide
with each other.

check it: `godot --path . -- --preview --parkour --nettest [--split]` runs the parkour bot, echoes your cat
back through a fake 60 ms / jittery / 2% loss network and prints how far every part of the copy is from the
real cat at the same moment (`--split` renders them side by side). knobs: `--net-hz --net-lag --net-jitter --net-loss`.

### steam app id

it runs on valve's public test app **480 ("Spacewar")** for now: free, works for testing with friends, but
steam shows the game as "Spacewar" and everyone shares it (lobbies are tagged `catgame`, so you only see
ours). for a real release you need a steamworks partner account + the **$100 app fee** per game
(https://partner.steamgames.com), then put your app id in `NetSteamTransport.STEAM_APP_ID` and drop the
`steam_appid.txt` line from the release workflow (steam supplies it when launched from steam).

### godotsteam

steam access is the GodotSteam GDExtension. it isn't committed: ci downloads it (`tools/fetch_godotsteam.sh`,
from codeberg) before exporting and fails the build if the steam api the game uses is missing
(`tests/steam_check.gd`). run the script yourself to get steam in the editor. without it the game runs fine,
the m menu just says steam isn't in this build.

## the living layer (`scripts/cat_soma.gd`)
everything a real cat does that is not locomotion, layered on the rig (`rig.soma`):
- breathing follows exertion: ~25 breaths a minute at rest, flanks after ribs, hard and fast after a long
  sprint (mouth open when really blown, also when the stamina bar runs dry)
- loose skin: the loin jiggles on landings, the belly pouch swings under the hips
- whiskers fan forward to hunt / sniff / yawn, pin back at a gallop or in fear, and quiver
- ears go flat sideways when startled, the tips flop on impacts and shakes, each one scans on its own when sat
- pupils go from slits to saucers (hunting, pouncing, scared), the eyes move before the head, slow blinks
- left alone it sniffs, tilts its head, yawns, stretches, shakes itself off, then sits down, grooms and
  (after a long while) loafs. any input and it is up at once
- a loud noise close by (`rig.hear(pos, 0.8+)`): flinch, puffed tail, raised back, wide eyes
- the head locks onto nearby prey and follows it
- wet paws (forest stream / pond): flicked on every step, then shaken off one by one when it stops
- the tail lies on the floor instead of going through it
- `rig.soma.act("yawn")` etc. plays one by hand, `rig.idle_life = false` turns the self started ones off.
  self started acts go through the rig's life_log, so multiplayer copies do the same thing
- lab: `godot --path . res://gaitlab.tscn -- --only life,scare,pant,wet,stalk2 --view face`
