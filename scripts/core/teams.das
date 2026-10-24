options gen2

// Sides of a battle, shared by the games: what the field, the roster and
// the turn list color by. A game maps its own flags to these.
module teams shared public

let TEAM_PLAYER = 0
let TEAM_ENEMY = 1
let TEAM_GUEST = 2
let TEAM_JUDGE = 3
