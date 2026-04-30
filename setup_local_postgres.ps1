# Setup script for local PostgreSQL installation

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  PostgreSQL Local Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if PostgreSQL is installed
Write-Host "1. Checking PostgreSQL installation..." -ForegroundColor Yellow
$pgService = Get-Service -Name postgresql* -ErrorAction SilentlyContinue

if ($pgService) {
    Write-Host "   [OK] PostgreSQL is installed" -ForegroundColor Green
    Write-Host "   Service: $($pgService.Name)" -ForegroundColor Gray
    Write-Host "   Status: $($pgService.Status)" -ForegroundColor Gray
    
    if ($pgService.Status -ne "Running") {
        Write-Host "   [WARNING] PostgreSQL service is not running" -ForegroundColor Yellow
        Write-Host "   Starting service..." -ForegroundColor Yellow
        Start-Service $pgService.Name
        Write-Host "   [OK] Service started" -ForegroundColor Green
    }
} else {
    Write-Host "   [ERROR] PostgreSQL is not installed" -ForegroundColor Red
    Write-Host ""
    Write-Host "   Please install PostgreSQL first:" -ForegroundColor Yellow
    Write-Host "   1. Download from: https://www.postgresql.org/download/windows/" -ForegroundColor White
    Write-Host "   2. Install PostgreSQL 15 or newer" -ForegroundColor White
    Write-Host "   3. Remember the password you set for 'postgres' user!" -ForegroundColor White
    Write-Host "   4. Run this script again" -ForegroundColor White
    exit 1
}

Write-Host ""

# Check if psql is available
Write-Host "2. Checking psql command..." -ForegroundColor Yellow
try {
    $psqlVersion = psql --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   [OK] psql is available" -ForegroundColor Green
        Write-Host "   $psqlVersion" -ForegroundColor Gray
    } else {
        Write-Host "   [WARNING] psql not in PATH" -ForegroundColor Yellow
        Write-Host "   You may need to add PostgreSQL bin to PATH" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   [WARNING] psql not found" -ForegroundColor Yellow
}

Write-Host ""

# Check if database exists
Write-Host "3. Checking database 'haneat'..." -ForegroundColor Yellow
try {
    $dbCheck = psql -U postgres -lqt 2>&1 | Select-String "haneat"
    if ($dbCheck) {
        Write-Host "   [OK] Database 'haneat' exists" -ForegroundColor Green
    } else {
        Write-Host "   [INFO] Database 'haneat' does not exist" -ForegroundColor Yellow
        Write-Host "   Creating database..." -ForegroundColor Yellow
        
        $password = Read-Host "   Enter PostgreSQL password for user 'postgres'"
        $env:PGPASSWORD = $password
        psql -U postgres -c "CREATE DATABASE haneat;" 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   [OK] Database created" -ForegroundColor Green
        } else {
            Write-Host "   [ERROR] Failed to create database" -ForegroundColor Red
            Write-Host "   Please create manually: psql -U postgres -c 'CREATE DATABASE haneat;'" -ForegroundColor Yellow
        }
        $env:PGPASSWORD = $null
    }
} catch {
    Write-Host "   [WARNING] Could not check database" -ForegroundColor Yellow
    Write-Host "   You may need to create it manually" -ForegroundColor Yellow
}

Write-Host ""

# Check backend/.env
Write-Host "4. Checking backend/.env file..." -ForegroundColor Yellow
$envPath = "backend\.env"
if (Test-Path $envPath) {
    Write-Host "   [OK] .env file exists" -ForegroundColor Green
    
    $envContent = Get-Content $envPath -Raw
    if ($envContent -match "DATABASE_URL=postgresql://postgres:.*@localhost:5432/haneat") {
        Write-Host "   [OK] DATABASE_URL is configured" -ForegroundColor Green
    } else {
        Write-Host "   [WARNING] DATABASE_URL may need to be updated" -ForegroundColor Yellow
        Write-Host "   Make sure it uses your PostgreSQL password!" -ForegroundColor Yellow
    }
} else {
    Write-Host "   [WARNING] .env file not found" -ForegroundColor Yellow
    Write-Host "   Creating .env file..." -ForegroundColor Yellow
    
    $password = Read-Host "   Enter PostgreSQL password for user 'postgres'"
    
    $envContent = @"
# JWT Secret Key
SECRET_KEY=BB2hzXR8k5ctP7nu5lzjYFW8dcVcYCC9qyo9jik1B3g

# PostgreSQL
DATABASE_URL=postgresql://postgres:$password@localhost:5432/haneat

# Redis
REDIS_URL=redis://localhost:6379/0

# App settings
APP_ENV=development
DEBUG=true
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080,http://localhost:5000,http://127.0.0.1:5000
"@
    
    $envContent | Out-File -FilePath $envPath -Encoding UTF8
    Write-Host "   [OK] .env file created" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Make sure PostgreSQL service is running" -ForegroundColor White
Write-Host "2. Check backend/.env has correct DATABASE_URL" -ForegroundColor White
Write-Host "3. Run backend: cd backend && python run.py" -ForegroundColor White
Write-Host ""


