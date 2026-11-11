@echo off
setlocal
set "DART=%FLUTTER_ROOT%\bin\cache\dart-sdk\bin\dart"
if not defined FLUTTER_ROOT set "DART=dart"
"%DART%" "%~dp0bootstrap.dart" %*
exit /b %ERRORLEVEL%
