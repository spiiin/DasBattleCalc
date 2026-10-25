# DasBattleCalc — подробное описание

Универсальный калькулятор / симулятор боёв для тактических игр на daslang + dasSDL3 + Dear ImGui (вид Blender 2.7 /
Blendish). Первая игра — **Final Fantasy Tactics Advance** (GBA, USA): загрузка сейва BizHawk, юниты текущего боя и
порядок ходов, рассчитанный так же, как в игре.

## Сборка и запуск

Нужна готовая сборка dasSDL3 (`<dasSDL3>/build/ninja`, Release, Ninja, MSVC /MD, `DASSDL3_WITH_IMGUI=ON`); путь —
переменная `DASSDL3_DIR` для `build.bat` (параметр `-DasSDL3` у `web/build.ps1`). Сейчас проект собирается на daScript
master с ещё не влитым PR про hex в аннотациях (`@offset = 0xD0`).

```bat
build.bat
build\bin\battlecalc.exe
```

Опции: `--state <файл .State>` и `--rom <FFTA (USA) .gba или .zip>` (последние пути запоминаются в `local.cfg`),
`--ui-scale K` (или `--ui-scale=K`), `--shot out.png [--frames N]`, `--script "F click X Y; F rclick X Y; F drag X0 Y0 X1 Y1; F key SCANCODE; ..."` (скриптовый ввод через очередь SDL).

Сейв — быстрое сохранение BizHawk 2.x с ядром mGBA (`GBA/State/*.mGBA.QuickSave1.State`). В нём RAM на момент
сохранения; батарейный `.SaveRAM` боя не содержит.

Тесты моделей: порядок ходов (повтор 22 ходов, записанных в игре), характеристики (экраны Status всех юнитов),
атака (17 прогнозов игры при правках RAM), дальность (правило клеток игры для меча, копья, лука, ружья),
способности (12 прогнозов и применений: support, Battle Tech), магия (Fire, Thunder, Cure, Protect), реакции
(Reflex, Strikeback, Counter, Bonecrusher по настоящим ударам), экспорт правок в сейв (запись, чтение обратно; `--out` —
куда писать новый сейв):

```bat
build\bin\battlecalc.exe tests\test_ffta_turn_order.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip>
build\bin\battlecalc.exe tests\test_ffta_stats.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip>
build\bin\battlecalc.exe tests\test_ffta_attack.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip>
build\bin\battlecalc.exe tests\test_ffta_reach.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip>
build\bin\battlecalc.exe tests\test_ffta_abilities.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip>
build\bin\battlecalc.exe tests\test_ffta_magic.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip>
build\bin\battlecalc.exe tests\test_ffta_reactions.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip>
build\bin\battlecalc.exe tests\test_ffta_export.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip> --out <new.State>
build\bin\battlecalc.exe tests\test_ffta_explore.das --state <ffta_test_battle1.State> --rom <FFTA (USA).zip>
build\bin\battlecalc.exe tests\test_ffta_battle2.das --state <ffta_test_battle2.State> --start <ffta_test_battle2_start.State> --rom <FFTA (USA).zip>
build\bin\battlecalc.exe tests\test_explore.das
build\bin\battlecalc.exe tests\test_ffta2_export.das --state <ffta2_test_battle1.State> --rom <FFTA2 (USA).zip> --out <new.State>
build\bin\battlecalc.exe tests\test_ffta2_reaction.das --state <сейв FFTA2: Luso рядом с Sasarr> --rom <FFTA2 (USA).zip>
build\bin\battlecalc.exe tests\test_ffta2_reach.das --state <сейв FFTA2: Luso рядом с Sasarr> --rom <FFTA2 (USA).zip>
build\bin\battlecalc.exe tests\test_ffta2_status.das --state <сейв FFTA2: Luso рядом с Sasarr> --rom <FFTA2 (USA).zip>
build\bin\battlecalc.exe tests\test_ffta2_explore.das --state <сейв FFTA2: Luso рядом с Sasarr> --rom <FFTA2 (USA).zip>
build\bin\battlecalc.exe tests\test_psp_mem.das --state <fftwotl_test_battle1.ppst> --out <new.ppst>
build\bin\battlecalc.exe tests\test_fftwotl_battle.das --state <fftwotl_test_battle1.ppst> --print 1
build\bin\battlecalc.exe tests\test_fftwotl_attack.das --state <fftwotl_test_battle1.ppst>
build\bin\battlecalc.exe tests\test_fftwotl_forecast.das --state <fftwotl_test_battle1.ppst>
build\bin\battlecalc.exe tests\test_fftwotl_explore.das --state <fftwotl_test_battle1.ppst>
build\bin\battlecalc.exe tests\test_fft_explore.das --state <fft_test_ramza2.State>
build\bin\battlecalc.exe tests\test_fftwotl_export.das --state <fftwotl_test_battle1.ppst> --out <new.ppst>
build\bin\battlecalc.exe tests\test_fftwotl_reach.das --state <fftwotl_test_battle1.ppst>
build\bin\battlecalc.exe tests\test_fftwotl_reach.das --state <fftwotl_test_battle2.ppst> --reach reach2.txt --unit 16
build\bin\battlecalc.exe tests\test_fftwotl_reach.das --state <fftwotl_test_battle1.ppst> --reach reach3.txt
build\bin\battlecalc.exe tests\test_fftwotl_reach.das --state <fftwotl_test_battle2.ppst> --reach reach4.txt --unit 16
build\bin\battlecalc.exe tests\test_fftwotl_battle2.das --state <fftwotl_test_battle2.ppst>
build\bin\battlecalc.exe tests\test_fftwotl_graphics.das --state <fftwotl_test_battle1.ppst> --rom <WotL (USA).iso>
```

