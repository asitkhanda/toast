#Requires -Version 5.1
param(
    [string]$Version = "",
    [string]$Configuration = "Release",
    [switch]$SkipPack,
    [switch]$Sign
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

function Read-MacVersion {
    $plist = Join-Path (Split-Path $Root -Parent) "Toast/Resources/Info.plist"
    if (-not (Test-Path $plist)) {
        throw "Mac Info.plist not found at $plist — version must match Toast/Resources/Info.plist"
    }
    $text = Get-Content $plist -Raw
    if ($text -match "<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>") {
        return $Matches[1].Trim()
    }
    throw "Could not parse CFBundleShortVersionString from Info.plist"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Read-MacVersion
}

Write-Host "Building Toast for Windows v$Version ($Configuration)"

$props = @(
    "/p:Configuration=$Configuration",
    "/p:Platform=x64",
    "/p:Version=$Version",
    "/p:ToastVersion=$Version",
    "/p:RuntimeIdentifier=win-x64",
    "/p:SelfContained=true",
    "/p:WindowsAppSDKSelfContained=true",
    "/p:PublishSingleFile=false"
)

dotnet restore Toast.sln
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

dotnet publish "src/Toast/Toast.csproj" -c $Configuration -r win-x64 --self-contained true @props
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$publishDir = Join-Path $Root "src/Toast/bin/$Configuration/net8.0-windows10.0.19041.0/win-x64/publish"
if (-not (Test-Path $publishDir)) {
    throw "Publish output not found: $publishDir"
}

# Ensure watchdog is in publish output
dotnet publish "src/Toast.Watchdog/Toast.Watchdog.csproj" -c $Configuration -r win-x64 --self-contained false -o $publishDir
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$dist = Join-Path $Root "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$setupName = "Toast-$Version-win-x64-Setup.exe"
$setupPath = Join-Path $dist $setupName

if ($Sign -and $env:WINDOWS_CERTIFICATE_P12 -and $env:WINDOWS_CERTIFICATE_PASSWORD) {
    Write-Host "Authenticode signing publish directory..."
    $p12 = Join-Path $env:TEMP "toast-windows-cert.p12"
    [IO.File]::WriteAllBytes($p12, [Convert]::FromBase64String($env:WINDOWS_CERTIFICATE_P12))
    $secure = ConvertTo-SecureString $env:WINDOWS_CERTIFICATE_PASSWORD -AsPlainText -Force
    Get-ChildItem $publishDir -Recurse -Include *.exe,*.dll | ForEach-Object {
        Set-AuthenticodeSignature -FilePath $_.FullName -Certificate (
            New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($p12, $secure)
        ) -TimestampServer "http://timestamp.digicert.com" | Out-Null
    }
    Remove-Item $p12 -Force -ErrorAction SilentlyContinue
} elseif ($Sign) {
    Write-Host "Sign requested but WINDOWS_CERTIFICATE_P12 / WINDOWS_CERTIFICATE_PASSWORD not set — publishing unsigned."
}

if (-not $SkipPack) {
    Write-Host "Packaging with Velopack..."
    dotnet tool update -g vpk 2>$null
    if ($LASTEXITCODE -ne 0) {
        dotnet tool install -g vpk
    }

    $packArgs = @(
        "pack",
        "--packId", "Toast",
        "--packVersion", $Version,
        "--packDir", $publishDir,
        "--mainExe", "Toast.exe",
        "--packTitle", "Toast",
        "--outputDir", $dist,
        "--channel", "win"
    )

    & vpk @packArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    # Normalize Setup.exe name for GitHub Releases / download API
    $generated = Get-ChildItem $dist -Filter "*Setup.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $generated) {
        throw "Velopack did not produce a Setup.exe in $dist"
    }
    if ($generated.FullName -ne $setupPath) {
        Copy-Item $generated.FullName $setupPath -Force
    }

    if ($Sign -and $env:WINDOWS_CERTIFICATE_P12 -and $env:WINDOWS_CERTIFICATE_PASSWORD) {
        $p12 = Join-Path $env:TEMP "toast-windows-cert.p12"
        [IO.File]::WriteAllBytes($p12, [Convert]::FromBase64String($env:WINDOWS_CERTIFICATE_P12))
        $secure = ConvertTo-SecureString $env:WINDOWS_CERTIFICATE_PASSWORD -AsPlainText -Force
        Set-AuthenticodeSignature -FilePath $setupPath -Certificate (
            New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($p12, $secure)
        ) -TimestampServer "http://timestamp.digicert.com" | Out-Null
        Remove-Item $p12 -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Windows package: $setupPath"
} else {
    Write-Host "SkipPack set — publish dir: $publishDir"
}

Write-Host "Done."
