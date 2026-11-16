class_name NetTest
extends Node
## `-- --preview --parkour --nettest`: runs the parkour bot while the loopback transport echoes
## your cat back to you through a fake laggy network as a RemoteCat. every frame it compares the
## remote cat's pose (every mesh of the rig) with what the local cat looked like at the same
## moment, and prints how far apart they are. add `--split` for a side by side render
## (left: your cat, right: the copy other players see).

var main: Node
var split := false
var _local_hist: Array = []   # [[t, PackedVector3Array], ...]
var _errs := PackedFloat32Array()
var _part_err := {}           # group -> [sum, n, max]
var _per_part := PackedFloat32Array()
var _shift_errs := PackedFloat32Array()   # worst part per frame, allowing +-2 frames of timing
var _part_names: Array = []
var _frames := 0
var _vp_l: SubViewport
var _vp_r: SubViewport
var _cam_l: Camera3D
var _cam_r: Camera3D
var _report_t := 0.0


func _ready() -> void:
	split = "--split" in OS.get_cmdline_user_args()
	process_priority = 1000   # after the rigs have animated this frame
	if split:
		_build_split()


func _remote() -> RemoteCat:
	for c in main.get_children():
		if c is RemoteCat:
			return c
	return null


static func _parts(rig: CatRig) -> Array:
	return rig.find_children("*", "MeshInstance3D", true, false)


static func _group(rig: CatRig, m: Node) -> String:
	var n := m
	while n and n != rig:
		if n == rig.head or n == rig.neck:
			return "head"
		if n == rig.tail_base:
			return "tail"
		n = n.get_parent()
	if m in rig.tail_segs or m in rig.tail_joints:
		return "tail"
	var p := m.get_parent()
	if p == rig.chest or p == rig.pelvis or m in rig.spine or p == rig.pivot:
		return "body"
	return "legs"


func _process(_dt: float) -> void:
	var player: CatPlayer = main.player
	if player == null or player.rig == null:
		return
	var lrig := player.rig
	var lp := _parts(lrig)
	var pos := PackedVector3Array()
	pos.resize(lp.size())
	for i in lp.size():
		pos[i] = (lp[i] as Node3D).global_position
	_local_hist.append([Net._disp_t, pos, _dbg(lrig)])
	while _local_hist.size() > 400:
		_local_hist.pop_front()
	var rc := _remote()
	if split:
		_update_split(lrig, rc)
	if rc == null or rc.rig == null or not rc.rig.visible:
		return
	var rt := rc.peer.render_time()
	# local pose at the remote's playback time
	var k := -1
	for i in range(_local_hist.size() - 1, 0, -1):
		if _local_hist[i - 1][0] <= rt:
			k = i
			break
	if k < 0 or _local_hist[k][0] < rt:
		return
	var a: Array = _local_hist[k - 1]
	var b: Array = _local_hist[k]
	var w := clampf((rt - a[0]) / maxf(b[0] - a[0], 1e-6), 0.0, 1.0)
	var rp := _parts(rc.rig)
	if rp.size() != lp.size():
		return
	_frames += 1
	if _frames < 20:
		return   # let both settle in
	if _per_part.size() != rp.size():
		_per_part.resize(rp.size())
		_per_part.fill(0.0)
		_part_names = rp.map(func(m): return "%s/%s(%s)" % [m.get_parent().name, m.name, _group(rc.rig, m)])
	for i in rp.size():
		var want: Vector3 = (a[1][i] as Vector3).lerp(b[1][i], w)
		var e := want.distance_to((rp[i] as Node3D).global_position)
		_errs.append(e)
		_per_part[i] += e
		var g := _group(rc.rig, rp[i])
		var acc: Array = _part_err.get(g, [0.0, 0, 0.0])
		acc[0] += e
		acc[1] += 1
		acc[2] = maxf(acc[2], e)
		_part_err[g] = acc
	var fm := 0.0
	for i in rp.size():
		fm = maxf(fm, _errs[_errs.size() - 1 - i])
	# same frame's worst part against the local cat 1-2 frames either side: if that's small the
	# difference is only *when* (a frame early / late), not *what*
	var best_shift := fm
	for sh in [-2, -1, 1, 2]:
		var j: int = k + sh
		if j < 1 or j >= _local_hist.size():
			continue
		var wm := 0.0
		for i in rp.size():
			var want2: Vector3 = (_local_hist[j - 1][1][i] as Vector3).lerp(_local_hist[j][1][i], w)
			wm = maxf(wm, want2.distance_to((rp[i] as Node3D).global_position))
		best_shift = minf(best_shift, wm)
	_shift_errs.append(best_shift)
	if fm > 0.05 and "--net-dbg" in OS.get_cmdline_user_args():
		print("[nettest]   local  " + str(b[2]))
		print("[nettest]   remote " + _dbg(rc.rig))
	if fm > 0.05:
		print("[nettest] t=%.2f worst part %.0f mm (%.0f mm a frame or two off)  floor=%s/%s vel=%s" % [rt, fm * 1000.0, best_shift * 1000.0, main.player.rig.on_floor, rc.rig.on_floor, rc.rig.drive_velocity.snapped(Vector3.ONE * 0.01)])
	_report_t += _dt
	if _report_t > 2.0:
		_report_t = 0.0
		print(summary())


