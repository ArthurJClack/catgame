class_name CatNetState
extends RefCounted
## one snapshot of everything the procedural cat rig is driven by, plus the wire format.
##
## the rig (cat_rig.gd) animates itself from a handful of inputs: where it is, how fast it moves,
## whether it's on the floor, and the pose dials (crouch, climb, sit, ...). if a remote copy of the
## rig gets the same inputs at the same moments it solves the same spine, paws, tail and ears, so
## that's all that goes over the wire: no bones. the random stuff the rig does on its own
## (glances, blinks, ear flicks, tail twitches) travels as events (CatRig.life_log).

## pose dials copied 1:1 from the local rig (lerped between snapshots on the other end)
const DIALS := [
	"crouch", "charge", "look_yaw", "look_pitch", "scramble", "slip_claws", "climb", "clamber",
	"clamber_pull", "rear", "scratch", "scratch_dist", "sit", "stretch", "groom", "loaf", "balance", "pin",
	"grip",
]

const T_HELLO := 1
const T_SNAP := 2
const T_BYE := 3
const T_ROSTER := 9   # lan mode only: the host tells clients who's connected

const F_FLOOR := 1
const F_CLAW := 2
const F_CLAW_R := 4
const F_CARRY := 8

var t := 0.0                  # sender's sim clock (s)
var xf := Transform3D.IDENTITY  # rig global transform
var vel := Vector3.ZERO       # rig.drive_velocity
var on_floor := true
var claw_on := false
var claw_i := 1
var claw_target := Vector3.ZERO
var ledge_world := Vector3.ZERO
var dials := PackedFloat32Array()
var carry := ""               # "res://path/to/prey.gd|kind" while something is in its mouth
# the rig's own clocks. it animates in _process, so these were sampled at the last drawn
# frame (anim_t, sender sim clock), not at the physics tick t
var anim_t := 0.0
var life_t := 0.0             # rig._t: drives breathing, wiggles, idle sway, tail lash
var gphase := 0.0             # rig.gait.phase: which paw lifts when
var paws := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])  # gait.pos (world)
var pmode := 0                # gait.mode per paw, 2 bits each
var events: Array = []        # [[id, t, [ev...]], ...]


static func from_rig(rig: CatRig, sim_t: float, carried: Node, disp_t: float) -> CatNetState:
	var s := CatNetState.new()
	s.t = sim_t
	s.anim_t = disp_t
	s.life_t = rig.get("_t")
	s.gphase = rig.gait.phase
	for i in 4:
		s.paws[i] = rig.gait.pos[i]
		s.pmode |= (rig.gait.mode[i] & 3) << (i * 2)
	s.xf = rig.global_transform
	s.vel = rig.drive_velocity
	s.on_floor = rig.on_floor
	s.claw_on = rig.claw_on
	s.claw_i = rig.claw_i
	s.claw_target = rig.claw_target
	s.ledge_world = rig.ledge_world
	s.dials.resize(DIALS.size())
	for i in DIALS.size():
		s.dials[i] = float(rig.get(DIALS[i]))
	if is_instance_valid(carried) and carried.get_script():
		s.carry = "%s|%s" % [(carried.get_script() as Script).resource_path, str(carried.get("kind")) if "kind" in carried else ""]
	return s


## feed this state into a (remote) rig. dt = the frame it's about to animate, so self-decaying
## dials (pin) come out where the sender's were
func apply(rig: CatRig, dt: float) -> void:
	rig.global_transform = xf
	rig.drive_velocity = vel
	rig.on_floor = on_floor
	rig.claw_on = claw_on
	rig.claw_i = claw_i
	rig.claw_target = claw_target
	rig.ledge_world = ledge_world
	for i in mini(DIALS.size(), dials.size()):
		rig.set(DIALS[i], dials[i])
	if rig.pin > 0.0:
		rig.pin = minf(rig.pin + dt * 0.9, 1.0)   # the rig decays pin itself every frame
	# clocks: the rig adds dt to _t itself, and moves the gait phase by the distance covered
	rig.set("_t", life_t - dt)
	rig.net_phase = gphase
	rig.net_paws = paws
	rig.net_pmode = pmode


