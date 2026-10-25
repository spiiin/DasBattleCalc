options gen2
options indenting = 4

// FFT: WotL (PSP): the battle map's mesh from the ISO for the field
// (research/fftwotl/graphics.md, "Battle map"). The map: its MAPnnn.GNS,
// which the game holds whole in RAM (psp_find_map: its fftpack file).
// Its 20-byte records: +3 the situation (0 the default), +5 the resource
// (0x17 a texture, 0x2E the primary mesh, >= 0x80 the end), +12 the
// index k: fftpack file = the map's first file + k (the GNS is the file
// after the last one). The mesh is the PSX one (fft_map.das): u32
// pointers at 0x40 (the polygons) and 0x44 (16 palettes); u16 counts of
// textured triangles, quads, untextured triangles, quads, then s16 x, y,
// z per corner (x, z: 28 a tile, y: -12 a height step), normals of the
// textured ones, their texture records (10 / 12 bytes).
module fftwotl_map shared public

require gba_mem
require math
require ../../ui/battle_field.das

let private MAP_TILE = 28.0
let private MAP_STEP = 12.0

struct private GnsRes {
    situation : int
    kind : int
    index : int
}

def private gns_records(g : int) : array<GnsRes> {
    var res : array<GnsRes>
    var p = 0
    while (p + 20 <= psx_buf_size(g)) {
        let kind = int(psx_buf_read8(g, p + 5))
        if (kind == 0 || kind >= 0x80) {
            break
        }
        res |> push(GnsRes(situation = int(psx_buf_read8(g, p + 3)), kind = kind, index = int(psx_buf_read8(g, p + 12))))
        p += 20
    }
    return <- res
}

def private s16(h, off : int) : float {
    let v = int(psx_buf_read16(h, off))
    return float(v >= 0x8000 ? v - 0x10000 : v)
}

// a corner in map coordinates: tile centers at whole numbers; the height
// as the field's (the shown height + 1)
def private corner(h, off : int) : float3 {
    return float3(s16(h, off) / MAP_TILE - 0.5, s16(h, off + 4) / MAP_TILE - 0.5, -s16(h, off + 2) / MAP_STEP + 1.0)
}

// the battle map's polygons; "" or the error
// (renderer: the SDL renderer for the textures)
def load_map_mesh_w(renderer; var polys : array<FieldPoly>) : string {
    polys |> clear()
    if (!psx_has_disc() || psp_pack_count() == 0) {
        return "no ISO"
    }
    let gns = psp_find_map()
    if (gns < 0) {
        return "the map is not found"
    }
    let recs <- gns_records(psp_pack_file(gns))
    var last = 0
    var tex = -1
    var mesh_k = -1
    for (r in recs) {
        last = max(last, r.index)
        if (r.kind == 0x17 && (tex < 0 || r.situation == 0)) {
            tex = r.index
        }
        if (r.kind == 0x2E && mesh_k < 0) {
            mesh_k = r.index
        }
    }
    if (tex < 0 || mesh_k < 0) {
        return "GNS {gns}: no texture / mesh"
    }
    let first = gns - 1 - last
    let tb = psp_pack_file(first + tex)
    let mb = psp_pack_file(first + mesh_k)
    let pp = int(psx_buf_read32(mb, 64))
    let pal = int(psx_buf_read32(mb, 68))
    let nt = int(psx_buf_read16(mb, pp))
    let nq = int(psx_buf_read16(mb, pp + 2))
    let nut = int(psx_buf_read16(mb, pp + 4))
    let nuq = int(psx_buf_read16(mb, pp + 6))
    if (nt + nq + nut + nuq > 20000 || psx_buf_size(mb) == 0) {
        return "GNS {gns}: a bad mesh"
    }
    let tv = pp + 8
    let qv = tv + nt * 18
    let utv = qv + nq * 24
    let uqv = utv + nut * 18
    let tuv = uqv + nuq * 24 + (nt * 3 + nq * 4) * 6        // after the normals
    let quv = tuv + nt * 10
    for (i in range(nt + nq)) {
        let quad = i >= nt
        let k = quad ? i - nt : i
        let v0 = quad ? qv + k * 24 : tv + k * 18
        let r = quad ? quv + k * 12 : tuv + k * 10
        let palette = int(psx_buf_read8(mb, r + 2)) & 15
        let page = int(psx_buf_read8(mb, r + 6)) & 3
        var pl = FieldPoly(tex = psx_map_texture(renderer, tb, mb, pal, page, palette))
        // the corners 0 1 / 2 3 of a quad: around as 0 1 3 2
        let idx = quad ? fixed_array<int>(0, 1, 3, 2) : fixed_array<int>(0, 1, 2, 2)
        let uvo = fixed_array<int>(0, 4, 8, 10)
        for (c in range(4)) {
            let j = idx[c]
            pl.p[c] = corner(mb, v0 + j * 6)
            pl.uv[c] = float2((float(psx_buf_read8(mb, r + uvo[j])) + 0.5) / 256.0,
                (float(psx_buf_read8(mb, r + uvo[j] + 1)) + 0.5) / 256.0)
        }
        polys |> push(pl)
    }
    for (i in range(nut + nuq)) {
        let quad = i >= nut
        let v0 = quad ? uqv + (i - nut) * 24 : utv + i * 18
        let idx = quad ? fixed_array<int>(0, 1, 3, 2) : fixed_array<int>(0, 1, 2, 2)
        var pl = FieldPoly(color = 0x303038ffu)
        for (c in range(4)) {
            pl.p[c] = corner(mb, v0 + idx[c] * 6)
        }
        polys |> push(pl)
    }
    return ""
}

// the standing frames (the first of SEQ animations 6 / 7) by the sheet's
// SHP type: TYPE1 / TYPE2 11 / 16, CYOKO 9 / 14, MON 2 / 4
def stand_frame_w(sheet : int; back : bool) : int {
    let t = psp_sprite_type(sheet)
    if (t == 2) {
        return back ? 14 : 9
    } elif (t == 3 || t == 5) {
        return back ? 4 : 2
    }
    return back ? 16 : 11
}
