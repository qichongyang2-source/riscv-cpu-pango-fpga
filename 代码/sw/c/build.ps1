#=============================================================================
#  build.ps1 : 裸机 C 程序编译（RISC-V GCC）-> imem.hex / dmem.hex
#  用法: .\build.ps1 -Src bench.c [-Out ..\..\sim\work]
#=============================================================================
param(
    [string]$Src = "bench.c",
    [string]$Out = "..\..\sim\work",
    [string]$Extra = ""
)

$ErrorActionPreference = 'Continue'
$tcRoot = "$env:TEMP\riscv_tc\xpack-riscv-none-elf-gcc-14.2.0-3\bin"
$gcc     = Join-Path $tcRoot 'riscv-none-elf-gcc.exe'
$objcopy = Join-Path $tcRoot 'riscv-none-elf-objcopy.exe'
$objdump = Join-Path $tcRoot 'riscv-none-elf-objdump.exe'
$py      = 'C:\Users\25924\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'

if (-not (Test-Path $gcc)) {
    Write-Host "toolchain not found: $gcc" -ForegroundColor Red
    exit 1
}

Push-Location $PSScriptRoot

$sources = @('crt0.S', 'uart.c', $Src)
$cflags  = @(
    '-march=rv32im_zicsr', '-mabi=ilp32', '-O2', '-g',
    '-nostdlib', '-nostartfiles', '-ffreestanding', '-fno-builtin',
    '-fno-common', '-Wl,--gc-sections', '-T', 'link.ld',
    '-o', 'app.elf'
) + $sources
if ($Extra -ne "") { $cflags = $Extra.Split(' ') + $cflags }

Write-Host "[build] $Src ..." -ForegroundColor Cyan
& $gcc @cflags 2>&1 | ForEach-Object { Write-Host "  $_" }
if ($LASTEXITCODE -ne 0) { Write-Host "[build] compile/link FAILED" -ForegroundColor Red; Pop-Location; exit 1 }

& $objcopy -O ihex app.elf app.hex
if ($LASTEXITCODE -ne 0) { Write-Host "[build] objcopy FAILED" -ForegroundColor Red; Pop-Location; exit 1 }

& $objdump -d app.elf > app.lst

& $py (Join-Path $PSScriptRoot '..\tools\hexsplit.py') app.hex -o $Out
if ($LASTEXITCODE -ne 0) { Write-Host "[build] hexsplit FAILED" -ForegroundColor Red; Pop-Location; exit 1 }

Write-Host "[build] done -> $Out" -ForegroundColor Green
Pop-Location
