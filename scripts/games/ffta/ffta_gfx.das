options gen2
options indenting = 4

// Pictures from the ROM: the units' map sprites and the item icons
// (research/notes.md, "Graphics"), decoded into textures by gba_gfx.cpp.
// Off by default: View -> "ROM sprites" / "ROM icons" (saved in local.cfg).
module ffta_gfx shared public

require gba_mem
require ../../app/shell.das
require ffta_battle

let private CHARACTER_TABLE = 0x085273D8u   // 14 bytes per story character, +0x04 sprite set
let private SPRITE_SETS = 0x08390E44u        // per set: 84 animations, 12 bytes each
let private SPRITE_TILES = 0x0869B89Cu        // 4bpp frames; animation entry +0x00 = offset
let private SPRITE_LAYOUTS = 0x08852E7Cu      // frame layouts; animation entry +0x04 = offset
let private SPRITE_PALETTES = 0x08419D60u     // 16 colours per row; row = wrapper +0x1E
let private ICONS = 0x083C83FCu               // "A7" archive, entry = item id
let private ICON_PALETTE_INDEX = 0x083C7FE4u  // byte +4 + 2 * item: palette << 4
let private ICON_PALETTES = 0x0841A100u       // 3 palettes of 16 colours
let private ICON_BASE = 65536                 // 0x10000 = GBA_GFX_ICON_BASE: icon ids drawn by gba_gfx

var rom_sprites = false
var rom_icons = false

// a story character's own set, else the job's (+0x07 through the parent chain)
def unit_sprite_set(un : BattleUnit) : int {
    if (un.character > 1) {
        return int(gba_read8(CHARACTER_TABLE + uint(un.character) * 14u + 4u))
    }
    return int(read_job(uint(un.job_id), uint(un.job2)).sprite)
}

// The first frame of the standing animation (0 facing +y / +x, 1 facing
// -x / -y; -y and +x mirrored) as a gba_gfx handle, -1 when off or absent.
def unit_sprite(un : BattleUnit) : int {
    if (!rom_sprites || !gba_has_rom()) {
        return -1
    }
    let set_ptr = gba_read32(SPRITE_SETS + uint(unit_sprite_set(un)) * 4u)
    if (set_ptr < 0x08000000u || set_ptr >= 0x0A000000u) {
        return -1
    }
    let f = un.facing & 3
    let anim = gba_read32(set_ptr + (f == 0 || f == 3 ? 0u : 12u))
    if (anim < 0x08000000u || anim >= 0x0A000000u || gba_read32(anim) == 0u) {
        return -1
    }
    return gba_gfx_sprite(shell_renderer(), SPRITE_TILES + gba_read32(anim + 4u), SPRITE_LAYOUTS + gba_read32(anim + 8u),
        SPRITE_PALETTES + uint(un.side & 15) * 32u, f >= 2)
}

// the icon of an item as an icon id for bl_icon / bl_menu_item; -1 when off
def item_icon(id : int) : int {
    if (!rom_icons || !gba_has_rom() || id < 0) {
        return -1
    }
    let k = gba_read8(ICON_PALETTE_INDEX + 4u + uint(id) * 2u) >> 4u
    let h = gba_gfx_icon(shell_renderer(), ICONS, id, ICON_PALETTES + k * 32u)
    return h >= 0 ? ICON_BASE + h : -1
}
