<#
.SYNOPSIS
  Cree, reutilise et demarre (ou arrete, ou supprime) un worktree CSGO avec son propre serveur Rojo.

.DESCRIPTION
  Une branche = un worktree worktrees\csgo-<slug> = un slot N (le checkout principal etant le slot 0, port 34872) :
  `rojo serve` du worktree ecoute sur le port 34872+N. Rien de versionne n'est modifie : port, pid et journal du serveur
  sont dans worktrees\.run\<slug>.port|.pid|.log, hors du worktree (git status y reste propre, meme sur une vieille branche).

  Idempotent : a relancer sans risque au debut de chaque tache. Un worktree deja present sur la bonne branche est
  reutilise (modifications et slot conserves). Par defaut le script demarre `rojo serve` en arriere-plan et attend que
  http://localhost:<port>/api/rojo reponde. -NoUp : sans demarrer.

  Studio ne suit qu'un serveur Rojo par fenetre : la connexion au worktree se fait a la main (mode Edit, plugin Rojo,
  port du worktree, Connect). Le script rappelle la procedure.

  Registre de nettoyage (worktrees\.owners.json, lu par csgo-worktree-cleanup.ps1) : la session Claude qui lance le
  script est inscrite comme utilisatrice du worktree. Quand ses threads T3 ne sont plus actifs, Rojo est arrete ;
  quand la PR de la branche est mergee (ou fermee), le worktree est supprime (si tout est commite et pousse).

.EXAMPLE
  .\scripts\csgo-worktree.ps1 feature/x                 # cree/reutilise et demarre rojo serve (branche creee depuis main si absente)
  .\scripts\csgo-worktree.ps1 fix/y -Base feature/x     # nouvelle branche creee depuis une autre base
  .\scripts\csgo-worktree.ps1 feature/x -NoUp           # sans demarrer Rojo
  .\scripts\csgo-worktree.ps1 feature/x -Stop           # arrete Rojo
  .\scripts\csgo-worktree.ps1 feature/x -Remove         # arrete Rojo, supprime le worktree (branche conservee)

  Pour /delegate :
  .\scripts\csgo-worktree.ps1 feature/x -NoUp -NoRegister     # creer sans inscrire la session courante
  .\scripts\csgo-worktree.ps1 feature/x -RegisterThread <id>  # inscrire seulement un thread T3 (rien d'autre)
#>
param(
  [Parameter(Position = 0, Mandatory = $true)][string]$Branch,
  [string]$Base = 'main',
  [int]$Slot = 0,
  [switch]$NoUp,
  [switch]$Stop,
  [switch]$Remove,
  [switch]$NoRegister,
  [string]$RegisterThread
)

$ErrorActionPreference = 'Stop'

# Racine du checkout principal, meme si le script est lance depuis la copie d'un worktree.
$commonDir = git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir
$root = (Resolve-Path (Split-Path -Parent $commonDir)).Path
$worktrees = Join-Path $root 'worktrees'
$runDir = Join-Path $worktrees '.run'
$slug = $Branch -replace '[^A-Za-z0-9._-]', '-'
$dir = Join-Path $worktrees "csgo-$slug"
$portFile = Join-Path $runDir "$slug.port"
$pidFile = Join-Path $runDir "$slug.pid"
$logFile = Join-Path $runDir "$slug.log"
$ownersFile = Join-Path $worktrees '.owners.json'
$basePort = 34872

# Cette methode permet de lire le registre des worktrees lorsqu'on doit l'enrichir ou le nettoyer.
function Get-Owners {
  if (Test-Path $ownersFile) { return @(Get-Content $ownersFile -Raw | ConvertFrom-Json) }
  return @()
}

# Cette methode permet d'inscrire la session Claude courante (ou le thread T3 donne) comme utilisatrice de la branche
# lorsque le script cree ou reutilise un worktree depuis Claude Code, ou quand /delegate a cree son thread.
function Register-Owner([string]$Thread) {
  $session = if ($Thread) { $null } else { $env:CLAUDE_CODE_SESSION_ID }
  if (-not ($session -or $Thread)) { return }
  New-Item -ItemType Directory -Force $worktrees | Out-Null
  # @() : PowerShell deroule le tableau renvoye, une seule entree reviendrait comme objet nu (sans +=).
  $owners = @(Get-Owners)
  $entry = $owners | Where-Object { $_.branch -eq $Branch } | Select-Object -First 1
  if (-not $entry) {
    $entry = [pscustomobject]@{ branch = $Branch; sessions = @(); threads = @() }
    $owners += $entry
  }
  $t = $Thread
  if ($session) {
    if ($session -notin $entry.sessions) { $entry.sessions = @($entry.sessions) + $session }
    # Le thread T3 (stable meme apres /clear) ; vide si la session ne tourne pas dans T3.
    $t = python -I (Join-Path $PSScriptRoot 't3_threads.py') thread-of $session 2>$null
  }
  if ($t -and $t -notin $entry.threads) { $entry.threads = @($entry.threads) + $t }
  ConvertTo-Json @($owners) -Depth 4 | Set-Content $ownersFile
}

