# DasBattleCalc — контекст проекта для Claude

Калькулятор / симулятор боёв тактических игр (первая — FFTA, GBA USA). daslang + dasSDL3 + Dear ImGui в стиле
Blender 2.7 (Blendish). Общение с пользователем — на русском.

## Сборка, запуск, проверка

- `build.bat` (VS 2022 x64 + Ninja) -> `build\bin\battlecalc.exe [script.das] [опции]`; по умолчанию `scripts/main.das`.
- Картинку проверяем `--shot file.png`, ввод — `--script "F click X Y; F drop PATH; F shot file.png"` (см. `native/gui_common.cpp`;
  `drop` — файл, перетащенный в окно). Кнопки «...» у полей State / ROM / Export — системный диалог SDL3
  (`gui_file_dialog`, только десктоп), перетаскивание — `gui_take_dropped`; разбор — `scripts/ui/roster.das`.
- Тест модели FFTA: `battlecalc tests\test_ffta_turn_order.das --state <ffta_test_battle1.State> --rom <FFTA.zip>`
  (сейвы-копии — в `CLAUDE.local.md`; слоты QuickSave пользователь перезаписывает); второй бой —
  `tests/test_ffta_battle2.das --state <ffta_test_battle2.State> --start <ffta_test_battle2_start.State>`;
  характеристики и снаряжение — `tests\test_ffta_stats.das`, атака — `tests/test_ffta_attack.das`, дальность — `tests/test_ffta_reach.das`, способности — `tests/test_ffta_abilities.das`, магия — `tests/test_ffta_magic.das`, реакции — `tests/test_ffta_reactions.das`, экспорт сейва — `tests/test_ffta_export.das`, Explore — `tests/test_ffta_explore.das` и `tests/test_explore.das` (язык, без сейва) (+ `--out <new.State>`; проверка
  в эмуляторе — `research/export_check.lua`, `PROBE_STATE`)
  (те же аргументы; прогнозы игры для сверки — `research/attack_probe.lua`). Экраны Status юнитов для сверки —
  `research/status_copy.lua` (запись юнита копируется в запись Marc, затем открывается Status).
- FFTA2 (NDS): `battlecalc --game ffta2 --state <ffta2_test_battle1.State> --rom <FFTA2.zip>`; тесты
  `tests/test_nds_mem.das` (чтение RAM melonDS и файлов ROM), `tests/test_ffta2_battle.das` (юниты, экраны Unit Info, карта высот — `research/ffta2/heights1.txt`),
  `tests/test_ffta2_attack.das` (175 прогнозов Attack игры, формула переведена из скриптов VM; 200 настоящих ударов, предсказанных по сидам генераторов),
  `tests/test_ffta2_abilities.das` (236 способностей по прогнозам игры; данные — `research/ffta2/abil1.txt`),
  `tests/test_ffta2_turns.das` (17 ходов из игры: порядок, CT, тики),
  `tests/test_ffta2_reach.das` (91 списков досягаемости игры: высоты, оружие, заклинания; `research/ffta2/reach1.txt`),
  `tests/test_ffta2_export.das` (запись сейва: правки юнитов -> новый .State -> чтение обратно; `--out <new.State>`, `--forecast N` — прогноз игры по нему из `vary_probe.lua`),
  `tests/test_ffta2_reaction.das` (реакции цели: срабатывание по правилу игры 0x020636DC, ответный удар; `research/ffta2/reaction1.txt`),
  `tests/test_ffta2_status.das` (70 прогнозов статусных способностей игры через VM; данные — `research/ffta2/status4.txt`, сейв `ffta2_test_attack.State`),
  `tests/test_ffta2_explore.das` (Explore FFTA2, `ffta2_explore.das`: точки = action2 после той же правки, примеры
  вкладки; сейв, где Luso стоит рядом с Sasarr — `ffta2_test_attack.State`),
  `tests/test_ffta2_vm.das` (все 245 — интерпретатором VM игры: `ffta2_vm.das` исполняет её скрипты из ROM, `ffta2_forecast.das` — нативные вызовы). Пробы FFTA2: `research/ffta2/plan_probe.lua` (план ввода,
  скриншоты, дампы, лог записей / исполнения), `vary_probe.lua` (прогноз при правках RAM), `exec_probe.lua` (настоящие удары с заданными сидами), `arm.py` (дизассемблер ARM), `vmdis.py` / `vmdec.py` (скрипты VM), `natives.py` (нативные вызовы).
