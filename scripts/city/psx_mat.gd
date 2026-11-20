extends RefCounted
## PSX materials with generated PLACEHOLDER textures (no art yet: checkers, planks, tiles, noise).
##   const Psx := preload("res://scripts/city/psx_mat.gd")
##   mesh.material = Psx.mat(Color(0.5, 0.5, 0.55), "concrete")
## kinds: plain, concrete, tile, crate, metal, checker, brick, asphalt, grass (32 px), and the
## facades windows / storefront (64 px = 8 m at uv_scale 0.125: 4 m bays, some windows lit).
## Replace with real textures later.

const SHADER := preload("res://scripts/city/psx_world.gdshader")
const SIZE := 32

static var _tex := {}


static func mat(col: Color, kind := "plain", uv_scale := 1.0, emission := 0.0, world_uv := true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("albedo_tex", tex(kind))
	m.set_shader_parameter("uv_scale", uv_scale)
	m.set_shader_parameter("emission", emission)
	m.set_shader_parameter("world_uv", world_uv)
	return m


static func tex(kind: String) -> ImageTexture:
	if _tex.has(kind):
		return _tex[kind]
	var size := 64 if kind in ["windows", "storefront"] else SIZE
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = hash(kind)
	var lit := [r.randf() < 0.35, r.randf() < 0.35, r.randf() < 0.35, r.randf() < 0.35]
	for y in size:
		for x in size:
			var v := 0.88 + r.randf() * 0.12
			match kind:
				"concrete":
					v = 0.66 + r.randf() * 0.24
					if y % 16 == 0:
						v *= 0.75
				"tile":
					v = 0.78 + r.randf() * 0.1
					if x % 16 == 0 or y % 16 == 0:
						v = 0.45
				"crate":
					v = 0.7 + r.randf() * 0.15
					if y % 8 == 0 or x == 0 or x == SIZE - 1 or abs(x - y) < 2 and false:
						v = 0.42
				"metal":
					v = 0.6 + r.randf() * 0.1 + (0.15 if (x + y) % 8 == 0 else 0.0)
				"checker":
					v = 0.95 if ((x / 8) + (y / 8)) % 2 == 0 else 0.55
				"brick", "windows", "storefront":
					v = 0.62 + r.randf() * 0.18
					if y % 4 == 0 or (x + (4 if (y / 4) % 2 == 0 else 0)) % 8 == 0:
						v = 0.4
					var bx := x % 32
					var by := y % 32
					var bay: int = (x / 32) + 2 * (y / 32)
					if kind == "windows" and bx >= 9 and bx < 23 and by >= 7 and by < 25:
						v = 0.12 if bx == 16 or by == 16 else (0.98 if lit[bay] else 0.16 + r.randf() * 0.05)
					elif kind == "storefront" and bx >= 3 and bx < 29 and by >= 8 and by < 32:
						v = 0.1 if bx == 3 or bx == 28 or by == 8 else (0.95 if bay % 3 != 2 else 0.2)
				"asphalt":
					v = 0.42 + r.randf() * 0.12 + (0.08 if r.randf() < 0.05 else 0.0)
				"grass":
					v = 0.55 + r.randf() * 0.35
			img.set_pixel(x, y, Color(v, v, v))
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t
