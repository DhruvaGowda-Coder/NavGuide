param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArguments)
$ErrorActionPreference = 'Stop'
$toolRoot = Join-Path $env:USERPROFILE '.local\share\navguardian'
$flutterCommand = Join-Path $toolRoot 'flutter\bin\flutter.bat'
if (-not (Test-Path $flutterCommand)) { $flutterCommand = (Get-Command flutter -ErrorAction Stop).Source }
$sdkPath = Join-Path $toolRoot 'android-sdk'
if (Test-Path $sdkPath) { $env:ANDROID_HOME = $sdkPath }
$javaDirectory = Get-ChildItem (Join-Path $toolRoot 'java') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($javaDirectory) { $env:JAVA_HOME = $javaDirectory.FullName; $env:PATH = "$($javaDirectory.FullName)\bin;$env:PATH" }
& $flutterCommand @FlutterArguments
exit $LASTEXITCODE
