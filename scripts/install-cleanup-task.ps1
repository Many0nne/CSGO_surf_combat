<#
.SYNOPSIS
  Installe (ou met a jour) la tache planifiee Windows "CSGO worktree cleanup" qui lance csgo-worktree-cleanup.ps1
  toutes les 10 minutes et a l'ouverture de session, sans fenetre (conhost --headless).
  Idempotent ; -Uninstall retire la tache. A lancer depuis le checkout principal (le chemin du script y est fige).

.EXAMPLE
  .\scripts\install-cleanup-task.ps1
  .\scripts\install-cleanup-task.ps1 -Uninstall
#>
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$taskName = 'CSGO worktree cleanup'

if ($Uninstall) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
  Write-Host "Tache '$taskName' retiree."
  return
}

# Toujours le script du checkout principal (avance en fast-forward a chaque passage), meme lance depuis un worktree.
$root = (Resolve-Path (Split-Path -Parent (git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir))).Path
$script = Join-Path $root 'scripts\csgo-worktree-cleanup.ps1'
$pwsh = (Get-Command pwsh).Source
# conhost --headless : pas de fenetre qui clignote toutes les 10 minutes.
$action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless `"$pwsh`" -NoProfile -NonInteractive -File `"$script`""
$triggers = @(
  New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10)
)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
  -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Settings $settings `
  -Description 'Arrete le Rojo des worktrees CSGO dont les threads T3 sont termines, supprime ceux dont la PR est mergee ou fermee.' -Force | Out-Null
Write-Host "Tache '$taskName' installee (toutes les 10 minutes et a l'ouverture de session)."
