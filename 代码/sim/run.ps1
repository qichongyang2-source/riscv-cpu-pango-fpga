#=============================================================================
#  run.ps1 : 一键汇编 + 编译 + 仿真
#  用法:
#     .\run.ps1                      # 跑全部 sw\tests\*.s
#     .\run.ps1 -Test t03_mem        # 跑单个
#     .\run.ps1 -Rebuild -Trace      # 强制重编译并打印提交轨迹
#=============================================================================
param(
    [string]$Test = "",
    [int]$Max = 200000,
    [switch]$Rebuild,
    [switch]$Trace,
    [switch]$ExTrace,
    [switch]$WbTrace,
    [switch]$Vcd
)

$ErrorActionPreference = 'Continue'
$root   = Split-Path -Parent $PSScriptRoot
$work   = Join-Path $root 'sim\work'
$python = 'C:\Users\25924\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
$iverilog = 'C:\iverilog\bin\iverilog.exe'
$vvp      = 'C:\iverilog\bin\vvp.exe'

if (-not (Test-Path $work)) { New-Item -ItemType Directory -Force -Path $work | Out-Null }

#--------------------------- 1. 编译 RTL -------------------------------------
$vvpFile = Join-Path $work 'sim.vvp'
$needBuild = $Rebuild -or (-not (Test-Path $vvpFile))
if (-not $needBuild) {
    $rtlTime = Get-ChildItem -Path (Join-Path $root 'rtl'), (Join-Path $root 'tb') -Recurse -Include *.v,*.vh |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($rtlTime.LastWriteTime -gt (Get-Item $vvpFile).LastWriteTime) { $needBuild = $true }
}

if ($needBuild) {
    Write-Host "[build] compiling RTL ..." -ForegroundColor Cyan
    $src = @()
    $src += (Get-ChildItem (Join-Path $root 'rtl\core')   -Filter *.v).FullName
    $src += (Get-ChildItem (Join-Path $root 'rtl\mem')    -Filter *.v).FullName
    $src += (Get-ChildItem (Join-Path $root 'rtl\periph') -Filter *.v).FullName
$src += (Get-ChildItem (Join-Path $root 'rtl\ai')     -Filter *.v).FullName
    $src += (Get-ChildItem (Join-Path $root 'rtl\soc')    -Filter *.v).FullName
    $src += (Get-ChildItem (Join-Path $root 'tb')         -Filter *.v).FullName
    & $iverilog -g2012 -DSIM_INIT -I (Join-Path $root 'rtl\core') -s tb_soc -o $vvpFile @src 2>&1 |
        ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    if ($LASTEXITCODE -ne 0) { Write-Host "[build] FAILED" -ForegroundColor Red; exit 1 }
    Write-Host "[build] ok" -ForegroundColor Green
}

#--------------------------- 2. 选择测试 -------------------------------------
$testsDir = Join-Path $root 'sw\tests'
$tests = if ($Test -ne "") {
    Get-ChildItem $testsDir -Filter "$Test*.s" | Sort-Object Name
} else {
    Get-ChildItem $testsDir -Filter '*.s' | Sort-Object Name
}
if ($tests.Count -eq 0) { Write-Host "no test matched '$Test'" -ForegroundColor Red; exit 1 }

#--------------------------- 3. 逐个仿真 -------------------------------------
$results = @()
Push-Location $work
foreach ($t in $tests) {
    $name = $t.BaseName
    & $python (Join-Path $root 'sw\tools\rvasm.py') $t.FullName -o $work | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $results += [pscustomobject]@{ Test = $name; Result = 'ASM-ERROR'; Cycles = ''; Commits = ''; IPC = ''; Code = '' }
        continue
    }

    $args = @('sim.vvp', "+MAX=$Max")
    if ($Trace)   { $args += '+TRACE' }
    if ($ExTrace) { $args += '+EXTRACE' }
    if ($WbTrace) { $args += '+WBTRACE' }
    if ($Vcd)     { $args += '+VCD' }

    $out = & $vvp @args 2>&1 | Out-String
    if ($out -match 'TEST PASSED') {
        $cyc = [regex]::Match($out, 'cycles=(\d+)').Groups[1].Value
        $cm  = [regex]::Match($out, 'commits=(\d+)').Groups[1].Value
        $ipc = if ([double]$cyc -gt 0) { [math]::Round([double]$cm / [double]$cyc, 2) } else { 0 }
        $results += [pscustomobject]@{ Test = $name; Result = 'PASS'; Cycles = $cyc; Commits = $cm; IPC = $ipc; Code = '' }
    } elseif ($out -match 'TEST FAILED') {
        $code = [regex]::Match($out, 'code=(\d+)').Groups[1].Value
        $cyc  = [regex]::Match($out, 'cycles=(\d+)').Groups[1].Value
        $results += [pscustomobject]@{ Test = $name; Result = 'FAIL'; Cycles = $cyc; Commits = ''; IPC = ''; Code = $code }
    } elseif ($out -match 'TIMEOUT') {
        $results += [pscustomobject]@{ Test = $name; Result = 'TIMEOUT'; Cycles = $Max; Commits = ''; IPC = ''; Code = '' }
    } else {
        $results += [pscustomobject]@{ Test = $name; Result = 'ERROR'; Cycles = ''; Commits = ''; IPC = ''; Code = '' }
        Write-Host $out -ForegroundColor DarkYellow
    }
    if ($Trace -or $ExTrace -or $WbTrace) { Write-Host $out }
}
Pop-Location

#--------------------------- 4. 汇总 -----------------------------------------
Write-Host ""
$results | Format-Table -AutoSize | Out-String | Write-Host
$fail = ($results | Where-Object { $_.Result -ne 'PASS' }).Count
if ($fail -eq 0) {
    Write-Host "ALL $($results.Count) TESTS PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$fail TEST(S) FAILED" -ForegroundColor Red
    exit 1
}
