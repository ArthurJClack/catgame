class_name CatSlide
extends RefCounted
## sliding down something the cat can't climb (smooth wall, a roof or ramp too steep to stand on).
## the player turns the rig onto the surface (rig y = off the surface, y 0 = the surface itself,
## -z = the way the head points along it), this works out where the paws go in that frame.
##
## front paws: stretched out ahead, claws in, dragging. each one catches, gets hauled out to full
## stretch by the body sliding away from it (or pushed back under the chest when it's going head
## first), lets go and snaps out to re-catch. the two alternate, so it reads as frantic clawing.
## body + hind legs trail behind the front paws, hind feet scrabbling at the surface.
## claw marks: `contact[i]` / `planted[i]` are the world spots the fore claws are dragging over.

const HOLD := 0.42        # how much the claws catch (0 = pure drag, the paws just ride along)
const RE_T := 0.12        # snap out to re-catch (s)
const H_RATE := 3.2       # hind scrabble strokes per metre slid (per second at 1 m/s)

var foot := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]   # rig local targets
var prot := [0.0, 0.0, 0.0, 0.0]
var planted := [false, false]          # fore claws in the surface right now
var contact := [Vector3.ZERO, Vector3.ZERO]  # world spot of each dragging fore claw
var catches := 0                       # counts re-catches (sfx clicks off this)
var drag := 0.0                        # 0..1 how hard the claws are dragging (speed)

var _z := [0.0, 0.0]
var _sw := [-1.0, -1.0]
var _from := [0.0, 0.0]
var _to := [0.0, 0.0]
var _hph := 0.0
var _t := 0.0
var _started := false


func reset() -> void:
	_started = false


## rig: the CatRig (for leg lengths / home spots). gxf: rig frame in world. vel_l: body
## velocity in rig space (+z = sliding toward the tail, the head up case)
func update(rig, dt: float, gxf: Transform3D, vel_l: Vector3) -> void:
	_t += dt
	var lg: float = rig.F_UP / 0.105        # leg scale for this cat style
	var hf: Vector3 = rig.HOME[0]
	var hh: Vector3 = rig.HOME[2]
	var near := hf.z - 0.045 * lg          # catch spot just ahead of the shoulder
	var far := hf.z - 0.165 * lg           # full stretch
	var vz := vel_l.z
	drag = clampf(absf(vz) / 1.6, 0.0, 1.0)
	if not _started:
		_started = true
		# start mid stagger: one paw already stretched, the other just caught
		_z = [lerpf(near, far, 0.55), lerpf(near, far, 0.1)] if vz >= 0.0 else [lerpf(near, far, 0.45), lerpf(near, far, 0.9)]
		_sw = [-1.0, -1.0]
	var head_up := vz >= -0.02
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var x := side * (absf(hf.x) + 0.018 * lg)
		var f: Vector3
		var pr: float
		if float(_sw[i]) < 0.0:
			# claws in: the paw only gives a bit, so the sliding body hauls the arm out
			# (or, head first, pushes it back under the chest)
			_z[i] = float(_z[i]) - vz * HOLD * dt
			var other_free := float(_sw[1 - i]) >= 0.0
			var spent := (head_up and float(_z[i]) <= far) or (not head_up and float(_z[i]) >= near)
			if spent and not other_free:
				_sw[i] = 0.0
				_from[i] = _z[i]
				_to[i] = (near if head_up else far) + randf_range(-0.012, 0.012) * lg
			_z[i] = clampf(float(_z[i]), far - 0.02 * lg, near + 0.02 * lg)
			# stick slip: the claw judders as it skates
			var jit := sin(_t * 41.0 + side * 1.7) * 0.0035 * drag
			f = Vector3(x, 0.002 + absf(jit), float(_z[i]) + jit)
			pr = 0.6 + 0.15 * drag        # toes clenched, claws raking
			planted[i] = true
		else:
			_sw[i] = minf(float(_sw[i]) + dt / RE_T, 1.0)
			var s: float = _sw[i]
			var e := s * s * (3.0 - 2.0 * s)
			_z[i] = lerpf(float(_from[i]), float(_to[i]), e)
			var arc := sin(PI * s)
			f = Vector3(x + side * arc * 0.01, arc * 0.045 * lg, float(_z[i]))
			pr = -0.9 * arc + 0.5 * smoothstep(0.55, 1.0, s)   # curled on the way, opens to strike
			planted[i] = false
			if s >= 1.0:
				_sw[i] = -1.0
				catches += 1
		foot[i] = f
		prot[i] = pr
		contact[i] = gxf * Vector3(f.x, 0.0, f.z)

	# hind legs: trailing back, feet scrabbling at the surface (pedal strokes toward the tail)
	_hph = fposmod(_hph + (0.6 + absf(vz) * H_RATE) * dt, 1.0)
	for k in 2:
		var i := k + 2
		var side := -1.0 if k == 0 else 1.0
		var s := fposmod(_hph + 0.5 * k, 1.0)
		var z0 := hh.z + 0.07 * lg
		var f := Vector3(side * (absf(hh.x) + 0.022 * lg), 0.0, z0)
		var pr := -0.35
		if s < 0.62:
			# foot on the surface, raked back
			f.z += lerpf(-0.03, 0.035, s / 0.62) * lg
			f.y = 0.002
		else:
			var u := (s - 0.62) / 0.38
			f.z += lerpf(0.035, -0.03, u * u * (3.0 - 2.0 * u)) * lg
			f.y = sin(PI * u) * 0.028 * lg
			pr = -0.35 - 0.5 * sin(PI * u)
		foot[i] = f
		prot[i] = pr