### FFT: The War of the Lions (PSP)

`battlecalc --game fftwotl --state <сейв .ppst>`; сейв — save state PPSSPP (`memstick/PSP/PPSSPP_STATE/
ULUS10297_1.00_N.ppst`, в меню PPSSPP это слот N + 1), игра — The War of the Lions (USA, ULUS10297). ISO не нужен:
код игры (BOOT.BIN) уже лежит в памяти сейва, таблицы предметов, способностей, профессий и все имена читаются оттуда.
В поле ROM можно указать ISO игры (`--rom <.iso>`) — только ради графики: спрайты юнитов на поле, иконки предметов в
снаряжении, 3D-модель карты боя (карта находится сама — по её файлу GNS в памяти сейва). В вебе — только `.ppst`.

- **Roster**: юниты боя (у кого сейчас ход — «(turn)»), гости (союзники под управлением ИИ) — зелёным.
- **Inspector**: профессия, основной и второй набор умений, Reaction / Support / Movement (в бою действуют по
  битовым маскам записи — при правке маски пересобираются), уровень, Exp, Brave, Faith, HP / MP / CT, PA / MA /
  Speed (база + снаряжение), 7 слотов снаряжения (список того, что может носить профессия; «All items» — всё),
  статусы, выученные способности по профессиям. **Export state with edits** пишет новый `.ppst` (PPSSPP: File → Load
  State…); RAM в нём — правленая, остальное — как в загруженном сейве.
- **Battle → Field**: карта боя с высотами и водой (из памяти игры; с ISO — текстурированная модель), юниты (с ISO —
  спрайты в палитрах игры), клетки дальности действия с учётом высот (ближний бой ±3 h, копья по прямой, стрелковое
  оружие не ближе 3 клеток, лук дальше сверху: +1 клетка за 2 h; умения — своя клетка, если можно, предел высоты у
  умений с флагом допуска, Throw = Move, Jump; сверено с подсветкой игры в двух боях). Вид — как в игре (зеркально общему полю
  других игр); **View** / Z и C поворачивают вид на 90° (во всех играх).
- **Calculation**: Turn order (тики CT, Haste / Slow / Stop; ход стоит 100 / 80 / 60 CT, у ходящего сейчас 100 уже
  снято), Attack (прогноз урона и шанса по шагам, реакция цели и ответный удар), Explore, Units, Items и Abilities
  (таблицы игры).
