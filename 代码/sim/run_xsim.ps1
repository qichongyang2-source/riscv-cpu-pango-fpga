#=============================================================================
#  run_xsim.ps1 : Vivado xsim 交叉验证流程
#  用法: .\run_xsim.ps1 -Test t01_alu -Max 20000
#=============================================================================
param(
    [string]$Test = "t00_smoke",
    [int]$Max = 200000,
    [switch]$Rebuild
)

$ErrorActionPreference = 'Continue'
$root    = Split-Path -Parent $PSScriptRoot
$work    = Join-Path $root 'sim\work'
$py      = 'C:\Users\25924\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
$vivado  = 'F:\vivado\Vivado\2023.1'

if (-not (Test-Path $work)) { New-Item -ItemType Directory -Force -Path $work | Out-Null }

# 汇编
& $py (Join-Path $root 'sw\tools\rvasm.py') (Join-Path $root "sw\tests\$Test.s") -o $work | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "[asm] FAILED" -ForegroundColor Red; exit 1 }

Push-Location $work

$src = @()
$src += (Get-ChildItem (Join-Path $root 'rtl\core')   -Filter *.v).FullName
$src += (Get-ChildItem (Join-Path $root 'rtl\mem')    -Filter *.v).FullName
$src += (Get-ChildItem (Join-Path $root 'rtl\periph') -Filter *.v).FullName
$src += (Get-ChildItem (Join-Path $root 'rtl\ai')     -Filter *.v).FullName
$src += (Get-ChildItem (Join-Path $root 'rtl\soc')    -Filter *.v).FullName
$src += (Get-ChildItem (Join-Path $root 'tb')         -Filter *.v).FullName

$setup = "call `"$vivado\settings64.bat`" >nul 2>&1"

if ($Rebuild -or -not (Test-Path 'xsim.dir')) {
    if (Test-Path 'xsim.dir') { Remove-Item -Recurse -Force 'xsim.dir' }
    Write-Host "[xsim] xvlog ..." -ForegroundColor Cyan
    $cmd = "$setup && xvlog -d SIM_INIT -i `"$root\rtl\core`" -work xil_defaultlib $($src -join ' ')"
    cmd /c $cmd 2>&1 | ForEach-Object { if ($_ -match 'ERROR|CRITICAL') { Write-Host "  $_" -ForegroundColor Red } }
    if ($LASTEXITCODE -ne 0) { Write-Host "[xsim] xvlog FAILED" -ForegroundColor Red; Pop-Location; exit 1 }

    Write-Host "[xsim] xelab ..." -ForegroundColor Cyan
    $cmd = "$setup && xelab -debug typical -timescale 1ns/1ps -L xil_defaultlib xil_defaultlib.tb_soc -s tb_soc_sim"
    cmd /c $cmd 2>&1 | ForEach-Object { if ($_ -match 'ERROR|CRITICAL') { Write-Host "  $_" -ForegroundColor Red } }
    if ($LASTEXITCODE -ne 0) { Write-Host "[xsim] xelab FAILED" -ForegroundColor Red; Pop-Location; exit 1 }
}

Write-Host "[xsim] run $Test ..." -ForegroundColor Cyan
$cmd = "$setup && xsim tb_soc_sim --runall --nolog"
$out = cmd /c $cmd 2>&1 | Out-String
Pop-Location

if ($out -match 'TEST PASSED') {
    Write-Host "PASS: $Test" -ForegroundColor Green
    exit 0
} elseif ($out -match 'TEST FAILED') {
    Write-Host "FAIL: $Test" -ForegroundColor Red
    Write-Host $out
    exit 1
} else {
    Write-Host "NO RESULT: $Test" -ForegroundColor Red
    Write-Host $out
    exit 2
}