# Cette methode permet de retirer la branche du registre lorsque son worktree vient d'etre supprime.
function Unregister-Owner {
  if (-not (Test-Path $ownersFile)) { return }
  $owners = @(Get-Owners | Where-Object { $_.branch -ne $Branch })
  ConvertTo-Json @($owners) -Depth 4 | Set-Content $ownersFile
}

# Cette methode permet de savoir si une ref git existe dans le depot principal.
function Test-Ref([string]$Ref) {
  git -C $root show-ref --verify --quiet $Ref
  return ($LASTEXITCODE -eq 0)
}

# Cette methode permet de savoir si le dossier est un worktree enregistre du depot (et pas un reliquat).
function Test-WorktreeRegistered {
  $target = (Resolve-Path $dir).Path -replace '\\', '/'
  [bool](git -C $root worktree list --porcelain | Where-Object { $_ -eq "worktree $target" })
}

# Cette methode permet de savoir si un port local est deja ecoute par un processus.
function Test-PortBusy([int]$Port) {
  [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

# Cette methode permet de savoir si le serveur Rojo lance pour ce worktree (pid enregistre) tourne encore.
function Test-RojoRunning {
  (Test-Path $pidFile) -and [bool](Get-Process -Id ([int](Get-Content $pidFile)) -ErrorAction SilentlyContinue)
}

# Cette methode permet de renvoyer le code HTTP d'une URL, ou $null si rien ne repond.
function Get-UrlCode([string]$Url) {
  try { return (Invoke-WebRequest -Uri $Url -TimeoutSec 3 -SkipHttpErrorCheck).StatusCode } catch { return $null }
}

# Cette methode permet d'attendre que Rojo reponde 200 sur /api/rojo lorsqu'il demarre ; s'arrete apres 30 s,
# ou des que son processus est mort. Renvoie le dernier code.
function Wait-Rojo([string]$Url) {
  $code = $null
  for ($i = 0; $i -lt 30; $i++) {
    $code = Get-UrlCode $Url
    if ($code -eq 200) { break }
    if (-not (Test-RojoRunning)) { break }
    Start-Sleep -Seconds 1
  }
  return $code
}

# Cette methode permet d'arreter le Rojo du worktree : arbre du pid enregistre, puis tout processus rojo qui ecoute
# encore sur le port du slot. Renvoie $true si quelque chose a ete arrete.
function Stop-Rojo([int]$Port) {
  $stopped = $false
  if (Test-Path $pidFile) {
    $rojoPid = [int](Get-Content $pidFile)
    if (Get-Process -Id $rojoPid -ErrorAction SilentlyContinue) { taskkill /PID $rojoPid /T /F *> $null; $stopped = $true }
    Remove-Item $pidFile
  }
  if ($Port -gt 0) {
    $listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique)
    foreach ($p in $listeners) {
      if ((Get-Process -Id $p -ErrorAction SilentlyContinue).ProcessName -eq 'rojo') { taskkill /PID $p /T /F *> $null; $stopped = $true }
    }
  }
  return $stopped
}

$exists = Test-Path $dir
$currentPort = if (Test-Path $portFile) { [int](Get-Content $portFile) } else { 0 }

if ($RegisterThread) {
  Register-Owner $RegisterThread
  Write-Host "Thread $RegisterThread inscrit pour le nettoyage de '$Branch'."
  return
}

if ($Stop -or $Remove) {
  $s = Stop-Rojo $currentPort
  Write-Host $(if ($s) { "Rojo arrete (port $currentPort)." } else { "Aucun Rojo en cours pour '$Branch'." })
  if ($Stop) { return }
}

if ($Remove) {
  if ($exists) {
    if (Test-WorktreeRegistered) {
      if (git -C $dir status --porcelain) { throw "Modifications non commitees dans $dir : commiter ou annuler avant -Remove." }
      git -C $root worktree remove --force $dir
      if ($LASTEXITCODE -ne 0) { throw "Suppression echouee : fermer les terminaux ouverts dans $dir (y compris le repertoire courant d'une session Claude), puis relancer -Remove." }
    } elseif (-not (Get-ChildItem -Path $dir -Recurse -File -Force)) {
      # Reliquat d'un -Remove interrompu : git a deja desinscrit le worktree, il ne reste que des dossiers vides.
      Remove-Item -Recurse -Force $dir -Confirm:$false
    } else {
      throw "$dir n'est pas un worktree git mais contient des fichiers : a verifier et supprimer a la main."
    }
  }
  Remove-Item -Force -ErrorAction SilentlyContinue $portFile, $logFile
  Unregister-Owner
  Write-Host $(if ($exists) { "Worktree supprime (branche '$Branch' conservee)." } else { "Rien a supprimer : pas de worktree $dir." })
  return
}

# Verification du dossier existant avant toute action : reutilise s'il est sur la bonne branche, sinon on bloque.
if ($exists) {
  if (-not (Test-WorktreeRegistered)) { throw "$dir existe mais n'est pas un worktree du depot (reliquat ? -Remove puis relancer)." }
  $current = git -C $dir branch --show-current
  if ($current -ne $Branch) { throw "$dir est sur '$current' au lieu de '$Branch'." }
}
# Inscription apres la verification : un echec ne laisse pas d'entree orpheline dans le registre.
if (-not $NoRegister) { Register-Owner }

# Choix du slot : celui deja attribue au worktree, sinon le premier numero >= 1 libre (ports des autres worktrees et ports reellement libres).
if ($Slot -le 0 -and $currentPort -gt 0) { $Slot = $currentPort - $basePort }
if ($Slot -le 0) {
  $used = @(Get-ChildItem -Path $runDir -Filter '*.port' -File -ErrorAction SilentlyContinue | ForEach-Object { [int](Get-Content $_.FullName) })
  $Slot = 1
  while (($used -contains ($basePort + $Slot)) -or (Test-PortBusy ($basePort + $Slot))) { $Slot++ }
}
$port = $basePort + $Slot
New-Item -ItemType Directory -Force $runDir | Out-Null
Set-Content -Path $portFile -Value $port

if (-not $exists) {
  $hasOrigin = (git -C $root remote) -contains 'origin'
  if ($hasOrigin) { git -C $root fetch origin --quiet }
  # Branche existante (locale ou origin) : on la reprend ; sinon creee depuis la base (origin si present).
  if (Test-Ref "refs/heads/$Branch") {
    git -C $root worktree add $dir $Branch
  } elseif ($hasOrigin -and (Test-Ref "refs/remotes/origin/$Branch")) {
    git -C $root worktree add --track -b $Branch $dir "origin/$Branch"
  } else {
    # Base locale en avance sur origin (commits pas encore pousses) : on part de la locale pour ne pas les perdre de vue.
    $start = $Base
    if ($hasOrigin -and (Test-Ref "refs/remotes/origin/$Base")) {
      git -C $root merge-base --is-ancestor "origin/$Base" $Base 2>$null
      $localAhead = ($LASTEXITCODE -eq 0) -and ((git -C $root rev-parse $Base) -ne (git -C $root rev-parse "origin/$Base"))
      if ($localAhead) { Write-Warning "'$Base' local est en avance sur origin/$Base : branche creee depuis le local (penser a pousser $Base)." }
      else { $start = "origin/$Base" }
    }
    git -C $root worktree add -b $Branch $dir $start
  }
  if ($LASTEXITCODE -ne 0) { throw "git worktree add a echoue" }
}

$rojoCode = $null
if (-not $NoUp) {
  if (-not (Test-RojoRunning)) {
    if (Test-PortBusy $port) { throw "Port $port deja pris par un autre processus : liberer le port ou relancer avec -Slot <autre>." }
    $rojo = (Get-Command rojo -ErrorAction SilentlyContinue).Source
    if (-not $rojo) { throw "rojo introuvable : lancer ``rokit install`` dans $root." }
    $proc = Start-Process -FilePath (Get-Command pwsh).Source -WorkingDirectory $dir -WindowStyle Hidden -PassThru `
      -ArgumentList '-NoProfile', '-NonInteractive', '-Command', "& '$rojo' serve default.project.json --port $port *> '$logFile'"
    Set-Content -Path $pidFile -Value $proc.Id
  }
  $rojoCode = Wait-Rojo "http://localhost:$port/api/rojo"
}

Write-Host ""
Write-Host "Worktree '$Branch' : $dir (slot $Slot)"
# Cette methode permet de formater l'etat du serveur pour le resume ([OK (200)] attendu par les briefs /delegate).
function Format-State($Code) { if ($NoUp) { '' } elseif ($Code -eq 200) { '  [OK (200)]' } else { "  [NE REPOND PAS$(if ($Code) { " ($Code)" })]" } }
Write-Host "  rojo : http://localhost:$port$(Format-State $rojoCode)"
if ($NoUp) { Write-Host "Rojo non demarre (-NoUp) : relancer sans -NoUp pour le demarrer."; return }
Write-Host "  journal : $logFile"
Write-Host "  Studio (mode Edit, pas en Play) : plugin Rojo > port $port > Connect. Disconnect pour revenir au checkout principal (34872)."
if ($rojoCode -ne 200) { throw "Rojo ne repond pas sur le port $port : voir $logFile." }
