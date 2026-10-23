# Web build (standalone AOT) into build-web\site. Needs Emscripten 5.0.3 and
# a dasSDL3 Web build (SDL3 wasm) - see web/README.md.
param(
    [string]$EmSdk = 'C:\src\emsdk',
    [string]$DasSDL3 = 'C:\src\dasSDL3-localdas',   # its daScript is built for wasm
    [string]$SdlWeb = 'C:\src\dasSDL3\build\web',   # a dasSDL3 Web build: only its SDL3 wasm is used
    [string]$Md4c = 'C:\Users\sanya\Documents\Codex\2026-09-19\cj\work\imgui-deps\md4c-release-0.5.3\src',
    [int]$Jobs = 8
)
$ErrorActionPreference = 'Stop'
# native tools write progress to stderr: their exit codes are checked instead
$root = Split-Path $PSScriptRoot -Parent
$dependency = $SdlWeb
$cache = Get-Content -LiteralPath (Join-Path $dependency 'CMakeCache.txt')
$ninja = (($cache | Where-Object { $_ -match '^CMAKE_MAKE_PROGRAM:' }) -split '=', 2)[1]
if (!$ninja -or !(Test-Path -LiteralPath $ninja)) { $ninja = 'C:\msvs17.8\2022\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe' }
$previous = @{}
Get-ChildItem Env: | ForEach-Object { $previous[$_.Name] = $_.Value }
try {
    $activation = Join-Path $EmSdk 'emsdk_env.bat'
    $env:EMSDK_QUIET = "1"
    & cmd.exe /d /s /c "`"call `"$activation`" >nul 2>nul && set`"" | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
    }
    if ($LASTEXITCODE -ne 0) { throw 'Cannot activate Emscripten' }
    $ErrorActionPreference = 'Continue'
    $node = (Get-ChildItem -LiteralPath (Join-Path $EmSdk 'node') -Directory | ForEach-Object { Join-Path $_.FullName 'node.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
    $build = Join-Path $root 'build-web'
    & (Join-Path $EmSdk 'upstream\emscripten\emcmake.bat') cmake -S $PSScriptRoot -B $build -G Ninja -DCMAKE_BUILD_TYPE=Release `
        "-DCMAKE_MAKE_PROGRAM=$ninja" "-DDASSDL3_DIR=$($DasSDL3 -replace '\\','/')" "-DDASSDL3_WEB=$($SdlWeb -replace '\\','/')" `
        "-DNODE_EXECUTABLE=$node" "-DMD4C_DIR=$Md4c"
    if ($LASTEXITCODE -ne 0) { throw 'Web configure failed' }
    cmake --build $build --parallel $Jobs
    if ($LASTEXITCODE -ne 0) { throw 'Web build failed' }
    Write-Output "Built $build\site. Serve: python -m http.server 8090 --bind 127.0.0.1 --directory `"$build\site`""
} finally {
    Get-ChildItem Env: | Where-Object { !$previous.ContainsKey($_.Name) } | ForEach-Object { [Environment]::SetEnvironmentVariable($_.Name, $null, 'Process') }
    foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
}
