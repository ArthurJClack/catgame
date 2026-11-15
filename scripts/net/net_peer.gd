class_name NetPeer
extends RefCounted
## another player as far as the network is concerned: who they are, which level they're in,
## and a short buffer of their cat's snapshots that gets played back a little in the past
## (interpolation delay) so motion is smooth even when packets arrive bunched up.

const MAX_SNAPS := 48
const MIN_DELAY := 0.07
const MAX_DELAY := 0.35

var id := 0
var name := "cat"
var style := "block_black"
var scene := ""
var hello_seen := false
var last_heard := 0.0          # local clock (s)
var snaps: Array[CatNetState] = []
var cat: Node = null           # RemoteCat in the current scene, if any

# clock: offset = local receive time - sender sim time, taken from the fastest packets
var _offset := 0.0
var _offset_ok := false
var _jitter := 0.02
var delay := 0.1

# life events (glances, swats, ...) waiting for playback to reach their time
var _events: Array = []        # [[id, t, ev], ...] sorted by t
var _last_event_id := -1


## local clock: game time (sum of frame deltas, advanced by Net every frame). not the wall
## clock, so fixed-fps test renders see the same timing as real play
static var clock := 0.0


static func now() -> float:
	return clock


func push(s: CatNetState, send_interval: float) -> void:
	var local := now()
	last_heard = local
	var sample := local - s.t
	if not _offset_ok or sample < _offset or absf(sample - _offset) > 2.0:
		# faster packet than any before (or the sender restarted its clock): snap to it
		_offset = sample
		_offset_ok = true
	else:
		# drift up very slowly, so a route change doesn't leave us playing too far back
		_offset += (sample - _offset) * 0.002
		_jitter = lerpf(_jitter, sample - _offset, 0.05)
	delay = clampf(send_interval * 1.5 + _jitter * 2.5 + 0.02, MIN_DELAY, MAX_DELAY)
	# keep snapshots in time order, drop duplicates / stale ones
	if not snaps.is_empty() and s.t <= snaps[-1].t:
		if s.t < snaps[0].t:
			return
		for i in snaps.size():
			if absf(snaps[i].t - s.t) < 1e-6:
				return
			if snaps[i].t > s.t:
				snaps.insert(i, s)
				break
	else:
		snaps.append(s)
	while snaps.size() > MAX_SNAPS:
		snaps.pop_front()
	for e in s.events:
		if int(e[0]) > _last_event_id:
			_last_event_id = int(e[0])
			var at := _events.size()
			for i in _events.size():
				if float(_events[i][1]) > float(e[1]):
					at = i
					break
			_events.insert(at, e)


## sender-clock time we're showing right now
func render_time() -> float:
	return now() - _offset - delay


## the cat's state at sender time rt (null until the first snapshot)
func sample(rt: float) -> CatNetState:
	if snaps.is_empty():
		return null
	if rt <= snaps[0].t:
		return snaps[0]
	var last := snaps[-1]
	if rt >= last.t:
		# late: carry on along the last velocity for a moment, then hold
		return last.extrapolated(minf(rt - last.t, 0.12))
	var hi := snaps.size() - 1
	var lo := 0
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if snaps[mid].t <= rt:
			lo = mid
		else:
			hi = mid
	var a := snaps[lo]
	var b := snaps[hi]
	var w := clampf((rt - a.t) / maxf(b.t - a.t, 1e-6), 0.0, 1.0)
	# throw away what's well behind playback
	while snaps.size() > 2 and snaps[1].t < rt - 0.5:
		snaps.pop_front()
	var s := CatNetState.lerp_states(a, b, w)
	_anim_clocks(s, rt)
	return s


## the rig's clocks were sampled at drawn frames (anim_t), not at ticks: interpolate them on
## their own timeline
func _anim_clocks(s: CatNetState, rt: float) -> void:
	var a: CatNetState = null
	var b: CatNetState = null
	for i in range(snaps.size() - 1, -1, -1):
		if snaps[i].anim_t <= rt:
			a = snaps[i]
			for j in range(i + 1, snaps.size()):
				if snaps[j].anim_t > a.anim_t:
					b = snaps[j]
					break
			break
	if a == null:
		return
	s.paws = a.paws
	s.pmode = a.pmode
	if b == null:
		s.life_t = a.life_t + (rt - a.anim_t)
		s.gphase = a.gphase
		return
	var w := clampf((rt - a.anim_t) / (b.anim_t - a.anim_t), 0.0, 1.0)
	s.life_t = a.life_t + (rt - a.anim_t)
	s.gphase = fposmod(a.gphase + wrapf(b.gphase - a.gphase, -0.5, 0.5) * w, 1.0)


## life events whose time has come
func due_events(rt: float) -> Array:
	var out := []
	while not _events.is_empty() and float(_events[0][1]) <= rt:
		out.append(_events.pop_front()[2])
	# way behind (tab was asleep): don't replay a backlog of blinks
	if out.size() > 12:
		out = out.slice(out.size() - 4)
	return out
