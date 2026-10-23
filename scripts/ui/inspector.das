options gen2
options indenting = 4

// Reflection inspector (in the spirit of Odin Inspector): inspect(value)
// walks the fields of a struct at compile time (daslib/apply) and draws
// a Blendish widget per field type. Field annotations tune the widget:
//   @caption = "Max HP" caption instead of the prettified field name
//   @min = 0 @max = 99  bounds; int / float with both become a slider
//   @step = 0.5         drag / arrow step of a number
//   @hide = true        the field is not shown
//   @readonly = true    shown as a label
module inspector shared public

require imgui
require dasimgui/imgui_boost
require daslib/apply
require daslib/rtti
require daslib/enum_trait
require math
require strings
require bl_imgui
require bnd_const

typedef FieldAnnotations = array<tuple<name : string; data : RttiValue>>

struct InspectorRow {
    x : float
    y : float
    w : float
    label_w : float
}

def private ann_value(a : FieldAnnotations; name : string; var out : float&) : bool {
    for (t in a) {
        if (t.name == name) {
            if (t.data is tInt) {
                out = float(t.data as tInt)
                return true
            } elif (t.data is tFloat) {
                out = t.data as tFloat
                return true
            }
        }
    }
    return false
}

def private ann_flag(a : FieldAnnotations; name : string) : bool {
    for (t in a) {
        if (t.name == name && t.data is tBool) {
            return t.data as tBool
        }
    }
    return false
}

// "max_hp" -> "Max Hp", or @caption
def field_caption(name : string; a : FieldAnnotations) : string {
    for (t in a) {
        if (t.name == "caption" && t.data is tString) {
            return t.data as tString
        }
    }
    var res = ""
    var up = true
    for (ch in name) {
        if (ch == '_') {
            res += " "
            up = true
        } else {
            let c = up && ch >= 'a' && ch <= 'z' ? ch - 'a' + 'A' : ch
            res += to_char(c)
            up = false
        }
    }
    return res
}

def private caption_column(var r : InspectorRow; caption : string) {
    SetCursorScreenPos(ImVec2(r.x, r.y))
    bl_label("{caption}:", -1, r.label_w)
    SetCursorScreenPos(ImVec2(r.x + r.label_w, r.y))
}

def private next_row(var r : InspectorRow) {
    r.y += u(23.0)
}

def private number_field(id, caption : string; var v : float&; precision : int; a : FieldAnnotations; var r : InspectorRow) : bool {
    var lo, hi : float
    var step = precision == 0 ? 0.25 : 0.01
    ann_value(a, "step", step)
    let has_lo = ann_value(a, "min", lo)
    let has_hi = ann_value(a, "max", hi)
    let w = r.w - r.label_w
    caption_column(r, caption)
    var changed = false
    if (has_lo && has_hi) {
        changed = bl_slider(id, "", v, lo, hi, fmt_number(v, precision), w)
    } else {
        changed = bl_number(id, "", v, step, precision, w)
    }
    if (has_lo) {
        v = max(v, lo)
    }
    if (has_hi) {
        v = min(v, hi)
    }
    next_row(r)
    return changed
}

def inspect_field(id, caption : string; var v : int&; a : FieldAnnotations; var r : InspectorRow) {
    var f = float(v)
    number_field(id, caption, f, 0, a, r)
    v = int(round(f))
}

def inspect_field(id, caption : string; var v : float&; a : FieldAnnotations; var r : InspectorRow) {
    number_field(id, caption, v, 2, a, r)
}

def inspect_field(id, caption : string; var v : bool&; a : FieldAnnotations; var r : InspectorRow) {
    SetCursorScreenPos(ImVec2(r.x + r.label_w, r.y))
    bl_option(id, caption, v)
    next_row(r)
}

def inspect_field(id, caption : string; var v : string&; a : FieldAnnotations; var r : InspectorRow) {
    caption_column(r, caption)
    bl_string(id, v, r.w - r.label_w)
    next_row(r)
}

