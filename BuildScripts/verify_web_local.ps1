[CmdletBinding()]
param(
    [ValidateRange(0, 65535)]
    [int]$Port = 0,
    [string]$PythonExecutable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$WebRoot = Join-Path $ProjectRoot "Web"
$BasePath = "arabiastrike.worldwar"
$VerificationLogRoot = Join-Path $ProjectRoot "Saved\Verification\Web"
$ServerProcess = $null
$TempRoot = $null
$OverallResult = "FAIL"

function Resolve-PythonExecutable {
    param([string]$RequestedExecutable)

    if (-not [string]::IsNullOrWhiteSpace($RequestedExecutable)) {
        if ([IO.File]::Exists($RequestedExecutable)) {
            return (Resolve-Path -LiteralPath $RequestedExecutable).Path
        }
        throw "The requested Python executable was not found: $RequestedExecutable"
    }

    foreach ($CommandName in @("python.exe", "python3", "python")) {
        $Command = Get-Command $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($Command) {
            return $Command.Source
        }
    }

    if ($env:USERPROFILE) {
        $BundledPython = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
        if ([IO.File]::Exists($BundledPython)) {
            return $BundledPython
        }
    }
    throw "Python 3 was not found. Pass -PythonExecutable explicitly."
}

function Get-AvailableLoopbackPort {
    $Listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try {
        $Listener.Start()
        return ([Net.IPEndPoint]$Listener.LocalEndpoint).Port
    }
    finally {
        $Listener.Stop()
    }
}

function Assert-HttpAsset {
    param(
        [string]$Url,
        [string]$ExpectedContentType
    )

    $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
    if ($Response.StatusCode -ne 200) {
        throw "HTTP $($Response.StatusCode) returned for $Url"
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedContentType) -and $Response.Headers["Content-Type"] -notlike "$ExpectedContentType*") {
        throw "Unexpected Content-Type '$($Response.Headers['Content-Type'])' for $Url"
    }
    Write-Host "HTTP_ASSET=$Url;STATUS=200;CONTENT_TYPE=$($Response.Headers['Content-Type']);BYTES=$($Response.RawContentLength)"
    return $Response
}

Push-Location $ProjectRoot
try {
    if (-not [IO.Directory]::Exists($WebRoot)) {
        throw "Web directory not found: $WebRoot"
    }

    $PythonExecutable = Resolve-PythonExecutable $PythonExecutable
    Write-Output "PYTHON=$PythonExecutable"

    $PreflightPath = Join-Path $ProjectRoot "ci\preflight_web_delivery.py"
    & $PythonExecutable $PreflightPath
    if ($LASTEXITCODE -ne 0) {
        throw "Web delivery preflight failed with exit code $LASTEXITCODE."
    }
    Write-Output "WEB_PREFLIGHT=PASS"

    New-Item -ItemType Directory -Force -Path $VerificationLogRoot | Out-Null
    $TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("ASWWWebVerify_{0}" -f [Guid]::NewGuid().ToString("N"))
    $PublishedWebRoot = Join-Path $TempRoot $BasePath
    New-Item -ItemType Directory -Force -Path $PublishedWebRoot | Out-Null
    Get-ChildItem -LiteralPath $WebRoot -Force | Copy-Item -Destination $PublishedWebRoot -Recurse -Force

    if ($Port -eq 0) {
        $Port = Get-AvailableLoopbackPort
    }

    $StdOutLog = Join-Path $VerificationLogRoot "local_http_stdout.log"
    $StdErrLog = Join-Path $VerificationLogRoot "local_http_stderr.log"
    $ProcessParameters = @{
        FilePath = $PythonExecutable
        ArgumentList = @("-m", "http.server", $Port, "--bind", "127.0.0.1", "--directory", $TempRoot)
        WorkingDirectory = $ProjectRoot
        RedirectStandardOutput = $StdOutLog
        RedirectStandardError = $StdErrLog
        PassThru = $true
    }
    if ($env:OS -eq "Windows_NT") {
        $ProcessParameters.WindowStyle = "Hidden"
    }
    $ServerProcess = Start-Process @ProcessParameters

    $BaseUrl = "http://127.0.0.1:$Port/$BasePath/"
    $IndexResponse = $null
    $LastError = $null
    for ($Attempt = 1; $Attempt -le 30; $Attempt += 1) {
        if ($ServerProcess.HasExited) {
            throw "Local HTTP server exited before validation. See $StdErrLog"
        }
        try {
            $IndexResponse = Invoke-WebRequest -Uri $BaseUrl -UseBasicParsing -TimeoutSec 2
            if ($IndexResponse.StatusCode -eq 200) {
                break
            }
        }
        catch {
            $LastError = $_.Exception.Message
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $IndexResponse -or $IndexResponse.StatusCode -ne 200) {
        throw "Local Web server did not become ready: $LastError"
    }

    $IndexResponse = Assert-HttpAsset -Url $BaseUrl -ExpectedContentType "text/html"
    $CssResponse = Assert-HttpAsset -Url ($BaseUrl + "app.css") -ExpectedContentType "text/css"
    $JavaScriptResponse = Assert-HttpAsset -Url ($BaseUrl + "app.js") -ExpectedContentType "text/javascript"

    if ($IndexResponse.Content -notmatch 'ARABIA STRIKE: WORLD WAR' -or $IndexResponse.Content -notmatch '\./app\.css' -or $IndexResponse.Content -notmatch '\./app\.js') {
        throw "The served launcher is missing its identity or relative asset references."
    }
    if ($JavaScriptResponse.Content -notmatch 'const\s+PIXEL_STREAMING_URL\s*=\s*"";' -or $JavaScriptResponse.Content -notmatch 'ASWW_PIXEL_STREAMING_STATE') {
        throw "The served launcher does not preserve the offline configuration and WebRTC bridge contract."
    }
    if ($CssResponse.Content -notmatch '@media \(max-width: 420px\)' -or $CssResponse.Content -notmatch 'safe-area-inset') {
        throw "The served stylesheet is missing compact mobile or safe-area rules."
    }

    $OverallResult = "PASS"
    Write-Output "LOCAL_WEB_URL=$BaseUrl"
    Write-Output "WEB_SUBPATH_RESULT=PASS"
    Write-Output "MOBILE_STATIC_LAYOUT=PASS"
    Write-Output "HEADLESS_BROWSER=NOT_RUN"
    Write-Output "LOCAL_WEB_TEST=PASS"
    Write-Output "SERVER_STDOUT_LOG=$StdOutLog"
    Write-Output "SERVER_STDERR_LOG=$StdErrLog"
}
finally {
    if ($ServerProcess -and -not $ServerProcess.HasExited) {
        Stop-Process -Id $ServerProcess.Id -Force -ErrorAction SilentlyContinue
        $ServerProcess.WaitForExit(5000) | Out-Null
    }

    if ($TempRoot) {
        $ResolvedTempRoot = [IO.Path]::GetFullPath($TempRoot)
        $ResolvedSystemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        $SafePrefix = "ASWWWebVerify_"
        if ($ResolvedTempRoot.StartsWith($ResolvedSystemTemp, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($ResolvedTempRoot).StartsWith($SafePrefix, [StringComparison]::Ordinal)) {
            Remove-Item -LiteralPath $ResolvedTempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            Write-Warning "Skipped temporary cleanup because the path failed the safety boundary: $ResolvedTempRoot"
        }
    }
    Pop-Location
}

Write-Output "OVERALL_RESULT=$OverallResult"
if ($OverallResult -ne "PASS") {
    exit 1
}
exit 0
