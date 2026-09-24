# Headless checks for the hunter project, with their reports printed.
#
# WHY THIS FILE EXISTS. Two runs in a row looked like "the engine hangs at
# startup": only the banner appeared, no report was written, the process lived
# forever. The cause was not the engine but a missing "--" separator. Without it
# Godot treats the flag as its own, OS.get_cmdline_user_args() stays empty,
# main.gd finds no mode and falls through to _open_game() -- in headless the game
# then runs forever: no output, no report, no quit(). This script always inserts
# "--" and adds --quit-after as a safety net so a run cannot outlive its welcome.
#
# ENCODING. This file is deliberately pure ASCII. Windows PowerShell 5.1 reads a
# .ps1 without a BOM as code page 1251, so any UTF-8 Cyrillic here turns into
# mojibake and the parser dies with "MissingEndCurlyBrace". Reports printed by
# this script may be Cyrillic: they are read from files, not parsed as code.
#
# Usage:
#   .\tools\run_headless.ps1                      # all check modes
#   .\tools\run_headless.ps1 --prep               # one mode
#   .\tools\run_headless.ps1 --prep --validate    # several
#
# WARNING: never kill Godot processes by name or by start time. In this project
# the editor and the runs are the same binary, so Get-Process *Godot* cannot tell
# them apart. An orphaned run is safer left alone than killed blindly.

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Modes
)

# NOTE: no $ErrorActionPreference = "Stop" here, deliberately. Under Windows
# PowerShell 5.1 it turns ANY line Godot writes to stderr into a terminating
# error, so a script error killed this script before it could print its own
# verdict -- the diagnosis was left buried in raw engine output. Failing loudly
# is handled explicitly below instead.

$Root  = Split-Path -Parent $PSScriptRoot
$Godot = "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
$Log   = Join-Path $Root "_glog.txt"

# Mode -> report file written by Godot itself (FileAccess, not stdout).
# The names are checked against main.gd on purpose: a wrong name here reports
# "NO REPORT" for a perfectly healthy run, which is worse than no tool at all.
# It already happened once -- _val_out.txt instead of _validate_out.txt.
$Reports = [ordered]@{
    "--validate" = "_validate_out.txt"
    "--outcomes" = "_outcomes_out.txt"
    "--swap"     = "_swap_out.txt"
    "--prep"     = "_prep_out.txt"
    "--art"      = "_art_out.txt"
    "--ui"       = "_ui_out.txt"
    "--smoke"    = "_smoke_out.txt"
    "--prose"    = "_prose_out.txt"
    "--loop"     = "_loop_out.txt"
    "--repeat"   = "_repeat_out.txt"
}

if (-not $Modes -or $Modes.Count -eq 0) { $Modes = @($Reports.Keys) }

if (-not (Test-Path $Godot)) { throw "Godot not found: $Godot" }

$failed = 0
foreach ($mode in $Modes) {
    if (-not $Reports.Contains($mode)) {
        Write-Host ("SKIP: {0} -- unknown mode. Known: {1}" -f $mode, ($Reports.Keys -join ", ")) -ForegroundColor Yellow
        continue
    }

    $report = Join-Path $Root $Reports[$mode]
    $errLog = Join-Path $Root "_gerr.txt"
    Remove-Item $report -ErrorAction SilentlyContinue
    # The log is inspected for script errors below, so it must not carry a
    # previous run's errors into this one.
    Remove-Item $Log -ErrorAction SilentlyContinue
    Remove-Item $errLog -ErrorAction SilentlyContinue

    Write-Host ("=== {0}" -f $mode) -ForegroundColor Cyan

    # "--" is mandatory: without it the mode never reaches main.gd. See main.gd.
    # --quit-after goes BEFORE "--", otherwise it becomes a user flag itself.
    #
    # Start-Process -Wait, NOT the call operator. This Godot build launches
    # asynchronously when invoked as `& $Godot ...` from a script: the call
    # returns at once and the report does not exist yet, so the script reported
    # NO REPORT for runs that were perfectly fine.
    #
    # stderr is captured because it is the ONLY place a script error appears:
    #   * the exit code is 0 even when main.gd fails to compile (measured);
    #   * --log-file is not written at all on that path (measured).
    # So a missing report plus a non-empty stderr is the real failure signal.
    $proc = Start-Process -FilePath $Godot -NoNewWindow -Wait -PassThru `
        -RedirectStandardError $errLog -ArgumentList @(
        "--headless", "--path", $Root, "--quit-after", "2000", "--", $mode, "--log-file", $Log
    )
    $code = $proc.ExitCode

    # A PARSE ERROR MUST BE NAMED AS SUCH. A broken script dies before writing
    # its report, and "NO REPORT" alone sends you hunting for a cause that the
    # engine states outright. Reading it out is the difference between
    # "your check failed" and "your code does not compile".
    $scriptErrors = @()
    if (Test-Path $errLog) {
        $scriptErrors = @(Select-String -Path $errLog -Pattern "SCRIPT ERROR|Parse Error|Failed to load|Nonexistent function|Cannot find member|Compile Error" -ErrorAction SilentlyContinue)
    }

    if (Test-Path $report) {
        Get-Content $report
    } else {
        Write-Host ("NO REPORT: {0}" -f $report) -ForegroundColor Red
    }

    if ($scriptErrors.Count -gt 0) {
        Write-Host ("SCRIPT ERRORS: {0}" -f $scriptErrors.Count) -ForegroundColor Red
        $scriptErrors | Select-Object -First 10 | ForEach-Object { Write-Host ("  " + $_.Line.Trim()) -ForegroundColor Red }
        $failed++
    }
    if (-not (Test-Path $report)) {
        $failed++
    }

    if ($code -ne 0) {
        Write-Host ("EXIT CODE: {0}" -f $code) -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
if ($failed -eq 0) {
    Write-Host "ALL MODES OK" -ForegroundColor Green
} else {
    Write-Host ("PROBLEMS: {0}" -f $failed) -ForegroundColor Red
    exit 1
}
