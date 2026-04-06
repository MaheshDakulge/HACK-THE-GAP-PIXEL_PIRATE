$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$port = 8000

Write-Host "NagarDocs Dev Tunnel Started" -ForegroundColor Green
Write-Host "Watching USB connection... (Press Ctrl+C to stop)" -ForegroundColor Yellow

while ($true) {
    # Get device list
    $deviceOutput = & $adb devices 2>&1
    $connected = $deviceOutput | Where-Object { $_ -match "\bdevice$" -and $_ -notmatch "List of" }

    if ($connected) {
        # Apply tunnel
        & $adb reverse tcp:$port tcp:$port | Out-Null
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Tunnel ACTIVE on port $port" -ForegroundColor Green
    } else {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Phone not detected, waiting..." -ForegroundColor Red
    }

    Start-Sleep -Seconds 3
}
