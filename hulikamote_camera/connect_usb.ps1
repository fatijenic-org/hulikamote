# Connects the phone (USB cable) to HULI-KAMOTE: the phone's camera becomes the Live Monitor's source.
#   1. finds adb (Android platform-tools)   2. finds the phone   3. adb forward: the phone's port 8080 becomes this laptop's port 8080
#   4. saves "Phone (USB)" as a camera in the backend and makes it the live source
# Run it through "Connect Phone.bat". Safe to run again (every time the cable is plugged in again).
param(
    [int]$Port = 8080,
    [string]$Backend = 'http://127.0.0.1:8000',
    [string]$Name = 'Phone (USB)'
)
$ErrorActionPreference = 'Stop'

function Say($text, $color = 'White') { Write-Host $text -ForegroundColor $color }

# 1. adb
$adb = $null
$places = @((Get-Command adb -ErrorAction SilentlyContinue).Source)
if ($env:ANDROID_HOME) { $places += "$env:ANDROID_HOME\platform-tools\adb.exe" }
if ($env:ANDROID_SDK_ROOT) { $places += "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe" }
$places += "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
foreach ($place in $places) { if ($place -and (Test-Path $place)) { $adb = $place; break } }
if (-not $adb) {
    Say 'adb was not found. Install Android Studio (it brings the platform-tools) and run this again.' Red
    exit 1
}

# 2. the phone
& $adb start-server | Out-Null
$lines = @(& $adb devices | Select-Object -Skip 1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
if ($lines | Where-Object { $_ -match 'unauthorized' }) {
    Say 'The phone asks to allow this laptop. Look at the phone screen, tap Allow, then run this again.' Yellow
    exit 1
}
$ready = @($lines | Where-Object { $_ -match '\sdevice$' } | ForEach-Object { ($_ -split '\s+')[0] })
if ($ready.Count -eq 0) {
    Say 'No phone found. Plug it in with the USB cable and turn on USB debugging (Settings > Developer options).' Red
    exit 1
}
$serial = $ready[0]
Say "Phone found: $serial" Green

# 3. the cable becomes a network: laptop port -> phone port
& $adb -s $serial forward "tcp:$Port" "tcp:$Port" | Out-Null
$url = "http://127.0.0.1:$Port/video"
Say "USB link ready: $url" Green

# the app must be broadcasting for a picture to exist
$broadcasting = $false
try {
    Invoke-WebRequest "http://127.0.0.1:$Port/snapshot.jpg" -UseBasicParsing -TimeoutSec 4 | Out-Null
    $broadcasting = $true
} catch {
}
if ($broadcasting) { Say 'The phone is broadcasting.' Green }
else { Say 'The phone is not broadcasting yet: open the HULI-KAMOTE Camera app and press Start broadcasting.' Yellow }

# 4. the Live Monitor
try {
    $saved = @((Invoke-RestMethod "$Backend/settings/camera-profiles" -TimeoutSec 4).profiles)
    $profiles = @($saved | Where-Object { $_.name -ne $Name } | ForEach-Object { @{ name = $_.name; url = $_.url } })
    $profiles += @{ name = $Name; url = $url }
    Invoke-RestMethod "$Backend/settings/camera-profiles" -Method Put -ContentType 'application/json' `
        -Body (@{ profiles = $profiles } | ConvertTo-Json -Depth 4) -TimeoutSec 6 | Out-Null
    Invoke-RestMethod "$Backend/settings/camera-profiles/use?name=$([uri]::EscapeDataString($Name))" -Method Post -TimeoutSec 8 | Out-Null
    Say 'The Live Monitor now uses the phone. Open it and press Start monitoring.' Green
} catch {
    Say "The backend was not reached ($Backend). Start it, then run this again." Yellow
    Say "Or by hand: Live Monitor > Change source > Camera or phone... > Address: $url" Yellow
}