- Формулы сверены с прогнозами самой игры (`tests/test_fftwotl_forecast.das`, 291 случай в двух боях: урон и шанс, которые игра показывает при выборе цели): Attack всеми видами
  оружия, зодиак, статусы, уклонения и стороны, элементы, поддержки и реакции (Shirahadori, Parry, Reflexes …),
  Fire, Cure, Arts of War, Umbra, Potion, Rush, Stone, статусная магия (Poison, Stop, Protect, Haste, Quick), Gravity,
  Empowerment / Invigoration, Rend Helm, Aurablast, Throw (лучший по WP предмет нужного вида из запаса партии;
  без него — «none in stock») и Jump (одно действие; выученные Jump задают дальность); Counter — по настоящему удару. Остальное — по
  `research/fftwotl/formulas.md` (не сверено).
- Как это исследовалось (PPSSPP WebSocket-отладчик, зонды): [research/fftwotl/notes.md](../research/fftwotl/notes.md).

### Веб-версия (standalone AOT)

```powershell
web\build.ps1
python -m http.server 8090 --bind 127.0.0.1 --directory build-web\site
```

Открыть http://127.0.0.1:8090/ (опции — в адресе: `?ui-scale=1.6` = `--ui-scale 1.6`; по умолчанию масштаб 1.0, на десктопе — 1.3), внизу справа выбрать сейв `.State` и ROM — файлы обрабатываются в браузере, на
сервер не уходят. Нужны Emscripten 5.0.3 (`C:\src\emsdk`) и Web-сборка dasSDL3 (`C:\src\dasSDL3\build\web`, из неё
берётся только SDL3); пути — параметры `build.ps1`.

Как в dasNES: генератор (wasm32, запускается в Node при сборке, `web/generator.cpp` + `web/standalone.das`)
компилирует `scripts/main_web.das` со всеми модулями и выдаёт C++ (`build-web/aot/battlecalc.das.cpp`); страница
линкуется только с ним, рантаймом daScript, ImGui, SDL3 и нашим нативным кодом — компилятора, интерпретатора и
`.das` в браузере нет (`web/check_standalone.cmake` проверяет map-файл). daScript для wasm собирается в `build-web/`.

| | wasm | data | wasm в gzip |
|---|---:|---:|---:|
| интерпретатор в браузере (демо 06 из dascript_sdl_gui) | 30.0 МБ | 5.6 МБ | 4.4 МБ |
| DasBattleCalc, standalone AOT | 2.4 МБ | 1.0 МБ (шрифт, иконки) | 0.8 МБ |

Чтобы модуль работал в standalone AOT, его функции должны быть в обычном C++-заголовке без daScript (`imgui_ext.h`,
`gba_mem.h`, `gui_common.h`) и модуль должен отдавать его в `aotRequire`. Вспомогательные функции dasImgui вырезаются
из `dasIMGUI.main.cpp` (`web/extract_imgui_helpers.cmake`), объявления, которых нет в его AOT-заголовке, — в
`native/dasimgui_aot_extra.h`.

## Интерфейс

- **Roster** — пути к сейву и ROM, кнопка Load, участники боя (имя, уровень, скорость, CT). **Export state with
  edits** — новый сейв BizHawk с правками (по умолчанию `<сейв>.edited.State` рядом; поверх загруженного не пишет):
  HP, Max HP, MP, база W.Atk…Speed, CT, резерв, снаряжение, статусы, работа, изученные способности, Support / Reaction (если у расы есть
  такая способность — она же помечается изученной), позиция и направление. Evade, Move, Jump берутся из работы —
  их правки не переносятся (сообщение в логе). Открыть в BizHawk: File → Load State → Load Named State. В веб-версии
  файл скачивается.
