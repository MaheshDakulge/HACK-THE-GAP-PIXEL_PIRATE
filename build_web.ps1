# PowerShell script to build NagarDocs Web app for GitHub Pages hosting
Write-Host "Building NagarDocs Flutter Web App..." -ForegroundColor Green

Set-Location "$PSScriptRoot\nagardocs_frontend"
flutter build web --release --base-href /HACK-THE-GAP-PIXEL_PIRATE/

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nWeb build succeeded! Compiled files are in nagardocs_frontend/build/web" -ForegroundColor Green
    Write-Host "Live GitHub Pages URL will be: https://MaheshDakulge.github.io/HACK-THE-GAP-PIXEL_PIRATE/" -ForegroundColor Cyan
} else {
    Write-Host "`nBuild failed. Please check errors above." -ForegroundColor Red
}