- FFT (PSX, USA): `battlecalc --game fft --state <BizHawk Nymashock .State> [--rom <FFT (USA).cue>]` — RAM из сейва
  (`native/psx_mem.cpp`), диск только для графики (спрайты, иконки, текстурированный меш карты на поле —
  `fft_map.das`). Тесты: `tests/test_psx_mem.das` (`--state <fft_test_battle1.State> [--out <new.State>]`),
  `tests/test_fft_battle.das` (то же), `tests/test_fft_turns.das` (`fft_test_battle1b.State`: 9 ходов из игры;
  `--charge fft_test_charge.State` — заряд Fire, `--haste fft_test_haste.State` — Haste / Slow),
  `tests/test_fft_attack.das` (`fft_test_ramza2.State [--battle2 fft_test_battle2.State]`: прогнозы Attack игры — урон, стороны, зодиак; второй бой — Barney по Candy),
  `tests/test_fft_graphics.das` (`fft_test_battle1.State --rom <.cue>`), `tests/test_fft_reach.das` (`--dir <PSX/State>`:
  12 сейвов `fft_reach_*.State` с открытыми зонами Move / Attack — флаги игры в терраине +5),
  `tests/test_fft_abilities.das` (`fft_test_ramza2.State [--throw fft_test_throw.State] [--battle2 fft_test_battle2.State]`: прогнозы способностей игры,
  Jump, Throw; формулы — `fft_abilities.das`), `tests/test_fft_explore.das` (`fft_test_ramza2.State`: Explore —
  стороны, зодиак, оружие, Attack UP, Protect, Fire дают числа игры). Второй бой (Гариленд) — `fft_test_battle2.State`.
  Экспорт сейва с правками — `export_battle` (характеристики, без позиции), тест `tests/test_fft_export.das`
  (`--state <fft_test_ramza2.State> --out <new.State>`). Пробы и форматы — `research/fft/`
  (`plan_probe.lua`, `ct_probe.lua`, `psx.py`, `notes.md`). В US-версии ○ подтверждает, × отменяет.
- FFT: The War of the Lions (PSP, ULUS10297): `battlecalc --game fftwotl --state <fftwotl_test_battle1.ppst>` — сейв
  PPSSPP (`native/psp_mem.cpp`: заголовок 0xB0, тело zstd, RAM 32 МБ из секции Memory; запись — несжатые блоки zstd).
  ISO не нужен: BOOT.BIN лежит в RAM (RAM = смещение + 0x08803FAC), таблицы и тексты читаются оттуда
  (ISO в поле ROM, ключ `wotl_iso`, — только графика: `psx_open_disc` читает и .iso, `psp_pack_file` — файлы
  fftpack.bin, `psp_unit_sprite` / `psp_item_icon` в `gba_gfx.cpp`, карта — `fftwotl_map.das`, карта боя ищется по GNS
  в RAM — `psp_find_map`; тест `tests/test_fftwotl_graphics.das --state <ppst> --rom <iso>`; форматы —
  `research/fftwotl/graphics.md`)
  (`fftwotl_data.das`; раскладки — `research/fftwotl/layouts.md`). Юниты — `fftwotl_battle.das` (21 запись по 0x1E8 с
  0x092E5CB4), формулы — `fftwotl_attack.das` по `research/fftwotl/formulas.md` (сверены с прогнозами игры:
  `tests/test_fftwotl_forecast.das`, данные `research/fftwotl/forecast1..9.txt` от `fcvary.py [--magic|--supports|--reactions]`, `fcyside.py`, `fctj.py [--throw|--jump]`, `fcgroups.py [--status]`
  и `fcgroups.py`; зонды управляют PPSSPP только через отладчик, окно свёрнуто), реакции — `reaction_w`, ходы —
  `fftwotl_turns.das`, Explore — `fftwotl_explore.das`. Тесты: `tests/test_psp_mem.das` (`--out`), `test_fftwotl_battle.das`
  (`--print 1`), `test_fftwotl_attack.das`, `test_fftwotl_explore.das` (+ порядок ходов), `test_fftwotl_export.das`.
  Пробы: PPSSPP WebSocket-отладчик (`research/fftwotl/pprun.py`, `ppdbg.py`, `mips.py`; заметки — `research/fftwotl/notes.md`).
  Общие части игр: `scripts/ui/battle_field.das` (изометрическое поле: `FieldMap`, `FieldUnit`, ввод — `FieldInput`),
  `scripts/ui/roster.das`, `scripts/ui/inspector.das`, `scripts/core/teams.das`, `scripts/core/config.das` (local.cfg:
  у FFTA ключи `state` / `rom`, у FFTA2 `ffta2_state` / `ffta2_rom`, у FFT `fft_state` / `fft_rom`, у WotL `wotl_state`). Игры делят один загруженный ROM и сейв:
  `GameModule.activate()` перезагружает свои файлы при переключении, веб — `shell_reload()` по коду ROM.
