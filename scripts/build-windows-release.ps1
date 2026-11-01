$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$appDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$helperDir = (Resolve-Path (Join-Path $appDir '..\backup-restore')).Path
$helperPath = Join-Path $helperDir 'bin\kontabb-bkp.exe'
$releaseDir = Join-Path $appDir 'build\windows\x64\runner\Release'
$embeddedHelper = Join-Path $releaseDir 'kontabb-bkp.exe'
$archivePath = Join-Path $appDir 'build\release\backup-drive-windows-x64-helper-v1.2.zip'

foreach ($tool in @('go', 'flutter')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Ferramenta ausente: $tool"
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path $helperPath) | Out-Null
$oldGoos = $env:GOOS
$oldGoarch = $env:GOARCH
$oldCgo = $env:CGO_ENABLED
try {
    $env:GOOS = 'windows'
    $env:GOARCH = 'amd64'
    $env:CGO_ENABLED = '0'
    & go build -C $helperDir -trimpath '-ldflags=-s -w' -o $helperPath .
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o helper.' }
} finally {
    $env:GOOS = $oldGoos
    $env:GOARCH = $oldGoarch
    $env:CGO_ENABLED = $oldCgo
}

Push-Location $appDir
try {
    & flutter build windows
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o aplicativo.' }
} finally {
    Pop-Location
}

if (-not (Test-Path $embeddedHelper -PathType Leaf)) {
    throw "O helper não foi embarcado: $embeddedHelper"
}
$sourceHash = (Get-FileHash $helperPath -Algorithm SHA256).Hash
$embeddedHash = (Get-FileHash $embeddedHelper -Algorithm SHA256).Hash
if ($sourceHash -ne $embeddedHash) {
    throw 'O build embarcou um helper diferente do recém-compilado.'
}
$stdoutPath = Join-Path ([IO.Path]::GetTempPath()) ("kontabb-help-" + [guid]::NewGuid().ToString('N') + '.out')
$stderrPath = "$stdoutPath.err"
try {
    $helpProcess = Start-Process -FilePath $embeddedHelper -ArgumentList '-h' -Wait -PassThru `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $helperHelp = (Get-Content $stdoutPath, $stderrPath -Raw) -join "`n"
    if ($helpProcess.ExitCode -ne 0 -or
        -not $helperHelp.Contains('KONTABB v1.2') -or
        -not $helperHelp.Contains('skip-missing-empty-tables')) {
        throw 'O helper embarcado não confirma a versão e a opção exigidas.'
    }
} finally {
    Remove-Item $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Force -Path (Split-Path $archivePath) | Out-Null
Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $archivePath -Force
$checkDir = Join-Path ([IO.Path]::GetTempPath()) ('kontabb-release-check-' + [guid]::NewGuid().ToString('N'))
try {
    Expand-Archive -LiteralPath $archivePath -DestinationPath $checkDir
    $archivedApp = Join-Path $checkDir 'backup_drive.exe'
    $archivedHelper = Join-Path $checkDir 'kontabb-bkp.exe'
    if (-not (Test-Path $archivedApp -PathType Leaf) -or
        -not (Test-Path $archivedHelper -PathType Leaf)) {
        throw 'O ZIP não contém o aplicativo e o helper esperados.'
    }
    if ((Get-FileHash $archivedHelper -Algorithm SHA256).Hash -ne $sourceHash) {
        throw 'O helper extraído do ZIP difere do recém-compilado.'
    }
} finally {
    if (Test-Path $checkDir) {
        Remove-Item -LiteralPath $checkDir -Recurse -Force
    }
}
Write-Host "Pacote local: $archivePath"
Get-FileHash $archivePath -Algorithm SHA256 | Format-List
Write-Host 'A assinatura do executável/instalador para distribuição deve ser feita separadamente.'
