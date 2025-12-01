#!/usr/bin/env pwsh
<#
.SYNOPSIS
    DLL dependency copier for kernels built on Windows

.DESCRIPTION
    Analyzes a .pyd file and copies its DLL dependencies to make it portable.
    Uses dumpbin to find dependencies and searches PATH for the DLLs.

.PARAMETER PydFile
    Path to the .pyd file to analyze

.PARAMETER OutputDir
    Output directory (defaults to .pyd file's directory)

.EXAMPLE
    .\copy_deps.ps1 -PydFile "build\_rmsnorm.pyd"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$PydFile,
    
    [string]$OutputDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Set output directory
if (-not $OutputDir) {
    $OutputDir = Split-Path -Parent $PydFile
}

if (-not (Test-Path $PydFile)) {
    Write-Error "File not found: $PydFile"
    exit 1
}

Write-Host "`n==============================================================" -ForegroundColor Cyan
Write-Host "Copying DLL Dependencies" -ForegroundColor Cyan
Write-Host "Source: $PydFile" -ForegroundColor Gray
Write-Host "Target: $OutputDir" -ForegroundColor Gray
Write-Host "==============================================================`n" -ForegroundColor Cyan

# Find dumpbin
$dumpbin = Get-Command dumpbin -ErrorAction SilentlyContinue
if (-not $dumpbin) {
    $vsPath = Get-ChildItem "C:\Program Files\Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($vsPath) {
        $dumpbin = $vsPath.FullName
    } else {
        Write-Error "dumpbin.exe not found. Please install Visual Studio with C++ tools."
        exit 1
    }
}

# Get dependencies
$output = & $dumpbin /DEPENDENTS $PydFile 2>&1 | Out-String
$dependencies = [regex]::Matches($output, '^\s+(\w+\.dll)\s*$', 'Multiline') | ForEach-Object { $_.Groups[1].Value }

if (-not $dependencies) {
    Write-Warning "No dependencies found"
    exit 0
}

Write-Host "Found $($dependencies.Count) dependencies`n" -ForegroundColor Yellow

# System DLLs to skip (Windows system libraries that are always available)
$skipPatterns = @('KERNEL32', 'USER32', 'GDI32', 'ADVAPI32', 'SHELL32', 
                  'ole32', 'OLEAUT32', 'WS2_32', 'WINMM', 'SETUPAPI',
                  'api-ms-win', 'ucrtbase', 'python3')

# Get PATH
$pathDirs = $env:PATH -split [IO.Path]::PathSeparator

$copied = 0
$skipped = 0

foreach ($dll in $dependencies) {
    # Skip system DLLs but keep MSVC/Intel runtime DLLs
    $shouldSkip = $false
    $isRuntimeDll = $dll -match '(MSVCP|VCRUNTIME|libmmd|svml_dispmd)'
    
    foreach ($pattern in $skipPatterns) {
        if ($dll -like "*$pattern*") {
            # Don't skip if it's a redistributable runtime DLL
            if (-not $isRuntimeDll) {
                Write-Host "  ⊘ $dll" -ForegroundColor DarkGray -NoNewline
                Write-Host " (system)" -ForegroundColor DarkGray
                $skipped++
                $shouldSkip = $true
                break
            }
        }
    }
    if ($shouldSkip) { continue }
    
    # Find DLL in PATH
    foreach ($dir in $pathDirs) {
        $dllPath = Join-Path $dir $dll
        if (Test-Path $dllPath) {
            $destPath = Join-Path $OutputDir $dll
            
            # Skip if identical
            if (Test-Path $destPath) {
                $srcHash = (Get-FileHash $dllPath -Algorithm MD5).Hash
                $dstHash = (Get-FileHash $destPath -Algorithm MD5).Hash
                if ($srcHash -eq $dstHash) {
                    $found = $true
                    break
                }
            }
            
            Copy-Item -Path $dllPath -Destination $destPath -Force
            Write-Host "  ✅ $dll" -ForegroundColor Green -NoNewline
            Write-Host " <- $dir" -ForegroundColor DarkGray
            $copied++
            break
        }
    }
}

Write-Host "`n==============================================================" -ForegroundColor Cyan
Write-Host "Copied: $copied | Skipped: $skipped" -ForegroundColor Green
Write-Host "==============================================================`n" -ForegroundColor Cyan

exit 0