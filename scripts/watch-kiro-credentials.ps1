[CmdletBinding()]
param(
    [int]$PollMinutes = 1,
    [string]$ProjectRoot = "C:\Users\Administrator\AIClient2API-study",
    [string]$SyncScriptPath = "C:\Users\Administrator\AIClient2API-study\scripts\sync-kiro-and-start.ps1",
    [string]$StateFile = "C:\Users\Administrator\AIClient2API-study\logs\kiro-credential-watch.state.json",
    [string]$LockFile = "C:\Users\Administrator\AIClient2API-study\logs\kiro-credential-watch.lock",
    [string]$LogFile = "C:\Users\Administrator\AIClient2API-study\logs\kiro-credential-watch.log",
    [string]$MutexName = "Global\AIClient2API-KiroCredentialWatcher"
)

$ErrorActionPreference = "Stop"

function Write-WatchLog {
    param([string]$Message)
    $line = "[watch-kiro-credentials] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Write-Host $line
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Initialize-WatchDirectories {
    $logDir = Split-Path -Parent $LogFile
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
}

function Acquire-Lock {
    $script:WatchMutex = New-Object System.Threading.Mutex($false, $MutexName)
    $hasMutex = $script:WatchMutex.WaitOne(0, $false)
    if (-not $hasMutex) {
        Write-WatchLog "another watcher is already running (mutex busy)"
        exit 0
    }

    if (Test-Path -LiteralPath $LockFile) {
        try {
            $existing = Get-Content -LiteralPath $LockFile -Raw | ConvertFrom-Json
            if ($existing.pid) {
                $proc = Get-Process -Id $existing.pid -ErrorAction SilentlyContinue
                if ($proc) {
                    Write-WatchLog "another watcher is already running with PID $($existing.pid)"
                    exit 0
                }
            }
        } catch {
        }
    }

    @{ pid = $PID; startedAt = (Get-Date).ToString("o") } |
        ConvertTo-Json | Set-Content -LiteralPath $LockFile -Encoding UTF8
}

function Release-Lock {
    if ($script:WatchMutex) {
        try {
            $script:WatchMutex.ReleaseMutex()
        } catch {
        }
        $script:WatchMutex.Dispose()
    }
    if (Test-Path -LiteralPath $LockFile) {
        Remove-Item -LiteralPath $LockFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Sync {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $SyncScriptPath -StartAIClient2API -RestartWhenCredentialChanges -VerboseLog 2>&1
    $exitCode = $LASTEXITCODE
    return @{
        Output = @($output)
        ExitCode = $exitCode
    }
}

function Read-State {
    if (-not (Test-Path -LiteralPath $StateFile)) {
        return @{}
    }
    try {
        return Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json -AsHashtable
    } catch {
        return @{}
    }
}

function Write-State {
    param([hashtable]$State)
    $State | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

Initialize-WatchDirectories
Acquire-Lock

try {
    Write-WatchLog "watcher started, poll interval=${PollMinutes}min"
    while ($true) {
        $sync = Invoke-Sync
        $joined = ($sync.Output -join "`n")
        $state = Read-State
        $state["lastRunAt"] = (Get-Date).ToString("o")
        $state["lastExitCode"] = $sync.ExitCode
        $state["lastOutput"] = $joined
        Write-State -State $state

        foreach ($line in $sync.Output) {
            if ($line) {
                Write-WatchLog $line
            }
        }

        if ($sync.ExitCode -ne 0) {
            Write-WatchLog "sync exited with code $($sync.ExitCode)"
        }

        Start-Sleep -Seconds ([Math]::Max(60, $PollMinutes * 60))
    }
} finally {
    Release-Lock
}
