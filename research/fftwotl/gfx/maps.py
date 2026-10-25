"""Battle map of FFT: WotL (PSP): GNS index, primary mesh, texture; a rough isometric render.

MAP/MAPnnn.GNS: 20-byte records: +2 arrangement, +3 situation (time/weather), +5 resource type
(0x17 texture, 0x2E primary mesh, 0x2F/0x30 override / alternate mesh, 0x31 ?, >= 0x80: other),
+12 resource index k -> fftpack file (first file of MAPnnn) + k.
Mesh file: u32 pointers at 0x40.. (0x40 primary mesh, 0x44 texture palettes, 0x68 terrain).
Primary mesh: u16 counts (textured tris, textured quads, untextured tris, untextured quads);
s16 x,y,z per vertex (all four groups in that order; y up is negative); s16 normals of textured
polygons; texture info 10 B per textured tri / 12 B per quad (u,v a; palette; ?; u,v b; page in
bits 0-1; ?; u,v c [; u,v d]); 4 B per untextured polygon; 2 B per textured polygon (terrain tile).
Texture: 256 x 1024 4bpp (131072 B), v_abs = 256 * page + v; 16 palettes of 16 BGR555 at 0x44.
"""
import os, struct, sys
import numpy as np
from PIL import Image
import fftpack as fp
import sprites as S


def gns(m):
    i = fp.find('MAP/MAP%03d.GNS' % m)
    d = fp.get(i)
    first = min(k for k, v in fp.names().items() if v.startswith('MAP/MAP%03d.' % m))
    recs = []
    for o in range(0, len(d) - 19, 20):
        r = d[o:o + 20]
        if r[0] not in (0x22, 0x30, 0x70) or r[5] >= 0x80:
            continue
        recs.append(dict(arr=r[2], sit=r[3], type=r[5], file=first + r[12]))
    return recs


def load_mesh(d):
    p_mesh, p_pal = struct.unpack_from('<2I', d, 0x40)
    tt, tq, ut, uq = struct.unpack_from('<4H', d, p_mesh)
    nv = tt * 3 + tq * 4 + ut * 3 + uq * 4
    o = p_mesh + 8
    v = np.array(struct.unpack_from('<%dh' % (3 * nv), d, o), dtype=np.float32).reshape(-1, 3)
    o += 6 * nv + 6 * (tt * 3 + tq * 4)          # skip normals
    polys = []
    vi = 0
    for k in range(tt):
        b = d[o + 10 * k:o + 10 * k + 10]
        polys.append((v[vi:vi + 3], [(b[0], b[1]), (b[4], b[5]), (b[8], b[9])], b[2] & 15, b[6] & 3))
        vi += 3
    o += 10 * tt
    for k in range(tq):
        b = d[o + 12 * k:o + 12 * k + 12]
        q = v[vi:vi + 4]
        uv = [(b[0], b[1]), (b[4], b[5]), (b[8], b[9]), (b[10], b[11])]
        polys.append((q[[0, 1, 2]], [uv[0], uv[1], uv[2]], b[2] & 15, b[6] & 3))
        polys.append((q[[1, 3, 2]], [uv[1], uv[3], uv[2]], b[2] & 15, b[6] & 3))
        vi += 4
    o += 12 * tq
    untex = []
    for k in range(ut):
        untex.append(v[vi:vi + 3]); vi += 3
    for k in range(uq):
        q = v[vi:vi + 4]; untex += [q[[0, 1, 2]], q[[1, 3, 2]]]; vi += 4
    pal = [[S.bgr555(struct.unpack_from('<H', d, p_pal + 32 * p + 2 * c)[0], c) for c in range(16)]
           for p in range(16)]
    return dict(counts=(tt, tq, ut, uq), polys=polys, untex=untex, pal=pal)


def texture(d):
    a = np.frombuffer(d[:131072], dtype=np.uint8)
    t = np.empty(a.size * 2, dtype=np.uint8)
    t[0::2] = a & 15
    t[1::2] = a >> 4
    return t.reshape(1024, 256)


