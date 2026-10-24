options gen2
options indenting = 4

// A game plugs into the shell as a GameModule: its data model and the
// contents of the shell's panels. The shell owns the window, docking,
// menus, style and the log; a game only fills rectangles it is given.
module game shared public

class GameModule {
    def abstract id() : string
    def abstract title() : string
    // left panel: the list of units / items to pick from
    def abstract draw_roster(x, y, w, h : float) : void
    // right panel: fields of the selected object; returns the bottom y
    def abstract draw_inspector(x, y, w : float) : float
    // center panel: the battle scene
    def abstract draw_scene(x, y, w, h : float) : void
    // bottom panel: the calculation for the current selection
    def abstract draw_calc(x, y, w, h : float) : void
    def abstract status() : string
    // the game became the current one (and before its first frame): the
    // games share one loaded ROM and state, so it loads its own again
    def activate() : void {
        pass
    }
    // the web page put new files at --state / --rom: a game whose ROM code
    // this is takes them (reload: load them again)
    def accepts_rom(code : string) : bool {
        return false
    }
    def reload() : void {
        pass
    }
    // the game's own items at the end of the View menu, and their action
    def view_items() : array<string> {
        return <- array<string>()
    }
    def view_pick(i : int) : void {
        pass
    }
}

var private games : array<GameModule?>

def register_game(var g : GameModule?) {
    games |> push(g)
}

def game_count() : int {
    return length(games)
}

def game_at(i : int) : GameModule? {
    return games[i]
}

// ------------------------------------------------------------ log

var private log_lines : array<string>

def log_line(s : string) {
    log_lines |> push(s)
    if (length(log_lines) > 200) {
        log_lines |> erase(0)
    }
}

def log_count() : int {
    return length(log_lines)
}

def log_at(i : int) : string {
    return log_lines[i]
}
