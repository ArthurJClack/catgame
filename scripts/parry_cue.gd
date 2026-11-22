class_name ParryCue
extends Node3D
## the "when to deflect" tell that rides above an enemy's head (souls_rat.gd):
##
##   deflectable hit -> a white-gold GLINT (four point star) with a RING closing in on it. the ring
##                     meets the star exactly when the hit lands, the star flares, so: press
##                     dodge + swat (cat_parry.gd) just before the ring closes
##   perilous hit    -> a red diamond with a ! and a red ring: can't be deflected, dodge it
##
## plus the enemy's POSTURE bar under it (fills from the middle out, sekiro style; goes red and
## flashes when it breaks: that's the opening for a finishing swat).
##
## all billboards, drawn on top (no depth test) so you can read them mid fight. no-op headless.

const STAR_SIZE := 0.07
const RING_FROM := 4.5        # ring starts this many star sizes out
const FLARE_T := 0.14         # after the hit: the star flares and fades

static var _tex := {}

var t := 0.0
var lead := 0.0               # s from the cue to the hit
var perilous := false
var live := false
var scale_k := 1.0            # rat size
var posture_frac := 0.0
var broken := false

var _star: MeshInstance3D
var _ring: MeshInstance3D
var _peril: MeshInstance3D
var _bar_bg: MeshInstance3D
var _bar: MeshInstance3D
var _ok := false
var cues := 0                 # tests
var last_lead := 0.0


func _ready() -> void:
	_ok = DisplayServer.get_name() != "headless"
	if not _ok:
		return
	_star = _quad(_get_tex("star"), Color(1, 0.95, 0.75, 0))
	_ring = _quad(_get_tex("ring"), Color(1, 0.95, 0.75, 0))
	_peril = _quad(_get_tex("peril"), Color(1, 0.15, 0.1, 0))
	_bar_bg = _quad(null, Color(0.05, 0.04, 0.03, 0.0), Vector2(1, 1))
	_bar = _quad(null, Color(1.0, 0.62, 0.15, 0.0), Vector2(1, 1))
	_bar_bg.position = Vector3(0, -0.055, 0)
	_bar.position = Vector3(0, -0.055, 0)
	_bar.sorting_offset = 0.01
	for m in [_star, _ring, _peril, _bar_bg, _bar]:
		m.visible = false


func _quad(tex: Texture2D, col: Color, size := Vector2.ONE) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.render_priority = 10
	m.albedo_color = col
	if tex:
		m.albedo_texture = tex
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _mat(mi: MeshInstance3D) -> StandardMaterial3D:
	return (mi.mesh as QuadMesh).material as StandardMaterial3D


## a hit lands in `in_s` seconds
func cue(in_s: float, is_perilous: bool) -> void:
	t = 0.0
	lead = maxf(in_s, 0.05)
	last_lead = lead
	perilous = is_perilous
	live = true
	cues += 1
	if _ok:
		CatSfx.play_at("cue_peril" if perilous else "cue_glint", global_position, 0.8 if perilous else 0.55)


func cancel() -> void:
	live = false


func _process(dt: float) -> void:
	if not _ok:
		return
	var s := STAR_SIZE * scale_k
	# posture bar: from the middle out, only while there's something on it
	var show_bar := posture_frac > 0.02 or broken
	_bar_bg.visible = show_bar
	_bar.visible = show_bar
	if show_bar:
		var w := 0.2 * scale_k
		_bar_bg.scale = Vector3(w + 0.008, 0.016 * scale_k + 0.006, 1)
		_mat(_bar_bg).albedo_color.a = 0.7
		var f := 1.0 if broken else posture_frac
		_bar.scale = Vector3(maxf(w * f, 0.001), 0.016 * scale_k, 1)
		var c := Color(1.0, 0.18, 0.1) if broken else Color(1.0, 0.62 - 0.3 * f, 0.15)
		c.a = 0.95 if not broken else 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.025)
		_mat(_bar).albedo_color = c
	if not live:
		for m in [_star, _ring, _peril]:
			m.visible = false
		return
	t += dt
	var col := Color(1.0, 0.18, 0.1) if perilous else Color(1.0, 0.95, 0.75)
	var u := clampf(t / lead, 0.0, 1.0)
	var after := t - lead
	if after > FLARE_T:
		live = false
		return
	# the ring closes in on the star, speeding up at the end (easier to read the moment)
	_ring.visible = after < 0.0
	if _ring.visible:
		var rs := lerpf(RING_FROM, 1.0, u * u * (3.0 - 2.0 * u) * 0.5 + u * 0.5)
		_ring.scale = Vector3.ONE * s * rs
		var rc := col
		rc.a = smoothstep(0.0, 0.25, u) * 0.9
		_mat(_ring).albedo_color = rc
	_star.visible = not perilous or after >= 0.0
	if _star.visible:
		var sc := lerpf(0.55, 1.0, u)
		var a := smoothstep(0.0, 0.2, u) * 0.85
		if after >= 0.0:
			var k := after / FLARE_T
			sc = 1.0 + 1.6 * k
			a = 1.0 - k
		_star.scale = Vector3.ONE * s * sc
		_star.rotation.z = 0.0
		var stc := col
		stc.a = a
		_mat(_star).albedo_color = stc
	_peril.visible = perilous
	if perilous:
		var pa := 1.0 if after < 0.0 else 1.0 - after / FLARE_T
		var pulse := 1.0 + 0.12 * sin(t * 26.0)
		_peril.scale = Vector3.ONE * s * 1.6 * pulse
		_peril.position = Vector3(0, 0.03 * scale_k, 0)
		_mat(_peril).albedo_color = Color(1.0, 0.12, 0.08, pa)


# ---------------------------------------------------------------- textures (built once)

static func _get_tex(id: String) -> Texture2D:
	if _tex.has(id):
		return _tex[id]
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var px := (x + 0.5) / n * 2.0 - 1.0
			var py := (y + 0.5) / n * 2.0 - 1.0
			var r := sqrt(px * px + py * py)
			var a := 0.0
			match id:
				"star":
					# four point glint: a hot core, two thin streaks, a soft halo
					var core := exp(-r * r * 60.0)
					var streak := exp(-absf(py) * 40.0) * maxf(1.0 - absf(px), 0.0) + exp(-absf(px) * 40.0) * maxf(1.0 - absf(py), 0.0)
					var diag := (exp(-absf(px - py) * 30.0) + exp(-absf(px + py) * 30.0)) * maxf(0.5 - r, 0.0)
					a = clampf(core + streak * 0.9 + diag * 0.6 + exp(-r * 5.0) * 0.25, 0.0, 1.0)
				"ring":
					a = exp(-pow((r - 0.86) / 0.05, 2.0))
				"peril":
					# a diamond outline with a ! in it
					var d := absf(px) + absf(py)
					a = exp(-pow((d - 0.8) / 0.06, 2.0))
					if d < 0.72:
						a = 0.25
					if absf(px) < 0.07 and py > -0.42 and py < 0.14:
						a = 1.0
					if Vector2(px, py - 0.32).length() < 0.08:
						a = 1.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_tex[id] = tex
	return tex