- **Inspector** — поля выбранного юнита. Форма строится по полям структуры (`scripts/ui/inspector.das`, `daslib/apply`,
  аннотации `@caption`, `@min/@max`, `@readonly`, `@hide`). Редактор: Support и Reaction (списки расы), работа
  (список работ расы юнита — меняет Move,
  Jump, базу Evade и силу без оружия; W.Atk…Speed записи остаются), HP, Max HP, MP, CT, резерв, «Assumed turn» (чем
  юнит закончит свои ходы: Move+Act / Act / Move / Wait). **Stats** — характеристики как на экране Status: база
  (редактируется) + снаряжение = итог. **Equipment** — 5 слотов; клик открывает список снаряжения с фильтром по имени и
  по виду (оружие, щиты, голова, тело, обувь / наручи / кольца), в строке — вид и бонусы. **Status** — галочки
  по битам `+0xE8..+0xED` с именами (Haste, Protect, Berserk…; таблица — `research/notes.md`, «Status bits»),
  изменённый бит помечен «*». **Abilities** — изученные способности (`+0x40 + i`, бит 0x80) по профессиям расы:
  раскрывающийся блок на работу (текущая раскрыта) с числом изученных и галочкой на способность, (R) / (S) / (C) —
  reaction / support / комбо; изученные action-способности появляются в списке Action на вкладке Attack. Выбор
  Support / Reaction помечает способность изученной. Всё пересчитывается сразу
  (порядок ходов, атака, поле); ограничения игры на слоты и работы не проверяются. Изменённое поле получает кнопку
  отката к значению из сейва; «Revert unit» / «Revert all» — откат юнита / всех. Загруженный сейв не меняется
  (правки — в новый файл кнопкой Export). Формулы и таблицы
  ROM — `research/notes.md`.
- **Battle**, две вкладки:
  - **Field** — карта боя в изометрии, как в игре (оттенок и число — высота клетки, синие — вода), юниты кружками
    цвета стороны со стрелкой направления (белый ромб под юнитом — выбранный, оранжевый — цель атаки); оранжевые
    рамки — клетки, которые
    атакующий может ударить (Fight). Колесико — масштаб (точка под курсором остаётся на месте; карта больше панели —
    полосы прокрутки), Fit — снова вписать в панель. Клик — выбрать юнита (он же
    атакующий в Attack), правый клик — цель, перетаскивание — на свободную клетку, Q / E или кнопки — поворот.
    Изменения влияют только на расчёты (сейв не меняется); подсказка на клетке — координаты и высота.
    **View → ROM sprites: on** — вместо кружков спрайты юнитов из ROM (кадр стойки по направлению, палитра из
    сейва), стоящие на своей клетке; **View → ROM icons: on** — иконки предметов из ROM в слотах снаряжения и в
    списке предметов. Обе настройки по умолчанию включены и запоминаются в `local.cfg`;
    `--rom-gfx 0` / `1` выключает / включает обе на один запуск. Форматы — `research/notes.md`, раздел «Graphics».
  - **Screen** — кадр игры, сохранённый в сейве.
  - **Chart** — график последнего эксперимента вкладки Explore: линии, столбики или точки, линейная или
    логарифмическая шкала по каждой оси, легенда, подсказка с точкой под мышью.
