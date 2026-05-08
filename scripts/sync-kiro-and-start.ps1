[CmdletBinding()]
param(
    [string]$ProjectRoot = "C:\Users\Administrator\AIClient2API-study",
    [string]$ProviderPoolsPath = "C:\Users\Administrator\AIClient2API-study\configs\provider_pools.json",
    [string]$CredentialDir = "",
    [int]$ApiPort = 3000,
    [int]$MasterPort = 3100,
    [string]$NodePath = "C:\Program Files\nodejs\npm.cmd",
    [switch]$StartAIClient2API,
    [switch]$RestartWhenCredentialChanges,
    [switch]$ForceRestart,
    [switch]$VerboseLog
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    Write-Host "[sync-kiro-and-start] $Message"
}

function Get-ListeningPid {
    param([int]$Port)
    $line = netstat -ano -p tcp | Select-String ":$Port\s+.*LISTENING\s+(\d+)$" | Select-Object -First 1
    if (-not $line) { return $null }
    $text = $line.ToString().Trim()
    if ($text -match "LISTENING\s+(\d+)$") { return [int]$matches[1] }
    return $null
}

function Stop-PortProcess {
    param([int]$Port)
    $pid = Get-ListeningPid -Port $Port
    if ($null -ne $pid) {
        try {
            Stop-Process -Id $pid -Force -ErrorAction Stop
            Write-Log "stopped PID $pid on port $Port"
        } catch {
            Write-Log ("failed stopping PID {0} on port {1}: {2}" -f $pid, $Port, $_.Exception.Message)
        }
    }
}

function Get-KiroCredentialDir {
    if ($CredentialDir) { return $CredentialDir }
    return [System.IO.Path]::Combine($env:USERPROFILE, ".aws", "sso", "cache")
}

function Get-LatestKiroCredentialFile {
    param([string]$Directory)
    if (-not (Test-Path -LiteralPath $Directory)) {
        throw "credential directory not found: $Directory"
    }

    $candidates = Get-ChildItem -LiteralPath $Directory -File -Filter *.json | Sort-Object LastWriteTime -Descending
    foreach ($file in $candidates) {
        try {
            $json = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            $hasToken = ($null -ne $json.refreshToken) -or ($null -ne $json.refresh_token) -or ($null -ne $json.accessToken) -or ($null -ne $json.access_token)
            $hasExpiry = ($null -ne $json.expiry_date) -or ($null -ne $json.expiry) -or ($null -ne $json.expires_at) -or ($null -ne $json.expiresAt)
            if ($hasToken -and $hasExpiry) { return $file.FullName }
        } catch {
            continue
        }
    }

    throw "no usable Kiro credential file found under $Directory"
}

function Update-ProviderPoolCredentialPath {
    param(
        [string]$JsonPath,
        [string]$CredentialPath
    )
    if (-not (Test-Path -LiteralPath $JsonPath)) {
        throw "provider pools file not found: $JsonPath"
    }

    $data = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json
    if (-not $data.'claude-kiro-oauth' -or $data.'claude-kiro-oauth'.Count -lt 1) {
        throw "claude-kiro-oauth pool missing in $JsonPath"
    }

    $node = $data.'claude-kiro-oauth'[0]
    $normalized = ($CredentialPath -replace '\\', '/')
    $previous = [string]$node.KIRO_OAUTH_CREDS_FILE_PATH
    $changed = $previous -ne $normalized

    $node.KIRO_OAUTH_CREDS_FILE_PATH = $normalized
    $node.isHealthy = $true
    $node.isDisabled = $false
    $node.errorCount = 0
    $node.lastErrorTime = $null
    $node.needsRefresh = $false
    $node.refreshCount = 0
    $node.lastErrorMessage = $null
    $node.scheduledRecoveryTime = $null

    $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $JsonPath -Encoding UTF8

    return @{
        Changed = $changed
        Previous = $previous
        Current = $normalized
    }
}

function Get-CurrentProviderPoolCredentialPath {
    param([string]$JsonPath)
    if (-not (Test-Path -LiteralPath $JsonPath)) { return $null }
    $data = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json
    if (-not $data.'claude-kiro-oauth' -or $data.'claude-kiro-oauth'.Count -lt 1) { return $null }
    return [string]$data.'claude-kiro-oauth'[0].KIRO_OAUTH_CREDS_FILE_PATH
}

function Start-AIClient2APIProcess {
    param(
        [string]$Root,
        [int]$Port,
        [string]$NpmPath
    )
    $current = Get-ListeningPid -Port $Port
    if ($null -eq $current) {
        Start-Process -FilePath $NpmPath -ArgumentList "run", "start" -WorkingDirectory $Root -WindowStyle Hidden | Out-Null
        Write-Log "started AIClient2API"
    } else {
        Write-Log "AIClient2API already listening on $Port with PID $current"
    }
}

try {
    $result = @{
        Changed = $false
        Previous = $null
        Current = $null
    }

    try {
        $credPath = Get-LatestKiroCredentialFile -Directory (Get-KiroCredentialDir)
        Write-Log "selected credential: $credPath"
        $result = Update-ProviderPoolCredentialPath -JsonPath $ProviderPoolsPath -CredentialPath $credPath
        if ($result.Changed) {
            Write-Log "updated provider pool credential path"
            if ($VerboseLog) {
                Write-Log "previous: $($result.Previous)"
                Write-Log "current : $($result.Current)"
            }
        } else {
            Write-Log "provider pool credential path already current"
        }
    } catch {
        $fallbackPath = Get-CurrentProviderPoolCredentialPath -JsonPath $ProviderPoolsPath
        Write-Log ("credential scan skipped: {0}" -f $_.Exception.Message)
        if ($fallbackPath) {
            Write-Log "using existing provider pool credential path"
            $result.Current = $fallbackPath
        } else {
            throw
        }
    }

    if ($StartAIClient2API) {
        if ($ForceRestart -or ($RestartWhenCredentialChanges -and $result.Changed)) {
            Stop-PortProcess -Port $ApiPort
            Stop-PortProcess -Port $MasterPort
            Start-Sleep -Seconds 2
        }
        Start-AIClient2APIProcess -Root $ProjectRoot -Port $ApiPort -NpmPath $NodePath
    }
} catch {
    Write-Log "error: $($_.Exception.Message)"
    exit 1
}