static func lerp_states(a: CatNetState, b: CatNetState, w: float) -> CatNetState:
	var s := CatNetState.new()
	s.t = lerpf(a.t, b.t, w)
	var qa := a.xf.basis.get_rotation_quaternion()
	var qb := b.xf.basis.get_rotation_quaternion()
	s.xf = Transform3D(Basis(qa.slerp(qb, w)), a.xf.origin.lerp(b.xf.origin, w))
	# discrete flags flip at the later snapshot. while the floor flag is changing hold the
	# velocity of the earlier one, so the landing hits as hard as it did for the sender
	s.on_floor = a.on_floor
	s.vel = a.vel if a.on_floor != b.on_floor else a.vel.lerp(b.vel, w)
	s.claw_on = a.claw_on
	s.claw_i = a.claw_i
	s.claw_target = a.claw_target.lerp(b.claw_target, w)
	s.ledge_world = a.ledge_world.lerp(b.ledge_world, w)
	s.dials.resize(a.dials.size())
	for i in a.dials.size():
		s.dials[i] = lerpf(a.dials[i], b.dials[i], w) if i < b.dials.size() else a.dials[i]
	s.carry = a.carry
	s.anim_t = a.anim_t
	s.life_t = a.life_t
	s.gphase = a.gphase
	s.paws = a.paws
	s.pmode = a.pmode
	return s


## same state pushed forward a little (packets late): keeps the body moving instead of freezing
func extrapolated(dt: float) -> CatNetState:
	var s := CatNetState.new()
	s.t = t + dt
	s.xf = Transform3D(xf.basis, xf.origin + vel * dt)
	s.vel = vel
	s.on_floor = on_floor
	s.claw_on = claw_on
	s.claw_i = claw_i
	s.claw_target = claw_target
	s.ledge_world = ledge_world
	s.dials = dials
	s.carry = carry
	s.anim_t = anim_t + dt
	s.life_t = life_t + dt
	s.gphase = gphase
	s.paws = paws
	s.pmode = pmode
	return s


# ------------------------------------------------------------------ wire format

static func _v3(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_float(v.x)
	b.put_float(v.y)
	b.put_float(v.z)


static func _r3(b: StreamPeerBuffer) -> Vector3:
	return Vector3(b.get_float(), b.get_float(), b.get_float())


func encode() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(T_SNAP)
	b.put_double(t)
	var f := 0
	if on_floor: f |= F_FLOOR
	if claw_on: f |= F_CLAW
	if claw_i == 1: f |= F_CLAW_R
	if carry != "": f |= F_CARRY
	b.put_u8(f)
	_v3(b, xf.origin)
	var q := xf.basis.get_rotation_quaternion()
	b.put_float(q.x)
	b.put_float(q.y)
	b.put_float(q.z)
	b.put_float(q.w)
	_v3(b, vel)
	_v3(b, claw_target)
	_v3(b, ledge_world)
	b.put_u8(dials.size())
	for d in dials:
		b.put_float(d)
	if carry != "":
		b.put_utf8_string(carry)
	b.put_double(anim_t)
	b.put_double(life_t)
	b.put_float(gphase)
	b.put_u8(pmode)
	for p in paws:
		_v3(b, p)
	b.put_u8(events.size())
	for e in events:
		b.put_u32(int(e[0]))
		b.put_double(float(e[1]))
		b.put_var(e[2])
	return b.data_array


## null if the packet is junk
static func decode(data: PackedByteArray) -> CatNetState:
	if data.size() < 60 or data[0] != T_SNAP:
		return null
	var b := StreamPeerBuffer.new()
	b.data_array = data
	b.seek(1)
	var s := CatNetState.new()
	s.t = b.get_double()
	var f := b.get_u8()
	s.on_floor = (f & F_FLOOR) != 0
	s.claw_on = (f & F_CLAW) != 0
	s.claw_i = 1 if (f & F_CLAW_R) != 0 else 0
	var o := _r3(b)
	var q := Quaternion(b.get_float(), b.get_float(), b.get_float(), b.get_float())
	if not q.is_finite() or q.length_squared() < 0.5:
		return null
	s.xf = Transform3D(Basis(q.normalized()), o)
	s.vel = _r3(b)
	s.claw_target = _r3(b)
	s.ledge_world = _r3(b)
	var n := b.get_u8()
	s.dials.resize(n)
	for i in n:
		s.dials[i] = b.get_float()
	if (f & F_CARRY) != 0:
		s.carry = b.get_utf8_string()
	s.anim_t = b.get_double()
	s.life_t = b.get_double()
	s.gphase = b.get_float()
	s.pmode = b.get_u8()
	for i in 4:
		s.paws[i] = _r3(b)
	if b.get_position() < b.get_size():
		var ne := b.get_u8()
		for i in ne:
			var id := b.get_u32()
			var et := b.get_double()
			var ev = b.get_var(false)   # no objects, ever
			if ev is Array and not (ev as Array).is_empty():
				s.events.append([id, et, ev])
	if not (s.xf.origin.is_finite() and s.vel.is_finite()):
		return null
	return s
