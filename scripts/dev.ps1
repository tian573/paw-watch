param (
    [Parameter(Position=0)]
    [ValidateSet("setup", "lint", "test", "run", "run-emulator", "emulators", "clean", "help")]
    [string]$Command = "help"
)

switch ($Command) {
    "setup" {
        Write-Host "Installing dependencies..." -ForegroundColor Cyan
        flutter pub get
    }
    "lint" {
        Write-Host "Running static analysis..." -ForegroundColor Cyan
        flutter analyze
    }
    "test" {
        Write-Host "Running tests..." -ForegroundColor Cyan
        flutter test
    }
    "run" {
        Write-Host "Launching PawWatch..." -ForegroundColor Cyan
        flutter run
    }
    "run-emulator" {
        Write-Host "Launching PawWatch connected to local Firebase emulators..." -ForegroundColor Cyan
        flutter run --dart-define=USE_EMULATOR=true
    }
    "emulators" {
        Write-Host "Configuring Java environment for Firebase emulators..." -ForegroundColor Cyan
        if (Test-Path "C:\Program Files\Android\Android Studio\jbr\bin\java.exe") {
            $env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
            $env:Path = "$env:JAVA_HOME\bin;$env:Path"
        }
        Write-Host "Starting Firebase local emulators..." -ForegroundColor Cyan
        firebase emulators:start
    }
    "clean" {
        Write-Host "Cleaning project..." -ForegroundColor Cyan
        flutter clean
        flutter pub get
    }
    Default {
        Write-Host "PawWatch Developer Tasks:" -ForegroundColor Yellow
        Write-Host "  .\scripts\dev.ps1 setup        - Install dependencies"
        Write-Host "  .\scripts\dev.ps1 lint         - Run static analysis"
        Write-Host "  .\scripts\dev.ps1 test         - Run test suite"
        Write-Host "  .\scripts\dev.ps1 run          - Launch app"
        Write-Host "  .\scripts\dev.ps1 run-emulator - Launch app connected to local emulators"
        Write-Host "  .\scripts\dev.ps1 emulators    - Start Firebase emulators"
        Write-Host "  .\scripts\dev.ps1 clean        - Clean and re-fetch dependencies"
    }
}
