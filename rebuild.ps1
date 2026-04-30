Get-Process flutter -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process dart -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host 'Stopped Flutter processes' -ForegroundColor Green

cd 'D:\HAN Eat 1'
Write-Host 'Cleaning...' -ForegroundColor Yellow
flutter clean
Remove-Item -Path 'build' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path '.dart_tool' -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'Cleaned' -ForegroundColor Green

Write-Host 'Getting dependencies...' -ForegroundColor Yellow
flutter pub get
Write-Host 'Dependencies installed' -ForegroundColor Green

Write-Host 'Ready to run. Execute: flutter run' -ForegroundColor Cyan