def inspect_field(id, caption : string; var v : auto(E)&; a : FieldAnnotations; var r : InspectorRow) {
    static_if (typeinfo is_enum(v)) {
        var names : array<string>
        var sel = 0
        for (e in each(v)) {
            if (e == v) {
                sel = length(names)
            }
            names |> push("{e}")
        }
        caption_column(r, caption)
        if (bl_choice(id, names, sel, r.w - r.label_w)) {
            var k = 0
            for (e in each(v)) {
                if (k == sel) {
                    v = e
                }
                k++
            }
        }
        next_row(r)
    } else {
        caption_column(r, caption)
        bl_label("({typeinfo typename(v)})")
        next_row(r)
    }
}

// Does field `name` of value differ from the same field of original?
def field_changed(value, original : auto(T); name : string) : bool {
    var res = false
    apply(value) $(vn : string; vf; va) {
        if (vn == name) {
            apply(original) $(on : string; of; oa) {
                static_if (typeinfo typename(vf) == typeinfo typename(of)) {
                    static_if (typeinfo is_enum(vf) || typeinfo is_string(vf) || typeinfo is_numeric(vf) || typeinfo typename(vf) == "bool") {
                        if (on == name && vf != of) {
                            res = true
                        }
                    }
                }
            }
        }
    }
    return res
}

// Copies field `name` of original into value.
def revert_field(var value : auto(T)&; original : T; name : string) {
    apply(value) $(vn : string; var vf; va) {
        if (vn == name) {
            apply(original) $(on : string; of; oa) {
                static_if (typeinfo typename(vf) == typeinfo typename(of)) {
                    static_if (typeinfo is_enum(vf) || typeinfo is_string(vf) || typeinfo is_numeric(vf) || typeinfo typename(vf) == "bool") {
                        if (on == name) {
                            vf = of
                        }
                    }
                }
            }
        }
    }
}

// The revert button at the end of a row: an arrow back to the saved value.
def bl_revert_button(id : string; x, y : float) : bool {
    SetCursorScreenPos(ImVec2(x, y))
    return bl_tool_button(id, "", BND_ICON_LOOP_BACK, u(22.0))
}

// As inspect(), and an editable field that differs from the same field
// of original gets a revert button at the end of its row.
def inspect(id : string; var value : auto(T)&; original : T; x, y, w : float) : float {
    let bw = u(24.0)
    var r = InspectorRow(x = x, y = y, w = w - bw, label_w = floor(w * 0.4))
    var revert = ""
    apply(value) $(name : string; var field; annotations) {
        if (ann_flag(annotations, "hide")) {
            return
        }
        let caption = field_caption(name, annotations)
        if (ann_flag(annotations, "readonly")) {
            caption_column(r, caption)
            bl_label("{field}")
            next_row(r)
            return
        }
        let row_y = r.y
        let changed = field_changed(value, original, name)
        inspect_field("{id}.{name}", caption, field, annotations, r)
        if (changed && bl_revert_button("{id}.{name}.revert", x + w - u(22.0), row_y)) {
            revert = name
        }
    }
    if (revert != "") {
        revert_field(value, original, revert)
    }
    return r.y
}

// Draws every field of value from (x, y) in width w; returns the bottom y.
def inspect(id : string; var value : auto(T)&; x, y, w : float) : float {
    var r = InspectorRow(x = x, y = y, w = w, label_w = floor(w * 0.4))
    apply(value) $(name : string; var field; annotations) {
        if (ann_flag(annotations, "hide")) {
            return
        }
        let caption = field_caption(name, annotations)
        if (ann_flag(annotations, "readonly")) {
            caption_column(r, caption)
            bl_label("{field}")
            next_row(r)
            return
        }
        inspect_field("{id}.{name}", caption, field, annotations, r)
    }
    return r.y
}
