options gen2
options indenting = 4

// local.cfg next to the project: key=value lines shared by the games
// (each keeps its own keys; writing one key keeps the others).
module config shared public

require daslib/fio
require gui_common
require strings
require daslib/strings_boost

def private config_path() : string {
    return "{gui_project_dir()}/local.cfg"
}

def private config_lines() : array<string> {
    var res : array<string>
    for (line in split(fread(config_path()), "\n")) {
        if (line != "") {
            res |> push(line)
        }
    }
    return <- res
}

def config_get(key : string; default_value : string = "") : string {
    for (line in config_lines()) {
        if (starts_with(line, "{key}=")) {
            return slice(line, length(key) + 1)
        }
    }
    return default_value
}

def config_set(key, value : string) {
    var lines <- config_lines()
    var found = false
    for (line in lines) {
        if (starts_with(line, "{key}=")) {
            line = "{key}={value}"
            found = true
        }
    }
    if (!found) {
        lines |> push("{key}={value}")
    }
    fwrite(config_path(), join(lines, "\n") + "\n")
}