- **Calc**, три вкладки:
  - **Turn order** — порядок ходов: таблица с прокруткой (сторона цветом, «+N» тиков от текущего момента, номер хода
    юнита, чем юнит закончит ход; клик выбирает юнита), число ходов вперёд — поле «Turns ahead» (1..200).
  - **Attack** — атакующий, действие (Fight или изученная способность), цель (списком или на поле) и сторона
    (Auto — по позициям и направлению цели, или Front / Side / Back). Урон или лечение (как в прогнозе игры, разброс
    реального удара, крит) с разбивкой A − D/2 и множителя, эффект способности, шанс попадания (показанный игрой и
    реально бросаемый: +10 у не-врагов), шанс крита, средний урон, число ударов до KO, достаёт ли атакующий цель
    (правило игры: высота, тип оружия). Support-способности атакующего и цели (Weapon Atk+, Magic Pow+, Turbo MP,
    Doublehand, Concentrate, Weapon Def+) учитываются. Способности: Battle Tech Soldier проверены по одной,
    остальные читаются из таблиц эффектов ROM — урон и лечение по формулам, ×2 / ×3, урон по MP, Drain,
    оживление, статусы (вредный — шанс по Evade, полезный — без броска), стоимость MP, дальность, площадь (кто в
    неё попадает и сколько получит); особые эффекты (Demi, Death, кражи…) помечены «not modelled». Реакция цели:
    сработает ли (Counter, Strikeback, Reflex, Block Arrows, Bonecrusher, Return Magic…), уворот (шанс 0) и ответный
    удар — урон и шанс. «Real» шанс — с учётом ГСЧ игры (два соседних числа броска связаны; таблица
    `research/roll_table.py`). Модель — `scripts/games/ffta/ffta_attack.das`, формулы — `research/notes.md`
    («Attack», «Fight reach», «Abilities», «Ability effects», «Reactions», «Real hits»).
  - **Explore** — эксперименты: как меняется результат атаки при переборе параметров. Слева — скрипт (список
    готовых примеров, Run или Ctrl+Enter; подсветка синтаксиса: операторы, параметры, метрики, новые столбцы, числа;
    имя, которого нет, — красным; строка с ошибкой — красным фоном), справа — таблица точек (клик по заголовку —
    сортировка; полосу между ними можно перетаскивать; **CSV** — таблица в текущем порядке: на десктопе файл
    `<сейв>.explore.csv` рядом с сейвом, в вебе — скачивание), график — во вкладке Battle → Chart. Сцена — атакующий, цель, действие и сторона вкладки Attack.

### Язык экспериментов (Explore)

Оператор — одна строка (внутри `( )` строку можно переносить), `//` — комментарий. Разбор — грамматика dasPEG
(`scripts/core/explore.das`), вычисление — наше.

```
vary atk.watk 50..300 step 10        // ось: параметр и его значения (точек — произведение осей, до 20000)
vary tgt.wdef 50, 100, 150, 200      // вторая ось
avg = expected                       // вычисляемый столбец
ko = ceil(tgt.hp / max(avg, 0.01))   // параметр, прочитанный формулой, становится столбцом
where reach && avg > 0               // оставить строки
sort avg desc                        // или: sort avg
plot avg, damage by atk.watk per tgt.wdef log y title "Урон"
scene Marc vs Euver with Fire from back   // иначе — как на вкладке Attack
```

- **vary** `путь значения`. Значения: `от..до` или `от..до step шаг` (оба конца включены; `300..100` — вниз),
  список `a, b, c`, генераторы игры: `jobs` (работы расы), `weapons` / `weapons "Sword"`, `supports`, `reactions`,
  `actions` (изученные + Fight), `sides`.
- **Параметры** `atk.*` / `tgt.*` (длинные `attacker.*` / `target.*` значат то же): `watk wdef mpow mres speed evade
  move jump` (база, как в инспекторе; `watk_total` … — с экипировкой, только чтение), `hp max_hp mp ct level`, `job`,
  `weapon`, `support`, `reaction`, `status.<имя>` (0 / 1: `status.protect`, `status.haste` …). Сцены: `action`
  (способность), `side` (1 спереди, 2 сбоку, 3 сзади, 0 — по позициям).
- **Столбцы каждой точки**: оси, `damage dmg_min dmg_max crit_damage hit hit_real crit expected reach mp_cost attack
  defense base evade distance`.
- **имя = выражение** — новый столбец; **where** условие; **sort** выражение `[asc|desc]`.
- **plot** `y1, y2, …` и в любом порядке: `by x` (по умолчанию первая ось), `per серия` (линия / группа на каждое
  значение), `line` / `bar` / `scatter` (по умолчанию line для чисел, bar для подписей), `log x` / `log y` /
  `log xy`, `title "…"`.
- **scene** в любом сочетании: `A vs B` (атакующий и цель по имени), `with Действие` (`with "First Aid"` — имя с
  пробелом в кавычках), `from front|side|back|auto`.