def render(mesh, tex, scale=2.0, yaw=45.0, pitch=30.0):
    """Orthographic view rotated by yaw around Y and tilted by pitch; z-buffered, nearest texel."""
    cy, sy = np.cos(np.radians(yaw)), np.sin(np.radians(yaw))
    cp, sp = np.cos(np.radians(pitch)), np.sin(np.radians(pitch))

    def proj(p):
        x, y, z = p[:, 0], -p[:, 1], p[:, 2]
        xr, zr = x * cy - z * sy, x * sy + z * cy
        return np.stack([xr * scale, (-y * cp + zr * sp) * scale, zr * cp + y * sp], 1)

    allv = np.concatenate([pp[0] for pp in mesh['polys']] + mesh['untex'])
    pv = proj(allv)
    mn, mx = pv.min(0), pv.max(0)
    W, H = int(mx[0] - mn[0]) + 20, int(mx[1] - mn[1]) + 20
    img = np.zeros((H, W, 4), np.uint8)
    img[:] = (40, 40, 60, 255)
    zb = np.full((H, W), -1e9, np.float32)
    pal = np.array(mesh['pal'], np.uint8)
    items = [(t, uv, pl, pg) for t, uv, pl, pg in mesh['polys']] + [(t, None, 0, 0) for t in mesh['untex']]
    for tri, uv, pl, pg in items:
        q = proj(tri) - mn + 10
        x0, y0 = np.floor(q[:, :2].min(0)).astype(int)
        x1, y1 = np.ceil(q[:, :2].max(0)).astype(int)
        if x1 <= x0 or y1 <= y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        (ax, ay), (bx, by), (cx, cyy) = q[0, :2], q[1, :2], q[2, :2]
        den = (by - cyy) * (ax - cx) + (cx - bx) * (ay - cyy)
        if abs(den) < 1e-6:
            continue
        l0 = ((by - cyy) * (xs - cx) + (cx - bx) * (ys - cyy)) / den
        l1 = ((cyy - ay) * (xs - cx) + (ax - cx) * (ys - cyy)) / den
        l2 = 1 - l0 - l1
        m = (l0 >= 0) & (l1 >= 0) & (l2 >= 0)
        if not m.any():
            continue
        z = l0 * q[0, 2] + l1 * q[1, 2] + l2 * q[2, 2]
        sub = zb[y0:y1, x0:x1]
        m &= z > sub
        if uv is None:
            col = np.array([90, 90, 90, 255], np.uint8)
            img[y0:y1, x0:x1][m] = col
        else:
            u = l0 * uv[0][0] + l1 * uv[1][0] + l2 * uv[2][0]
            v = l0 * uv[0][1] + l1 * uv[1][1] + l2 * uv[2][1]
            ti = tex[np.clip(v.astype(int), 0, 255) + 256 * pg, np.clip(u.astype(int), 0, 255)]
            c = pal[pl][ti]
            m &= ti != 0
            img[y0:y1, x0:x1][m] = c[m]
        sub[m] = z[m]
    return Image.fromarray(img)


def main(m=56):
    recs = gns(m)
    for r in recs:
        print('arr %d sit 0x%02X type 0x%02X file %d %s' % (r['arr'], r['sit'], r['type'], r['file'],
                                                         fp.names().get(r['file'])))
    mesh_f = next(r['file'] for r in recs if r['type'] == 0x2E)
    tex_f = next(r['file'] for r in recs if r['type'] == 0x17 and r['sit'] == 0 and r['arr'] == 0)
    mesh = load_mesh(fp.get(mesh_f))
    print('mesh', mesh_f, 'counts', mesh['counts'], 'texture', tex_f)
    tex = texture(fp.get(tex_f))
    Image.fromarray(np.array(mesh['pal'], np.uint8)[0][tex]).save(os.path.join(fp.OUT, 'map%03d_tex_pal0.png' % m))
    for yaw in (45, 135, 225, 315):
        render(mesh, tex, yaw=yaw).save(os.path.join(fp.OUT, 'map%03d_yaw%d.png' % (m, yaw)))
    print('rendered to', fp.OUT)


if __name__ == '__main__':
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 56)
