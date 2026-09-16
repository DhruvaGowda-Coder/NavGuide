$ErrorActionPreference = 'Stop'
$toolRoot = Join-Path $env:USERPROFILE '.local\share\navguardian'
$javaDirectory = Get-ChildItem (Join-Path $toolRoot 'java') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($javaDirectory) { $env:JAVA_HOME = $javaDirectory.FullName }
$androidDirectory = Join-Path $PSScriptRoot '..\android'
& (Join-Path $androidDirectory 'gradlew.bat') -p $androidDirectory signingReport
exit $LASTEXITCODE