- **Выражения**: числа, `"строки"`, `true / false`, `+ - * / %`, `< <= > >= == !=`, `&& || !`, `a ? b : c`,
  функции `abs min max clamp round floor ceil sqrt pow exp log log10 log2`. Значение — число или подпись с числом
  (работа: имя и id; сравнение и сортировка — по имени).
- Ошибки — с номером строки: синтаксис («near '…'»), неизвестный оператор, столбец (со списком столбцов), функция,
  параметр.

#### Explore в FFTA2

Тот же язык, свои параметры (`scripts/games/ffta2/ffta2_explore.das`); вкладки Calculation → Explore и Battle →
Chart, сцена — с вкладки Attack (атакующий, цель, действие, сторона, привилегия клана).

- **Параметры** `atk.*` / `tgt.*`: `attack defense magick resistance` (база, как в колонке base экрана Unit Info:
  значение записи / 4; `attack_raw` … — само значение записи), `speed`, `evasion move jump` (только чтение),
  `attack_total` … (с экипировкой, только чтение), `hp max_hp mp max_mp ct level`, `job`, `weapon`, `support`,
  `status.<имя>` (0 / 1; имя — как в игре, буквами и цифрами, `↑` / `↓` — `up` / `down`: `status.protect`,
  `status.shell`, `status.defenseup`, `status.speeddown`, `status.oil` …). Сцена: `action` (способность),
  `side` (1 спереди, 2 сбоку, 3 сзади, 0 — по позициям), `privilege` (привилегия клана).
- **Генераторы**: `jobs`, `weapons`, `supports` (851..881 и none), `actions` (Attack и способности с уроном или
  лечением — список вкладки Attack), `sides`.
- **Столбцы каждой точки**: `damage healing dmg_min dmg_max hit hit_real crit expected reach distance mp_cost attack
  defense power base scaled after_side affinity` (`healing` 1 — число в `damage` лечит; `attack defense power` —
  множители формулы / 10; `base scaled after_side` — её промежуточные значения, см. разбивку на вкладке Attack).
- Точка считается пошаговой формулой (`action2`), а способности, которые она не покрывает, — скриптами игры (VM).
  Способность «на себя» (диапазон 8) применяется к атакующему.
- `scene A vs B with Fire from back` — как в FFTA.

#### Explore в FFT: WotL

Параметры — `scripts/games/fftwotl/fftwotl_explore.das`; сцена — с вкладки Attack (атакующий, цель, действие,
сторона).

- **Параметры** `atk.*` / `tgt.*`: `pa ma sp` (текущие, со снаряжением), `pa_raw ma_raw sp_raw` (без него), `brave
  faith hp max_hp mp max_mp ct level`, `move jump c_ev` (только чтение), `job`, `weapon` (правая рука), `support`,
  `zodiac` (0 Aries … 11 Pisces, 12 Serpentarius), `status.<имя>` (0 / 1: `status.protect`, `status.shell`,
  `status.atheist` …). Сцена: `action` (способность, Attack = 0), `side` (1 спереди, 2 сбоку, 3 сзади, 0 — по
  позициям).
- **Генераторы**: `jobs`, `weapons`, `supports`, `actions` (действия наборов умений атакующего), `sides`.
- **Столбцы**: `damage healing dmg_min dmg_max hit crit expected reach distance mp_cost xa ya zodiac_rel`.
- Пример: `vary atk.pa 3..20`, `vary atk.brave 40, 60, 80, 97`, `plot expected by atk.pa per atk.brave`.

#### Explore в FFT (PSX)

Параметры — `scripts/games/fft/fft_explore.das`; сцена — с вкладки Attack (атакующий, цель, выбранное действие).

- **Параметры** `atk.*` / `tgt.*`: `pa ma sp` (как в записи, со снаряжением), `brave faith hp max_hp mp max_mp ct
  level move jump`, `zodiac`, `weapon` (правая рука; бонусы предмета пересчитываются, как в редакторе), `support`,
  `status.<имя>`, `job` (только чтение: множители PA / MA профессии не моделируются). Сцена: `action`, `side`.