- Пути этой машины (ROM, BizHawk, тестовый сейв) — в `CLAUDE.local.md` (не в репозитории).
- daScript — локальная ветка (master + `fix-annotation-hex`), через worktree dasSDL3 `C:\src\dasSDL3-localdas`
  (параметр `DASSDL3_DIR` у `build.bat` и `web/build.ps1`); как он устроен — в `CLAUDE.local.md`.

- Веб: `web\build.ps1` (standalone AOT, см. README); новый нативный модуль = реализация в .cpp/.h без daScript +
  привязки с `aotRequire`, иначе генератор упадёт (`fail_on_lack_of_aot_export`) или страница не слинкуется.
  SDL `FILL_DOCUMENT` прячет остальные элементы страницы — `web/app.js` возвращает свою панель.
  Генератор (`web/generator.cpp`): `keep_symbol_tables` (иначе индексы глобальных освобождаются после simulate) и
  отдельные `ModuleGroup` для программы и эмиттера (иначе в C++ попадает код компилятора).

## daslang: грабли этого проекта

- **Куча скрипта.** По умолчанию она линейная и не освобождается, а UI каждый кадр строит строки и массивы (~145 КБ
  за кадр): веб падал через пару минут (`out of heap memory`, затем `memory access out of bounds` — «зависание»).
  Поэтому `scripts/main.das` и `scripts/main_web.das` объявляют `options persistent_heap` + `options gc`, и куча
  собирается между кадрами, когда в ней больше 16 МБ: на десктопе — `collect_frame_garbage()` в цикле, в вебе —
  `collectHeap` в `web/runner.cpp` после `app_frame`. В консоли страницы: `runtime._web_heap_bytes()`.

- `require` подпапок: из `scripts/main.das` — `require app/shell`; между подпапками — `require ../ui/bl_imgui.das`
  (с `.das`); корни FsFileAccess плоские (`root/имя.das`), подпапки в них не работают.
- Зарезервированы: `label`, `addr` (аннотация подписи поля — `@caption`), `expect`, `range`.
- **dasPEG** (язык Explore, `scripts/core/explore.das`): модуль `peg` daScript помечен `no_aot` — для веба нужна
  локальная правка (см. `CLAUDE.local.md`); корни модулей `peg` / `detail` — в `native/runner.cpp` и
  `web/generator.cpp`. Все правила грамматики возвращают ОДИН тип (`PNode?`): кэши правил разных типов дают
  обобщённые экземпляры с одним именем (internal error 50609 в интерпретаторе, «no matching function» в AOT C++).
  Действия правил без побочных эффектов (PEG откатывается). Парсер рекурсивный — программам нужен
  `options stack = 1000000` (main.das, main_web.das, тесты Explore). Позиций в действиях нет: скрипт делится на
  операторы до разбора (`split_statements`), номер строки — от начала оператора.
- Параметр `var s : string` — локальная копия; вернуть строку через параметр — `var s : string&`.
- Цепочка «"" или текст ошибки» — макросы `scripts/core/result_try.das`: `try_ok(call, "Префикс: ")` и
  `ensure(cond, msg)` возвращают из функции (`: string`) первую ошибку; пример — `FftaGame.load_files`, тест —
  `tests/test_result_try.das` (без аргументов). В веб попадает только раскрытый код.
- Шестнадцатеричные литералы — uint; `let x & = arr[i]` требует `unsafe(...)`. Без unsafe — `with_(arr[i]) $(x) { ... }`
  из `daslib/with_boost` (блокирует массив на время блока), но в нашей версии daScript только для ЛОКАЛЬНОГО массива:
  с аргументом функции или полем класса макрос даёт error 31019 — там индексировать напрямую или копировать элемент.
- Структуры памяти игры описываем `struct` + `@offset = 0xD0` (hex приходит как `tUInt64`) и читаем `read_struct`
  (apply), а не ручными `gba_read*`.
- `T(a = .., b = ..)` с именованными аргументами — всегда литерал структуры `T`, одноимённая функция `def T(..)` не
  вызывается: фабрики называть иначе (`turn_columns`).
- `$Result` в daScript master — вариант `{ err; ok }` (`is err`, `as ok`), не кортеж; функции с `sdl_try` должны
  объявлять тип результата (`: SdlStatus`).
- Список с прокруткой: `BeginChild(id, size, ImGuiChildFlags.None, ImGuiWindowFlags.None)`, строки — абсолютными
  координатами от `GetCursorScreenPos()` (уже учитывает прокрутку) + `InvisibleButton` на строку.

## Исследование игры

`research/`: BizHawk запускается из скрипта (`EmuHawk.exe --lua=... rom.zip`), Lua пишет лог / скриншоты и закрывает
эмулятор; `thumb.py` — дизассемблер Thumb; `turnsim.py` — модель на Python и сверка с логом. Результаты — в
`research/notes.md`; любое новое правило сначала проверять по игре, потом переносить в `ffta_battle.das`.
