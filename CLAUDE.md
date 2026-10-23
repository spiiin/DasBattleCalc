# DasBattleCalc — контекст проекта для Claude

Калькулятор / симулятор боёв тактических игр (первая — FFTA, GBA USA). daslang + dasSDL3 + Dear ImGui в стиле
Blender 2.7 (Blendish). Общение с пользователем — на русском.

## Сборка, запуск, проверка

- `build.bat` (VS 2022 x64 + Ninja) -> `build\bin\battlecalc.exe [script.das] [опции]`; по умолчанию `scripts/main.das`.
- Картинку проверяем `--shot file.png`, ввод — `--script "F click X Y; F shot file.png"` (см. `native/gui_common.cpp`).
- Тест модели FFTA: `battlecalc tests\test_ffta_turn_order.das --state <QuickSave1.State> --rom <FFTA.zip>`;
  характеристики и снаряжение — `tests\test_ffta_stats.das`, атака — `tests/test_ffta_attack.das`, дальность — `tests/test_ffta_reach.das`, способности — `tests/test_ffta_abilities.das`, магия — `tests/test_ffta_magic.das`, реакции — `tests/test_ffta_reactions.das`, экспорт сейва — `tests/test_ffta_export.das`, Explore — `tests/test_ffta_explore.das` и `tests/test_explore.das` (язык, без сейва) (+ `--out <new.State>`; проверка
  в эмуляторе — `research/export_check.lua`, `PROBE_STATE`)
  (те же аргументы; прогнозы игры для сверки — `research/attack_probe.lua`). Экраны Status юнитов для сверки —
  `research/status_copy.lua` (запись юнита копируется в запись Marc, затем открывается Status).
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