- **Генераторы**: `weapons`, `supports`, `actions` (Attack и способности наборов атакующего; все Jump — одно
  действие), `sides` (цель разворачивается к атакующему передом, боком или спиной).
- **Столбцы** — как в WotL. Проверка на `fft_test_ramza2`: стороны 66 / 74 / 100%, зодиак 35 / 49 / 21, Dagger 18,
  Defender 48, Attack UP 56, Protect 28, Fire 17 при 95% — числа игры.

## Как устроено

```
native/            хост (C++): daScript + dasSDL3 + dasImgui + наши модули
  runner.cpp         запуск scripts/main.das
  gui_common.*       шрифт, примитивы, аргументы, скриптовый ввод, скриншоты
  module_imgui_ext   стиль Blendish на ImGui, лист иконок
  gba_mem.*          BizHawk .State (zip + zstd -> RAM mGBA), ROM, чтение памяти GBA, кадр из сейва; запись нового
                     .State с изменённой RAM (кадр zstd из несжатых блоков — компрессор не нужен)
  third_party/       stb_truetype, miniz (zip), zstddeclib (zstd 1.5.6)
scripts/
  main.das           десктопный вход
  app/shell.das      меню, док-панели, статус; панели заполняет игра
  core/game.das      интерфейс GameModule, лог
  core/gba_struct    чтение структур из памяти GBA по аннотациям @offset (daslib/apply)
  core/result_try    макросы try_ok / ensure: выход из функции с первой ошибкой ("" = успех)
  core/explore       язык экспериментов: грамматика dasPEG, выражения, таблица, шаги, данные графика
  ui/                bl_imgui (виджеты Blendish), bnd_const, inspector
  games/ffta/        ffta_battle.das (RAM -> юниты, модель порядка ходов), ffta.das (панели), ffta_explore.das
                     (параметры, значения осей и метрики экспериментов), ffta_gfx.das (спрайты и иконки из ROM;
                     распаковка и текстуры — native/gba_gfx.cpp)
  games/ffta2/       FFTA2: ffta2_battle / _attack / _vm / _forecast / _turns (модель), ffta2.das (панели),
                     ffta2_explore.das (Explore)
  games/fftwotl/     FFT: WotL: fftwotl_data (таблицы и тексты из RAM), _battle (юниты, карта, экспорт), _attack
                     (прогноз, реакции), _turns, _explore, fftwotl.das (панели); сейв PPSSPP — native/psp_mem.cpp
  games/fft/         FFT (PSX): fft_battle (юниты, карта, тексты, редактор, экспорт), _attack, _abilities,
                     _reactions, _reach, _turns, _map, _explore, fft.das (панели); сейв BizHawk — native/psx_mem.cpp
  ui/explore_view    таблица (сортировка, только видимые строки) и график (линии, столбики, точки, лог-шкалы)
research/          исследование FFTA: notes.md (результаты), Lua-скрипты BizHawk, дизассемблер Thumb, симулятор
tests/             тесты на daslang
assets/            шрифт DejaVu Sans, иконки (свой пиксель-арт, `icons/make_icons.py`)
```

Механика порядка ходов FFTA (адреса, формулы, проверка) — в [research/notes.md](../research/notes.md).

## Лицензии сторонних файлов

- DejaVu Sans — свободная лицензия шрифтов DejaVu (`assets/fonts/LICENSE-DejaVuSans.ttf.txt`).
- Иконки (`assets/icons/ffta_icons16.png`) — свои, нарисованы скриптом `assets/icons/make_icons.py` (16 × 16, в духе
  меню FFTA); константы — `scripts/ui/icons.das`. Новую иконку — добавить рисунок в `ICONS` скрипта, запустить его и
  перенести напечатанные строки в `icons.das`; `ffta_icons_preview.png` — увеличенный просмотр.
- miniz — public domain / unlicense; zstd — BSD (`native/third_party/LICENSE-zstd.txt`); stb_truetype — public domain / MIT.
- ROM и сейвы в репозиторий не входят.
