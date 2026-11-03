@echo off
rem run-bash.cmd - run a bash script with Git for Windows' bash.exe, never the WSL launcher.
rem
rem Usage (from .mcp.json, .lsp.json, hooks.json):
rem   cmd /c ${CLAUDE_PLUGIN_ROOT}/tools/environment/run-bash.cmd <script.sh> [args...]
rem
rem Why (issue #83): "cmd /c bash" lets cmd pick bash from PATH, and on many machines
rem C:\Windows\System32\bash.exe (the WSL launcher) comes first. The script then runs in the
rem default WSL distribution - e.g. Docker Desktop's "docker-desktop", which has no /bin/bash -
rem and the MCP server / hook dies at once with CONNECTION_CLOSED. This wrapper resolves a real
rem Git Bash explicitly, so WSL being installed (or which distro is default) no longer matters.
rem
rem Resolution order:
rem   1. %CLAUDE_CODE_GIT_BASH_PATH% (Claude Code's own override; git-bash-check.ps1 writes it)
rem   2. the standard Git for Windows install folders
rem   3. next to git.exe found on PATH (Git\cmd\git.exe or Git\bin\git.exe -> Git\bin\bash.exe)
rem   4. last resort: bare "bash" from PATH (the old behaviour)
rem Kept as cmd (not PowerShell) because PreToolUse runs this on every tool call: cmd starts in
rem a few ms, PowerShell in hundreds.
setlocal

set "RB_BASH="
if defined CLAUDE_CODE_GIT_BASH_PATH if exist "%CLAUDE_CODE_GIT_BASH_PATH%" set "RB_BASH=%CLAUDE_CODE_GIT_BASH_PATH%"
if not defined RB_BASH if exist "%ProgramFiles%\Git\bin\bash.exe" set "RB_BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined RB_BASH if exist "%ProgramW6432%\Git\bin\bash.exe" set "RB_BASH=%ProgramW6432%\Git\bin\bash.exe"
if not defined RB_BASH if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "RB_BASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if not defined RB_BASH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "RB_BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined RB_BASH (
  for /f "delims=" %%G in ('where git.exe 2^>nul') do (
    if not defined RB_BASH if exist "%%~dpG..\bin\bash.exe" set "RB_BASH=%%~dpG..\bin\bash.exe"
    if not defined RB_BASH if exist "%%~dpGbash.exe" set "RB_BASH=%%~dpGbash.exe"
  )
)
if not defined RB_BASH set "RB_BASH=bash"

"%RB_BASH%" %*
exit /b %ERRORLEVEL%
