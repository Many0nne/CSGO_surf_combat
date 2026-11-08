<#
.SYNOPSIS
  Compile et installe le plugin Rojo « CSGO autoconnect » (plugin officiel + autoconnect.patch) dans Studio.

.DESCRIPTION
  Clone le tag Rojo de rokit.toml dans worktrees\.run\rojo-plugin-src, applique autoconnect.patch, compile le plugin
  avec le rojo du projet, puis remplace %LOCALAPPDATA%\Roblox\Plugins\Rojo.rbxm. Le plugin officiel est sauvegarde
  une fois dans %LOCALAPPDATA%\Roblox\Rojo.official.rbxm (hors du dossier Plugins : Studio y charge tout .rbxm).
  Redemarrer Studio ensuite. Voir README.md.

.EXAMPLE
  .\tools\rojo-plugin\install.ps1             # compile et installe
  .\tools\rojo-plugin\install.ps1 -BuildOnly  # compile seulement (affiche le chemin du .rbxm)
  .\tools\rojo-plugin\install.ps1 -Uninstall  # remet le plugin officiel sauvegarde
#>
param(
  [switch]$BuildOnly,
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$commonDir = git -C $repo rev-parse --path-format=absolute --git-common-dir
$root = (Resolve-Path (Split-Path -Parent $commonDir)).Path
$runDir = Join-Path $root 'worktrees\.run'
$src = Join-Path $runDir 'rojo-plugin-src'
$out = Join-Path $runDir 'Rojo-csgo-autoconnect.rbxm'
$pluginsDir = Join-Path $env:LOCALAPPDATA 'Roblox\Plugins'
$installed = Join-Path $pluginsDir 'Rojo.rbxm'
$backup = Join-Path $env:LOCALAPPDATA 'Roblox\Rojo.official.rbxm'

if ($Uninstall) {
  if (-not (Test-Path $backup)) { throw "Pas de sauvegarde $backup : reinstaller le plugin officiel avec ``rojo plugin install``." }
  Copy-Item -Force $backup $installed
  Write-Host "Plugin Rojo officiel remis ($installed). Redemarrer Studio."
  return
}

# Version de Rojo du projet : le plugin doit rester compatible avec le serveur `rojo serve`.
$version = (Select-String -Path (Join-Path $repo 'rokit.toml') -Pattern 'rojo-rbx/rojo@([\d.]+)').Matches[0].Groups[1].Value
$tag = "v$version"

# Clone frais a chaque fois : le patch s'applique toujours sur le tag exact.
if (Test-Path $src) { Remove-Item -Recurse -Force $src -Confirm:$false }
git -c advice.detachedHead=false clone --quiet --depth 1 --branch $tag --recurse-submodules --shallow-submodules https://github.com/rojo-rbx/rojo.git $src
if ($LASTEXITCODE -ne 0) { throw "Clone de Rojo $tag echoue." }
git -C $src apply (Join-Path $PSScriptRoot 'autoconnect.patch')
if ($LASTEXITCODE -ne 0) { throw "autoconnect.patch ne s'applique pas sur Rojo $tag : le mettre a jour (voir README.md)." }

# rojo lance depuis le depot : le shim Rokit y trouve la version du projet.
Push-Location $repo
try { rojo build (Join-Path $src 'plugin.project.json') -o $out } finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { throw 'Compilation du plugin echouee.' }
Write-Host "Plugin compile : $out (Rojo $tag + autoconnect)."
if ($BuildOnly) { return }

New-Item -ItemType Directory -Force $pluginsDir | Out-Null
if ((Test-Path $installed) -and -not (Test-Path $backup)) {
  Copy-Item $installed $backup
  Write-Host "Plugin officiel sauvegarde : $backup"
}
Copy-Item -Force $out $installed
Write-Host "Installe : $installed. Redemarrer Studio, puis autoriser l'acces a localhost si Studio le demande."
