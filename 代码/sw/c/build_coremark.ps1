#=============================================================================
#  build_coremark.ps1 : 编译 CoreMark 裸机镜像 -> imem.hex / dmem.hex
#  用法: .\build_coremark.ps1 [-Iterations 1] [-Out ..\..\sim\work]
#=============================================================================
param(
    [int]$Iterations = 1,
    [string]$Out = "..\..\sim\work",
    [int]$DataSize = 2000
)

$ErrorActionPreference = 'Continue'
$tcRoot  = "$env:TEMP\riscv_tc\xpack-riscv-none-elf-gcc-14.2.0-3\bin"
$gcc     = Join-Path $tcRoot 'riscv-none-elf-gcc.exe'
$objcopy = Join-Path $tcRoot 'riscv-none-elf-objcopy.exe'
$objdump = Join-Path $tcRoot 'riscv-none-elf-objdump.exe'
$py      = 'C:\Users\25924\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'

if (-not (Test-Path $gcc)) { Write-Host "toolchain not found" -ForegroundColor Red; exit 1 }

Push-Location $PSScriptRoot

$srcs = @('crt0.S', 'uart.c',
          'coremark/core_list_join.c', 'coremark/core_main.c',
          'coremark/core_matrix.c', 'coremark/core_state.c',
          'coremark/core_util.c', 'coremark/core_portme.c',
          'coremark/ee_printf.c')

$defs = @("-DITERATIONS=$Iterations", '-DPERFORMANCE_RUN=1',
          "-DTOTAL_DATA_SIZE=$DataSize", '-DFLAGS_STR="-O2 rv32im"')

$cflags = @('-march=rv32im_zicsr', '-mabi=ilp32', '-O2', '-g',
            '-nostdlib', '-nostartfiles', '-ffreestanding', '-fno-builtin',
            '-fno-common', '-I', 'coremark', '-Wl,--gc-sections', '-T', 'link.ld',
            '-o', 'coremark.elf') + $defs + $srcs

Write-Host "[coremark] building (ITERATIONS=$Iterations, DATA=$DataSize) ..." -ForegroundColor Cyan
& $gcc @cflags 2>&1 | ForEach-Object { Write-Host "  $_" }
if ($LASTEXITCODE -ne 0) { Write-Host "[coremark] build FAILED" -ForegroundColor Red; Pop-Location; exit 1 }

& $objcopy -O ihex coremark.elf coremark.hex
& $objdump -d coremark.elf > coremark.lst

& $py (Join-Path $PSScriptRoot '..\tools\hexsplit.py') coremark.hex -o $Out
if ($LASTEXITCODE -ne 0) { Write-Host "[coremark] hexsplit FAILED" -ForegroundColor Red; Pop-Location; exit 1 }

Write-Host "[coremark] done -> $Out" -ForegroundColor Green
Pop-Location
