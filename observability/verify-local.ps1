param([string]$Api = 'http://localhost:8051', [string]$TokenFile = '')
$ErrorActionPreference = 'Stop'
$envPath = Join-Path $PSScriptRoot '../.env.local'
$raw = Get-Content -Raw -LiteralPath $envPath
$match = [regex]::Match($raw, '(?m)(?:^|\s)ADMIN_DEFAULT_PASSWORD=([^\s]+)')
if (-not $match.Success) { throw 'ADMIN_DEFAULT_PASSWORD is missing from ignored .env.local' }
$password = $match.Groups[1].Value.Trim('"', "'")
$login = Invoke-RestMethod "$Api/admin/login" -Method Post -ContentType 'application/json' -Body (@{ username='admin'; password=$password } | ConvertTo-Json)
$token = $login.data.token
if (-not $token) { throw 'Administrator login did not return a token' }
$headers = @{ Authorization = "Bearer $token" }
if ($TokenFile) {
    New-Item -ItemType Directory -Force -Path (Split-Path $TokenFile) | Out-Null
    [IO.File]::WriteAllText($TokenFile, $token)
}
# Print endpoint health/counts only, never credentials or trace payloads.
foreach ($path in @('/admin/llm/telemetry/summary', '/admin/llm/telemetry/traces', '/admin/traces', '/admin/logs')) {
    try {
        $response = Invoke-WebRequest "$Api$path" -Headers $headers -UseBasicParsing -TimeoutSec 20
        [pscustomobject]@{ Endpoint=$path; Status=$response.StatusCode }
    } catch {
        [pscustomobject]@{ Endpoint=$path; Status='Failed'; Detail=$_.Exception.Message }
    }
}
$metrics = Invoke-WebRequest "$Api/metrics" -Headers $headers -UseBasicParsing -TimeoutSec 10
[pscustomobject]@{ Endpoint='/metrics'; Status=$metrics.StatusCode; Bytes=$metrics.RawContentLength }
