@echo off
rem Configure + build the desktop host with Ninja in a VS x64 developer environment.
rem DASSDL3_DIR - the dasSDL3 checkout with a Release build in build\ninja. Default:
rem the worktree on a local daScript branch (parser fixes not yet in dasSDL3).
cd /d "%~dp0"
if not defined DASSDL3_DIR set DASSDL3_DIR=C:/src/dasSDL3-localdas
call "C:\msvs17.8\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DDASSDL3_DIR=%DASSDL3_DIR% || exit /b 1
cmake --build build --parallel 8
