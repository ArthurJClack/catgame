# cat game (prototype)

first person cat puzzle game, godot 4.3. everything is procedural (no imported assets yet):
the cat model, its animation, the level.

open the folder in godot 4.3+ and hit play (f5).

boot = **title screen** (`title_screen.gd`) over the live farm while the camera circles your cat: continue (last save, says where + play time + puzzles + treats), load / new game (3 slots, "start over" needs two clicks), settings, play online (the m lobby), quit. once per run, never in tests / previews / the server. test: `xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/title_test.gd [-- out/title]` (saves screenshots)

## controls
**simplified layout (2026-11-21)**, 14 rebindable actions:

| key | does |
|---|---|
| wasd + mouse | move (the cat turns where you look). keys alone = a calm ~1.25 m/s stroll |
| shift | run, double tap + hold = gallop |
| ctrl / c | crouch / sneak (slow + quiet) |
| space | tap = hop, hold = leap: aim with where you look (look up = leap up), let go (onto prey it's a pounce) |
| mouse1 | swat (alternates paws), hold = hook with your claws |
| mouse2 / g | grab / hold in your mouth |
| e / f | interact: drop what's in your mouth, otherwise scratch whatever's in front |
| alt / mouse4 | dodge |
| n | meow |
| v | first / third person (settings -> photo cam adds the orbit cam) |
| tab | lock on (rat pit only) |
| q (hold) | cat vision: puzzles (gold), prey (orange), cats (blue), loose stuff (white), things to climb (green) light up |
| j | explore map |
| esc / h | menu / help |

pad: L3 run, A hop / leap, B dodge, X interact, Y meow, RT swat, LT grab, RB crouch, LB cat vision, R3 lock on, d-pad left view.
lock on, rakes and the health bar only exist in the rat pit (`player.combat_zone`, set by
arena_main; bots always get them). holding space shows a jump bar under the crosshair: hop height, then leap distance (`CatPlayer.jump_meter()`). about half of stops are plain (no stop animation, `CatStop.NONE_CHANCE`), gentle ones always. removed: q / mouse3 aim leap (hold space does it), x / caps lock walk
(crouch sneaks), separate left / right paw buttons, d-pad walk / drop. 1-9 coats, f4 / f6 / f7 / f8 / f10
level jumps and t teleports are dev only (`DevKeys`, off in release exports): coats are in settings.
test: `--script res://tests/controls_test.gd` (xvfb). the notes below are the detailed history and
still describe how each system works; where they name old keys, the table wins.

- wasd moves relative to where you look (same as the orbit cam in every view), the cat turns to run that way and its head follows your look. backing up is slow, a/d = short sideways hop, hold shift = canter (6 m/s), double tap shift + hold = full gallop (11 m/s), ctrl/c stalk (crouch)
- momentum: the cat has weight. speed builds (trot ~0.4 s, full gallop ~2.5 s) and bleeds off when you let go (gallop rolls ~1.5-2 s), asking to go the other way at speed plants the paws and skids, and the faster it runs the wider it turns. hold x (or tap caps lock) = walk (~1 m/s)
- controller (`cat_pad.gd`, any pad godot maps, xbox names): left stick tilt = speed (nudge creep, half walk, full trot), right stick look, L3 run (click again = gallop), A = space (tap hop, hold higher hop, hold long = pounce), B dodge, X scratch, Y grab, LT/RT left/right paw, LB aim leap, RB crouch, R3 lock on, d-pad down drop, d-pad up walk toggle, d-pad left view. radial deadzones with rescale, hysteresis on the triggers
- space: tap = hop (1 m, comes out when you let go), hold a bit longer = a higher hop (up to 1.6 m, the cat gathers lower the longer you hold), hold ~0.45 s = **pounce mode**: the cat drops into the pounce crouch and a dotted line shows the exact path it'll fly, let go = pounce. in the air a press is instant: wall kick (1 per jump), scramble, leap off a climb
- no on screen action words any more ("swatted the hopper!" etc. are gone): `player.last_event` still logs them for tests, the only toasts left are level / system messages (`player.toast`)
- alt or mouse4: souls style dodge (`cat_dash.gd`). wasd toward the body = low dart, off to the side = startled side leap, behind = whirl round + dart, nothing held = backstep. committed once pressed, i-frames from the push off (`player.is_invulnerable()`), presses during the landing are buffered so dodges chain
- tab: souls style **lock on** (`cat_lock_on.gd`). locks the camera onto the best thing in view: rat pit rats first, then prey, then any other wildlife, nearest the crosshair wins. a dot marks it. while locked the body stays square to the target and wasd strafes / circles round it (shift still runs, camera stays on it), dodges read wasd relative to the target (s = backstep away, a / d = side leap round it, w = dart in), a quick mouse flick left / right hops the lock to the next target on that side, tab again unlocks. it also breaks when the target dies / is caught (a dead rat hands the lock to the next rat close by), gets past 16 m or stays out of sight for 1.4 s. works in first person, third person and orbit. other code can read `player.lock_target` (Node3D or null) and `player.lock_point()`. bot key `lock_on`. tests: `godot --headless --path . res://arena.tscn -- --locktest`, `--lockshow` renders the clip. (tab used to be "back to the house" in the forest / trail / pit / dock levels, that's f5 now)
- stamina bar (bottom centre, fades when full, `cat_stamina.gd`): hops, pounces, leaps, wall kicks, scrambles, swats and dodges cost a chunk, canter / gallop / climbing / claw dragging drain it while you do it, souls fast: a full bar lasts ~3.3 s of gallop or ~7 s of canter, and nothing comes back while you're running. comes back after a ~0.9 s breather (empty to full in ~3.3 s, a bit quicker standing still). run it dry and the cat is winded: trot only until it's back over a third. bots get a bottomless bar unless their bot dict has `stamina: true`. tests: `-- --preview --dashtest` (headless), `--dashshow` renders the clip
- health + stamina bars top left (`souls_hud.gd`, `cat_health.gd`): health red over stamina green with pale "just lost" trails, nine lives (lose all your health = lose a life). dodge i-frames ignore hits
- f10: **the rat pit** (`arena.tscn`, `arena_main.gd`). waves of rats (`souls_rat.gd`) that can only bite what's in front of their face: a wind up tell (rears back, jaw open), a lunge, then a recovery where they can't turn. they turn slower than you can circle them, so circle, bait the bite, dodge through it, and swat them from behind (double damage + stagger). a pounce that lands on one is a heavy hit. wave 4 has a brute. r restarts. tests: `godot --headless --path . res://arena.tscn -- --arenatest`, `--arenashow` renders the clip
- **cat puzzles** (`puzzles.gd`, all optional, no on screen words, the world answers): a treat bag on top of the kitchen wall cabinets (fridge -> cabinet jump, swat it off and it bursts on the floor), a sunbeam on the barn tie beam over the open floor (loft -> tie beam -> spine beam, sit still in it), the doormat outside the patio door (drop something you caught there, the bowl fills, every catch counts once), and oil lanterns on the rat pit pillars (pillars are climbable now: swat one off, it smashes onto the rats and the oil burns for a few seconds, cats too; they come back each wave). walk over treats to eat them. **pull the string** (`puzzle_rope.gd`): a frayed rope hangs off the barn loft edge (tail at cat height, a real chain of 4 rigid bits on pin joints), tied to a bale sitting on the edge. batting it only swings it; hook it with your claws (hold a paw) and drag it back twice and the bale creaks, slides, drops 2.5 m and bursts into treats, then stays as a step. **herd the chicks** (`puzzle_herd.gd`): five chicks potter about the yard east of the barn door, their pen (low chicken wire, a coop to perch on, grain inside) sits by the east fence with one gap facing west. they keep a real flight distance (~1.7 m): walk up slowly and they trot straight away from you, so where you stand steers them; gallop, swat or pounce near them and they bolt every which way. cats hop the fence, chicks can't. all five in and the gate swings shut, treats spill outside. **quiet paws** (`puzzle_dog.gd`, pier 9): the guard's dog sleeps on a mat outside the hut, chained, its dinner right by its nose. every move makes noise (speed x surface: grating clangs, puddles splash, stalking is near silent; hard landings and meows spike it), heard by distance from its ears and muffled by walls. it flicks an ear, lifts its head, then wakes, barks and lunges as far as the chain goes, and lies back down once it's quiet. stalk in, eat, stalk out. **one each for the other levels** (`puzzle_more.gd`): the crow's shiny (forest, a bottle cap on the deer stand platform, climb the ladder and swat it off), the boulder (trail, a treat bag on a tall rough rock by the rock garden, climb or leap up and knock it off) and the warm vent (city, a steaming grate on s main st, sit still on it in the rain). that makes 10, the pause menu counts them; crouch + keep still = cat sense shows unsolved ones nearby (`cat_sense.gd`). test: `--script res://tests/more_puzzles_test.gd` (xvfb). tests: `godot --headless --path . res://main.tscn -- --puzzletest`, `res://stealth.tscn -- --puzzletest` and `res://arena.tscn -- --puzzletest`, `--puzzleshow` renders a clip
- grip: paws only push so hard. wood/tile is slippy, carpet/rug grippy, grass in between. hard turns or stops at speed make the cat skid, scrabble and tear up grass/dirt/hay
- hunting: crouch to stalk (hud shows pounce range), pounce (hold space) onto prey, grab it (g) or claw it to catch, it sits in the cat's mouth, e drops it. swats stun prey (the cat only swats when you press swat)
- default cat is a black cat with yellow eyes, 1-9 swaps coats
- push into a wall while falling: claws out, slow wall slide
- hold space while running into a wall in the air: scramble up it
- paw combat (`cat_combat.gd`): mouse1 = left paw, mouse2 = right paw, g / mouse5 = grab
  - **souls style commitment**: every attack has a wind up, an active bit and a recovery (`CatCombat.MOVES`). each swat / rake lunges the cat in a bit (hind legs drive it ~0.25 m forward in the wind up, stops just short of the target) with the chest dropping into it, and the paw doesn't just tap: the claws hook in and drag down and back (a real scratch) before it comes home. once it starts you're in it: the feet plant and only creep, the body tracks a little in the wind up and freezes while the paw is out, no jumping / leaping / running / side hops. a dodge pressed mid attack waits for the move's cancel point and then rolls straight out of the recovery. clicks mid attack are buffered and come out at the chain point (swat to swat 0.28 s, so mashing strings a rhythm). getting hit in the wind up staggers you out of it (the paw never lands). the grab's reach and a stuck pounce landing are committed too. works the same locked on and on a pad
  - tap: swat with that paw, auto aims at the loose thing nearest the crosshair, real impulse (light stuff flies, barrels barely rock)
  - hold: that paw keeps raking whatever's in front (a rake every 0.24 s, half a swat's damage + poise, 3 stamina each). nothing to rake = claws out instead: hook a loose object and drag it around by looking, let go to fling. on a surface the claws dig in and drag marks
  - grab (g / mouse5, pad Y): a quick committed reach (no rearing up), both fore paws clamp on the target (heavy hit) and hold it pinned while the button is held, claws squeezing every 0.4 s. a cat needs a free fore paw to walk, so while it holds it can't move, hop or dodge. let go to be free again. nothing in reach = it grabs at air and recovers. holding drains stamina, rats wriggle out after 1.6 s (the brute sooner), small prey pinned like this is caught. everything is x2 from behind
  - both paws at once = just a left swat and a right swat (the second one buffered)
  - **pounce** (hold space past the hop, see above), the only pounce in the game (the old c + space and both-click pounces are gone, and the q leap is pure movement now). the cat crouches and winds up (0.7 s to full power) while you aim; the dotted line + ring show exactly where it lands. let go = launch: a low, mostly forward ballistic arc (~17 deg, looking up / down tilts it a bit, never a high lob), no air steering. soft lock: prey / rats near where the arc lands, the tab lock-on target and ledges the arc would smack just under the top bend the launch so it comes down exactly there (ring turns red on prey, yellow on a ledge). moving targets are led: it aims at where the animal will be when the cat comes down (its velocity, or measured from how it moved, times the flight time). it sticks the landing (no slide, no steps, then a short committed recovery) and the forepaws pin what's under them (rats: heavy hit). press a paw while aiming = call it off
  - slash fx (`slash_fx.gd`): three claw streaks along every swat / rake, sparks where it connects (red bits + scratch lines that stay on a rat for a second), a double streak when both paws come down
  - tests: `godot --headless --path . res://arena.tscn -- --combattest`, `--combatshow` / `--pounceshow` render the clips

## parkour (the easy way)
- hold q (or mouse3), look where you want to be, let go: the cat crouches, wiggles and leaps
  on a real ballistic arc that lands exactly there (green ring + arc preview, red = can't reach)
- look at the side of a table/counter/fridge and it finds the top for you
- too high to land on (up to ~2.2 m)? the ring turns yellow: it leaps to grab the edge,
  hangs on the forepaws, hind paws scrabble, and it hauls itself up (hold w, or s/c to let go)
- run or jump into a low ledge (< 0.3 m) and it just hops up; up to 0.85 m it grabs + clambers
- jump at anything rough holding w (cat tree post, sisal post, curtains): claws in, climb.
  w up (in bounds), s down, a/d sideways, space leaps off backwards (or lunges, see below), c lets go.
  climbing into an overhang (a perch) reaches around the lip and pulls up onto it
- **climbing** (`cat_climb.gd`, one system for everything on the side of things): free climb (botw style: w / s = up / down, a / d = sideways, diagonals; follows round trunks and posts, swings round outside corners on an arc, turns into inside corners, body turns toward where it's heading), hang off an edge, and every move over an edge: grab + haul up, top out off a climb, low ledge hop, curb step up, round an overhanging lip, step down off a wall onto the floor, push off. moves over edges are planned paths that start the way the cat is moving and end the way the next thing expects, swept with the real capsule before they start (no clipping through edges / shelves / ceilings, no teleports, no landing past a thin top in the air); a top with no headroom just isn't taken. the head's reach is checked upward and sideways so it never goes into what it's climbing toward. space + a direction = climb lunge, space alone / s / looking away = kick off. climbing drains stamina; run dry and the claws give out. anything in group "climbable" or with surface bark / fabric / carpet / rug / hay / sisal / rope grips. `climbing` / `clambering` / `mantling` on the player are read only views of it (setting one false resets). test: `godot --headless --fixed-fps 60 --path . res://climblab.tscn -- --climbtest` (18 runs, each also checked for pops / snaps / clipping / stuck), `--show [--fp] [--only a,b]` renders it (xvfb)
- f (hold) facing a wall/couch/post: stand up and scratch. leaves claw marks, fluff flies off soft stuff
- pounce (hold space): forepaws slam down together and pin whatever is under them.
  there's a wind up toy mouse to hunt: stalk slow (rushing spooks it), aim at it, pounce
- first person is a real camera in the cat's head: it rides the head bone (gait, crouch, rearing, pounces, climbing all move it), the head + neck are hidden and you see the cat's actual chest and forelegs. look ahead and the body is out of view like it would be for a real cat, look down and it curls its neck to watch its own paws. `player.head_cam = false` brings back the old floating paw viewmodel. test: `godot --path . res://fplab.tscn -- --fptest` (+ `--legacy` for the old paws)
- v: third person (see the whole cat)
- **esc (pad start) = pause menu** (`game_menu.gd`, autoload `GameMenu`): resume, settings, controls, back to the farm, quit. single player pauses, online the world keeps going but your cat stands still while it's open
  - settings (`game_settings.gd`, saved to `user://settings.cfg`): master / world ambience / cat + effects volume (audio buses `Ambience` + `SFX`, new players get routed automatically), mouse sensitivity, invert y, fov, head bob off (comfort: the fp eye glides instead of riding each step), fullscreen, vsync, max fps, show fps, quality low / medium / high (low: no ssao / ssil / fog / glow / msaa, shorter shadows) and render scale. defaults = exactly how the game was before
  - controls: every keyboard / mouse action can be rebound, two binds each (`cat_keys.gd`, `CatKeys.down("jump")`), binding a key takes it off whatever had it, esc / f-keys / m / r / h / 1-9 are reserved. gamepad map is listed but fixed
  - test: `xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/menu_test.gd`
- **achievements** (`achievements.gd`, lives under the `Save` autoload): 20 of them (knock the bag off, sunbeam, doormat gift, lantern, treats 10 / 50, catches 1 / 25, rats 10 / 100, last pit wave, a trail lap, visit everywhere, gallop, 3 m up, 50 meows, sit still a minute, + 2 secret), checked from the save stats + the live cat, stored in the save, a card + chime top right, pause menu -> achievements lists them. `unlocked(id)` signal is the hook for steam later. test: `--script res://tests/achievements_test.gd [-- out/dir]`
- **tutorial** (`tutorial.gd`): a fresh save on the farm gets one small hint card at a time, bottom centre: walk, look, cat sense (crouch + keep still), then hop, leap, swat, climb, scratch, run and meow each wait for the moment they are useful along the first puzzle (leap in the kitchen, swat with something in reach, meow once the treat bag is down; 45 s fallback), then "explore". cards show the keys you actually have bound (or pad buttons on a pad), tick off when you do the thing (or move on after 40 s), progress is in the save. the old help wall is hidden while it runs (h still shows it). settings -> tutorial hints on / off + restart. only controls: puzzles keep the no words rule. test: `--script res://tests/tutorial_test.gd [-- out/dir]` (xvfb)
- **cat audio** (`cat_sfx.gd`, all synthesised at load like the forest soundscape, ~36 clips, on the `SFX` bus): paw steps off the gait's real touchdowns (tap on wood / tile, muffled on carpet, rustle on grass / hay, grit on dirt, hind paws a bit quieter, louder with speed), hop push off, landings by drop height (soft / hard), swat + rake + grab whoosh, rat hits, scratching loop, climbing claw clicks, skids, dodge whoosh, catch squeak, hurt yowl / hiss, **n = meow** (rebindable, 3 meows), and a purr that fades in after ~5 s sitting still. rats squeak on their wind up, bite, hurt and death (`CatSfx.RatVoice`), every menu button clicks. `CatSfx.play_at(clip, pos)` for anything else. test: `--script res://tests/audio_test.gd [-- out/sfx]` (xvfb, also writes every clip as a wav)
- **save / load** (`save_game.gd`, autoload `Save`): 3 slots (`user://save_<n>.json`, written to a temp file then swapped so a crash can't eat it). keeps the level you're in + where the cat stands, the coat, play time, treats, puzzles solved, stats (catches, rats, best pit wave, best trail laps in one run, lives lost, levels visited) and room for achievements / tutorial flags. autosaves every 45 s, 2 s after every level change, on a puzzle solve and on quit, "saved" blinks bottom right. the pause menu has a save button. booting loads the last slot's progress; `Save.continue_game()` also puts you back in the saved level and spot. off in tests / previews / the server. test: `--script res://tests/save_test.gd` (xvfb), `tests/menu_shots.gd -- out/menu` saves screenshots of the pages

## vr (OpenXR: SteamVR, Quest Link / Air Link, WMR)

- turn it on in settings -> vr -> "turn vr on (restarts)", use the "Cat Game VR" start menu shortcut, or launch with `--xr-mode on -- --vrboot`. OpenXR can only start with the engine, so switching restarts the game. no headset / runtime = it stays flat and says so. `-- --vr` / `-- --novr` force it for one run. flat mode never builds any vr nodes
- you're the cat: the headset rides the head bone (same spot as the first person head cam), world scale 0.5 by default so the world looks cat sized (settings: "cat size"). the view only ever yaws: slopes, wall climbs, head bob and roll never tilt your eyes. leaning moves the eye a few cm, walking round the room recentres
- controllers: left stick move (head relative, tilt = speed), click = run / again = gallop. right stick snap / smooth turn, pull back = crouch. triggers = left / right paw, either grip = grab, A hop (hold = leap / pounce), B dodge, X interact (scratch / drop), Y meow (hold Y or menu button = pause menu), right stick click = lock on (rat pit)
- your hands are the forepaws: raise a hand to chest height and that paw lifts and follows it, swing it fast = swat. haptics on swats / hits / grabs / catches
- every 2d screen (hud, menus, title, tutorial) draws on a panel floating in front of you, a laser from your pointer hand clicks it (trigger), stick scrolls. dropdowns become click to cycle buttons in vr. comfort vignette while running / turning, blink on snap turns
- code: `scripts/vr/cat_vr.gd` (launch switch, `CatVR.read(cat)` input merge), `scripts/vr/vr_body.gd` (origin, poses, input, paws, panel, laser, vignette), `cat_rig.vr_paw / vr_paw_w`, `openxr_action_map.tres` (godot's default map: Quest, Index, Vive, WMR, Pico...)
- test (no headset, simulated poses + buttons): `xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --fixed-fps 60 --script res://tests/vr_test.gd [-- outdir]`

## numbers (real cat scale, meters)
- body 0.46 m, shoulder 0.25 m, eye height 0.25 m
- stalk 0.7 m/s, trot 3.2 m/s, canter 6 m/s, gallop 11 m/s (~40 km/h)
- gravity 9.8, hop 1.0 m (charged 1.6 m), pounce ~3 m out

## files
- `scripts/cat_rig.gd` procedural low poly cat + ik gait system: walk/trot/gallop/climbing bound,
  single track paw placement, wrist flick + heel lift, scapula ride, front first landings,
  spring chain tail, stretch/groom/loaf/scratch/hang/climb/pin poses (5 model styles, one rig)
- `scripts/toy_mouse.gd` prey toy
- `scripts/paw_view.gd` first person front legs
- `scripts/cat_player.gd` movement controller (`-- --preview --movetest` checks momentum + the pad, `--movecurve` dumps a speed csv)
- `scripts/move_lab.gd` movement scoreboard: bot maneuvers on each surface, numbers printed next to a real cat's
  (`godot --headless --fixed-fps 60 --path . res://movelab.tscn -- --realtest [--only a,b] [--csv out.csv]`, ~1 min)
- grip: `CatPlayer.real_move` (default on) holds push, brake and turn to what the surface grips (`CatPlayer.MU` x g,
  `GRIP_REAL` scales it all). `CAT_OFF=real_move` or `--real 0` in the labs = the old grip table
- jumps (also `real_move`): a hop loads the legs first (`GATHER_MIN`..`GATHER_MAX`), goes lower the faster the run
  (`RUN_HOP`), and can't be steered in the air past a small nudge (`AIR_NUDGE`, `AIR_BUDGET`)
- landings (also `real_move`): hitting the ground faster than `LAND_FREE` costs run speed and a short recovery
  (`LAND_KEEP_*`, `LAND_REC_*`), faster than `LAND_HARD` (about a 6 m fall) also hurts (`FALL_DMG_*`, `CatHealth.fall`).
  a pounce or dodge that sticks its landing skips the soft tier
- `scripts/cat_pad.gd` gamepad reader (deadzones, button map, `CatPad.sim` fake pad for tests)
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
- first person paws lab: `godot --path . res://fplab.tscn -- --fptest` (needs a display, e.g. xvfb) checks the fp paws are copies of the rig's real forelegs and stay on screen through walk / trot / gallop / swats / pounce / dodges / wall kick. without `--fptest` it plays the same moves split screen: old viewmodel | new viewmodel + a small third person view of the body

## views + levels

- v cycles first person, third person and orbit cam. in orbit, the mouse orbits the cat, the scroll wheel zooms, wasd is camera relative and the cat turns to face where it goes. the camera never clips through walls.
- the farm is the **hub world** (`scripts/hub.gd`): walk out a gate to travel, every level has a way back that drops you at the gate you left by.
  - west fence gate -> the forest · east fence steel gate + lamp lit lane -> pier 9 (night docks) · north timber arch -> the running trail · neon steel gate in the back fence behind the house -> the city · cellar hatch against the barn -> the rat pit
  - fingerpost on the patio points at all four. in multiplayer the signs show "2 cats there" and you get a flash when a friend walks off somewhere ("mo went to the forest"); each player travels on their own, lobby "go to them" still works
  - ways back: forest gate behind the spawn, a lit cat hole in the dock warehouse west wall, a farm gate just off the trail start line, a lit tunnel in the pit wall behind you, a farm gate on the sidewalk behind the city start. f5 still works everywhere
  - f6 / f7 / f8 / f10 stay as debug shortcuts. add a destination: an entry in `Hub.DESTS` (+ `FENCE_GATES` for a fence gate or your own builder), a spawn in `Hub.spawns()`, and `Hub.exit(...)` in the level
  - tests: `xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script res://tests/hub_test.gd` (every gate there and back). `tests/hub_show.gd` renders the tour clip, `tests/hub_map.gd` the labelled map

## the city (res://city.tscn, f4 from the farm)
- one dense crossroads at cat scale (`scripts/city/city_block.gd`, 92 x 92 m, rebuilt small 2026-11-22; the old full size pioneer square osm map is gone). main st + cross st meet in the middle; around them: neko ramen, apartments, a laundromat, the alley, a back lot with a loading dock (nw) · the deli, apartments, the arcade, hotel neko, a parking lot with a carport, backyards with a treehouse (ne) · a bodega, the noodle bar, a hotel, a construction site (unfinished concrete floors + scaffold), a plaza with a food truck + the cat cafe (sw) · the park: climbable trees with limbs, benches, a raised pond with a cat statue fountain + stepping stones, a playground (slide, swings, climbing frame, seesaw), a gazebo (se)
- built for a cat: window sills (26 cm), window ac units and flower boxes, awnings (fabric, climb + walk them, crates / vending machines / newspaper boxes step you up), drain pipes on the corners all the way to the roof, switchback fire escapes (ramps, landings, a drop ladder off a dumpster, a wall ladder to the roof), cornices + parapets to walk, roof clutter (ac boxes, hatch huts, water towers with ladders, billboards on climbable lattice), wooden fences with cat holes (climbable, walk the top rail), chain-link, pallets, crate stacks, an old car on blocks. crawl spaces under the loading dock, the porch deck, the gazebo and the footbridge stairs, under parked cars and dumpsters. roof to roof: gaps, planks, the WHISKR sign bridge over cross st, the footbridge over main st
- one merged mesh per 12 m cell with one shader (`city_block.gdshader`: brick, concrete, planks, grating, glow, glass, water, asphalt, awning stripes, leaves, tiles in world space, soot + rain streaks, wet shiny street), colliders grouped per surface / climbable / cell. a dark skyline with lit windows past the edges
- **traffic** (`city_traffic.gd`): cars (the three shitbox rally models), buses (stop at the bus shelter) and bikes on both streets, traffic lights + walk signals with countdowns on every crosswalk. cars don't stop for cats: get hit and you're bonked back onto the curb you came from (a yowl, a toss, a honk). wait for WALK or go over / under. online: nothing is sent, the lights and every car are a pure function of the shared clock (unix time, fixed 30 hz steps from a hashed spawn schedule, 90 s warm up), so everyone sees the same traffic
- pigeons on the pavements, plaza and roofs, sparrows in the park and yards (`wildlife.gd` birds with `ground_cb` / `perch_list` / `pigeon`): they flush up to ledges, wires, lamps and branches when you get close. rats in the alleys, dumpsters, the loading dock, construction site and park come from the hunting update (`hunt_prey.gd`, spawned only if it's there)
- the warm vent puzzle sits on the s main st sidewalk in front of the noodle bar. parked cars along both curbs + in the lot (`city_cars.gd`)
- keys: j map · r back to the start · t next spot · f5 / the farm sign back. preview: `-- --still x,y,z,tx,ty,tz`, `-- --tour` (83 s camera flythrough), `-- --citytest` (walks, gets bonked, checks it all, one line + exit code), `-- --mapshot out.png`

## explore map (every level)
- **j** (rebindable, pad back button, or pause menu -> map) opens a map of the level you're in that fills in as you explore (`explore_map.gd`, autoload `ExploreMap`). shows the cat (arrow), place names you've seen, puzzles you've found (gold = solved) and the ways out. the picture is a top down shot of the live level taken the first time you open it, the fog is a byte per cell on top (a bit more reveal from up high)
- a level can give its size + place names with `map_info()` on its root (the city does), otherwise the map frames the level's meshes
- saved per level in `Save.data.explore[scene_path] = {v, rect, cell, w, h, fog (base64)}`; `ExploreMap.merge(path, entry)` folds another copy in (max per cell) for world sync, `revealed` fires as it fills. test: `--script res://tests/explore_map_test.gd` (xvfb)

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
- running over rough ground: the cat never jumps by itself, only when you press space
  - roots, branches and stone lips up to 11 cm: the body glides up while the paws step
    (`scripts/run_assist.gd`, `auto_step`, on for the player everywhere)
  - walking or running into anything up to ~22 cm (curbs, steps, low rocks, small logs): it steps up onto it,
    forepaws then hinds, no leap, and keeps its pace (`STEP_MOUNT`, the quick mantle in cat_player.gd)
  - taller than that (hurdle logs, big rocks, the creek, the 26 cm stone steps): jump
- r restart · t next section · b auto step on/off · f5 back to the house
- `-- --runtest` (headless ok): a bot runs a lap (jumping only when it gets stuck) and prints every step up,
  jump and stuck spot. `-- --run` = preview video
- `res://steptest.tscn` (headless): runs the cat at walk/trot/canter/gallop into boxes, a round rock and a
  lying log of 6-35 cm, checks it never launches itself and mounts everything up to 22 cm

### rough ground footwork

paws look where they step: each swing picks a foothold where the paw will actually land (off root / rock
edges and steep faces, reach rays up to 24 cm up / 20 cm down, never onto something the cat walks under),
lifts higher to clear what's in between and keeps the toes out of the ground mid swing. the girdles sit
nearer the lower paw (the cat crouches over dips instead of reaching into them), tilt with the ground
across them, and the body height is damped in world space so it doesn't hop when the capsule rides a bump.
`CatGait.rough = false` = the old flat ground behaviour.
- `res://roughlab.tscn -- --roughtest [--legacy] [--only walk,trot,canter]` (headless): the real controller
  walks / trots / canters over bumps, roots, rocks, a 15 deg cross slope and 7 cm stone steps, and every
  frame checks planted paws against the ground under them (ROUGHTEST PASS). `-- --show` = before/after video

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

## multiplayer (steam lobbies + dedicated servers)

press **m** in game. other players show up as full cats, animated by the same procedural rig as yours.

- **host (friends)** makes a friends-only lobby, **host (public)** one anyone can find. **invite friends**
  opens the steam overlay invite list (shift+tab works too). friends accept the invite in steam and land
  in your lobby. **refresh** lists public / friends' lobbies, **join** hops in. **go to them** takes you to
  the level a friend is in (house / forest / docks): you only see cats in the same level as you.
- name tags float over everyone's cat. "x joined" / "x left" shows in the middle of the screen.
- needs steam running and logged in on every pc. no steam? lan / direct ip works too:
  host runs `CatGame.exe -- --net-host`, friends run `CatGame.exe -- --net-join <host ip>` (udp 24680,
  `--net-port` to change, `--net-name` to set your tag).

### dedicated servers

a server is a game with no window and no cat that stays up as a meeting place. players find it in the
**m** menu under **servers** (**steam servers** / **lan servers**, then **join**), or type its address in
the box (`1.2.3.4` or `1.2.3.4:port`). steam's own server browser (View > Game Servers, filter Spacewar for
now) lists it too and starts the game with `+connect ip:port`. joining drops you in the server's level;
you can still wander off, you just only see cats in the same level.

- download **CatGameServer-linux.tar.gz** or **CatGameServer-windows.zip** from a release, edit the top of
  `run_server.sh` / `run_server.bat` (name, map, ports, max cats, message of the day) and start it. it
  restarts itself if it dies.
- or run any build headless: `CatGame.exe --headless -- --server --name "my cats" --map forest`
- flags (after `--`): `--name`, `--map house|forest|docks|trail|arena`, `--port` (udp, 24680),
  `--query-port` (steam, 27016), `--max` (16), `--motd`, `--token <gslt>`, `--no-steam`
- open **udp 24680** (the cats) and **udp 27016** (steam's server list queries) in the firewall / router.
- the steam server list needs the GodotSteam *Server* extension (ci puts it in the server builds) and, on
  linux, steam's `steamclient.so` in `~/.steam/sdk64/` (steamcmd `+login anonymous +app_update 1007`, see
  `run_server.sh`). without either it's a direct-ip server and says so in its log.
- GodotSteam Server is pinned to **v4.0.1**: v4.3 / v4.4 crash inside `serverInit` (they parse the ip
  with a steam networking call before steam is up), and v4.0.1's release lib crashes on load in godot 4.3,
  so the server builds use the **debug** export templates (its debug lib works). ci proves it every run:
  the exported linux server logs on to steam and valve's public api (`GetServersAtAddress`) lists it.
- anonymous logon gets a new server id each start. a game server login token
  (https://steamcommunity.com/dev/managegameservers, app 480 for now) via `--token` or `CATGAME_GSLT`
  keeps it.

how it works: the server is the lan host's relay (`NetEnetTransport` with `dedicated` on) without a cat of
its own. every game still runs its own world and sends its own cat; the server forwards snapshots to everyone
else, tells new players its name / level / motd (`T_INFO`), and learns names from their hellos for the
server list. `scripts/net/dedicated_server.gd` (the server), `steam_server.gd` (SteamGameServer listing),
`server_browser.gd` (the m menu list). no steam auth, no passwords and no anti cheat yet: anyone with the
address can join. dedicated server exports (`dedicated_server` feature) start straight into `server.tscn`.

checks: `godot --headless --path . --script res://tests/server_test.gd` (server + two clients on localhost:
roster, info, relay, leaving). `tests/steam_server_check.gd` lists GodotSteam Server's calls in ci.

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