static func _dbg(r: CatRig) -> String:
	return "land=%s %.3f air=%.2f launch=%.2f modes=%s vel=%s floor=%s ph=%.3f t=%.3f" % [r.land_known, r.land_t, r._air_w, r._launch, r.gait.mode, r.drive_velocity.snapped(Vector3.ONE * 0.01), r.on_floor, r.gait.phase, r._t]


func summary() -> String:
	if _errs.is_empty():
		return "[nettest] no samples yet"
	var s := _errs.duplicate()
	s.sort()
	var mean := 0.0
	for e in s:
		mean += e
	mean /= s.size()
	var out := "[nettest] frames %d  parts err mm: mean %.2f  p50 %.2f  p95 %.2f  p99 %.2f  max %.1f" % [
		_frames, mean * 1000.0, s[s.size() / 2] * 1000.0, s[int(s.size() * 0.95)] * 1000.0, s[int(s.size() * 0.99)] * 1000.0, s[-1] * 1000.0]
	var ss := _shift_errs.duplicate()
	ss.sort()
	if ss.size() > 0:
		out += "\n[nettest]   worst part per frame allowing +-2 frames timing: p50 %.1f  p95 %.1f  max %.1f mm" % [ss[ss.size() / 2] * 1000.0, ss[int(ss.size() * 0.95)] * 1000.0, ss[-1] * 1000.0]
	for g in _part_err:
		var acc: Array = _part_err[g]
		out += "\n[nettest]   %-5s mean %.2f mm  max %.1f mm" % [g, acc[0] / maxf(acc[1], 1) * 1000.0, acc[2] * 1000.0]
	if "--net-parts" in OS.get_cmdline_user_args() and _per_part.size() > 0:
		var idx := range(_per_part.size())
		idx.sort_custom(func(x, y): return _per_part[x] > _per_part[y])
		for k in mini(10, idx.size()):
			out += "\n[nettest]     part %s mean %.1f mm" % [_part_names[idx[k]], _per_part[idx[k]] / maxf(_frames - 19, 1) * 1000.0]
	return out


func _exit_tree() -> void:
	print(summary())


# ------------------------------------------------------------------ side by side render

func _build_split() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 4)
	layer.add_child(hb)
	var mk := func(label: String) -> Array:
		var c := SubViewportContainer.new()
		c.stretch = true
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(c)
		var vp := SubViewport.new()
		vp.msaa_3d = Viewport.MSAA_2X
		c.add_child(vp)
		var cam := Camera3D.new()
		cam.fov = 55
		cam.near = 0.01
		vp.add_child(cam)
		var l := Label.new()
		l.text = label
		l.position = Vector2(24, 18)
		l.add_theme_font_size_override("font_size", 26)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 8)
		c.add_child(l)
		return [vp, cam]
	var L: Array = mk.call("your cat")
	var R: Array = mk.call("what your friends see  (60 ms lag + jitter + 2% loss)")
	_vp_l = L[0]
	_cam_l = L[1]
	_vp_r = R[0]
	_cam_r = R[1]
	_cam_l.cull_mask = 0xFFFFF & ~(1 << 2)
	_cam_r.cull_mask = 0xFFFFF & ~(1 << 1)


static func _set_layers(rig: Node, bit: int) -> void:
	for m in rig.find_children("*", "VisualInstance3D", true, false):
		(m as VisualInstance3D).layers = 1 << bit


var _cam_hist: Array = []   # [[disp_t, Transform3D, fov], ...] of the main camera
var _frame_i := 0


func _update_split(lrig: CatRig, rc: RemoteCat) -> void:
	_set_layers(lrig, 1)
	var src := get_viewport().get_camera_3d()
	if src == null or src == _cam_l:
		return
	_cam_l.global_transform = src.global_transform
	_cam_l.fov = src.fov
	_cam_hist.append([Net._disp_t, src.global_transform, src.fov])
	while _cam_hist.size() > 120:
		_cam_hist.pop_front()
	# the right view films the copy with the camera from the moment the copy is showing, so
	# frame N on the right lines up with the left frame drawn at that time (paired up after,
	# see the "[split]" log lines)
	var rt := -1.0
	if rc and rc.rig and rc.peer:
		_set_layers(rc.rig, 2)
		rt = rc.peer.render_time()
		var best: Array = _cam_hist[0]
		for c in _cam_hist:
			if absf(c[0] - rt) < absf(best[0] - rt):
				best = c
		_cam_r.global_transform = best[1]
		_cam_r.fov = best[2]
	else:
		_cam_r.global_transform = src.global_transform
		_cam_r.fov = src.fov
	print("[split] %d %.4f %.4f" % [_frame_i, Net._disp_t, rt])
	_frame_i += 1
