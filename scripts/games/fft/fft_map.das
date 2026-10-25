options gen2
options indenting = 4

// FFT (PSX): the battle map's mesh from the disc for the field
// (research/fft/notes.md, "Graphics"). The map: the MAPnnn.GNS the game
// holds in RAM (psx_find_map). Its 20-byte records: +3 the situation
// (0 the default), +5 the resource (0x17 a texture, 0x2E the primary
// mesh), +8 u32 sector, +12 u32 size. The mesh: u32 pointers at 0x40
// (the polygons) and 0x44 (16 palettes); at the polygons u16 counts of
// textured triangles, quads, untextured triangles, quads, then s16 x, y,
// z per corner (x, z: 28 a tile, y: -12 a height step), normals of the
// textured ones, their texture records (u, v; palette; -; u, v; page;
// -; u, v [; u, v]: 10 / 12 bytes), 4 bytes per untextured polygon.
module fft_map shared public

require gba_mem
require math
require strings
require ../../ui/battle_field.das

let MAP_TILE = 28.0
let MAP_STEP = 12.0

struct private GnsRes {
    situation : int
    kind : int
    lba : int
    size : int
}

def private gns_records(g : int) : array<GnsRes> {
    var res : array<GnsRes>
    var p = 0
    while (p + 20 <= psx_buf_size(g)) {
        let kind = int(psx_buf_read8(g, p + 5))
        if (kind == 0x31) {
            break
        }
        res |> push(GnsRes(situation = int(psx_buf_read8(g, p + 3)), kind = kind, lba = int(psx_buf_read32(g, p + 8)),
            size = int(psx_buf_read32(g, p + 12))))
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
def load_map_mesh(renderer; var polys : array<FieldPoly>) : string {
    polys |> clear()
    if (!psx_has_disc()) {
        return "no disc"
    }
    let no = psx_find_map()
    if (no < 0) {
        return "the map is not found"
    }
    let g = psx_disc_file("MAP/MAP{no < 100 ? (no < 10 ? "00" : "0") : ""}{no}.GNS")
    let recs <- gns_records(g)
    var tex = GnsRes(lba = -1)
    var mesh_res = GnsRes(lba = -1)
    for (r in recs) {
        if (r.kind == 0x17 && (tex.lba < 0 || r.situation == 0)) {
            tex = r
        }
        if (r.kind == 0x2E && mesh_res.lba < 0) {
            mesh_res = r
        }
    }
    if (tex.lba < 0 || mesh_res.lba < 0) {
        return "MAP{no}: no texture / mesh"
    }
    let tb = psx_disc_read(tex.lba, tex.size)
    let mb = psx_disc_read(mesh_res.lba, mesh_res.size)
    let pp = int(psx_buf_read32(mb, 64))
    let pal = int(psx_buf_read32(mb, 68))
    let nt = int(psx_buf_read16(mb, pp))
    let nq = int(psx_buf_read16(mb, pp + 2))
    let nut = int(psx_buf_read16(mb, pp + 4))
    let nuq = int(psx_buf_read16(mb, pp + 6))
    if (nt + nq + nut + nuq > 20000) {
        return "MAP{no}: a bad mesh"
    }
    var p = pp + 8
    let tv = p
    let qv = tv + nt * 18
    let utv = qv + nq * 24
    let uqv = utv + nut * 18
    p = uqv + nuq * 24 + (nt * 3 + nq * 4) * 6        // the normals
    let tuv = p
    let quv = tuv + nt * 10
    // textured: (corner offsets, the record, its corners' uv offsets)
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
