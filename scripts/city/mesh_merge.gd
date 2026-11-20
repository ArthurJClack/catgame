extends RefCounted
## Merges every MeshInstance3D under a node into ONE ArrayMesh with one surface per material
## (fewer nodes to cull and fewer draw calls: a Shitbox Rally car is ~20 meshes, merged it's a
## handful of surfaces). Keeps position, normal, uv (all the PSX shader uses).
##   const Merge := preload("res://scripts/city/mesh_merge.gd")
##   var r := Merge.merge(root)   # {mesh: ArrayMesh, mats: [Material per surface]}

static func merge(root: Node3D) -> Dictionary:
	var groups := {}        # material (or null) -> {v, n, uv, i}
	var order: Array = []
	var inv := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D.IDENTITY
	var list: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		list.push_front(root)
	for node in list:
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var xf := _rel(root, mi) if not root.is_inside_tree() else inv * mi.global_transform
		var nb := xf.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat: Material = mi.get_active_material(s)
			if not groups.has(mat):
				groups[mat] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "i": PackedInt32Array()}
				order.append(mat)
			var g: Dictionary = groups[mat]
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns = arr[Mesh.ARRAY_NORMAL]
			var uvs = arr[Mesh.ARRAY_TEX_UV]
			var idx = arr[Mesh.ARRAY_INDEX]
			var base: int = (g["v"] as PackedVector3Array).size()
			for k in vs.size():
				g["v"].append(xf * vs[k])
				g["n"].append((nb * (ns[k] as Vector3)).normalized() if ns != null else Vector3.UP)
				g["uv"].append(uvs[k] if uvs != null else Vector2.ZERO)
			if idx == null:
				for k in vs.size():
					g["i"].append(base + k)
			else:
				for k in (idx as PackedInt32Array):
					g["i"].append(base + k)
	var mesh := ArrayMesh.new()
	var mats: Array = []
	for mat in order:
		var g: Dictionary = groups[mat]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g["v"]
		arr[Mesh.ARRAY_NORMAL] = g["n"]
		arr[Mesh.ARRAY_TEX_UV] = g["uv"]
		arr[Mesh.ARRAY_INDEX] = g["i"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mats.append(mat)
	return {"mesh": mesh, "mats": mats}


## transform of `n` relative to `root` (for trees not in the scene yet)
static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
