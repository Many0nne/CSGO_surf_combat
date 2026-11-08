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

  Studio ne suit qu'un serveur Rojo par fenetre. Avec le plugin Rojo modifie (tools\rojo-plugin), -AcquireStudio l'y
  connecte seul et la liberation le renvoie sur 34872 ; sinon connexion a la main (mode Edit, plugin Rojo, port, Connect).

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

  Studio partage (une seule fenetre Studio pour tous les worktrees, verrou worktrees\.run\studio.lock) :
  .\scripts\csgo-worktree.ps1 feature/x -AcquireStudio                # reserve Studio, ou sort en code 2 avec le detenteur
  .\scripts\csgo-worktree.ps1 feature/x -AcquireStudio -WaitStudio 20 # attend jusqu'a 20 min qu'il se libere
  .\scripts\csgo-worktree.ps1 feature/x -ReleaseStudio                # libere (aussi fait par -Stop et -Remove)
  .\scripts\csgo-worktree.ps1 feature/x -StudioStatus                 # detenteur actuel et port auquel Studio est connecte
  Un verrou est repris d'office si son detenteur n'a plus de worktree, plus de Rojo, ou plus de thread T3 actif.
#>
param(
  [Parameter(Position = 0, Mandatory = $true)][string]$Branch,
  [string]$Base = 'main',
  [int]$Slot = 0,
  [switch]$NoUp,
  [switch]$Stop,
  [switch]$Remove,
  [switch]$NoRegister,
  [string]$RegisterThread,
  [switch]$AcquireStudio,
  [int]$WaitStudio = 0,
  [switch]$ReleaseStudio,
  [switch]$StudioStatus
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

$studioLock = Join-Path $runDir 'studio.lock'

# Cette methode permet de lire le verrou Studio (branche, port, depuis) lorsqu'on veut savoir qui utilise Studio ; $null si libre.
function Get-StudioLock {
  if (-not (Test-Path $studioLock)) { return $null }
  try { return Get-Content $studioLock -Raw | ConvertFrom-Json } catch { return $null }
}

# Cette methode permet de dire pourquoi le detenteur du verrou Studio ne l'utilise plus (worktree supprime, Rojo arrete,
# threads T3 tous termines) lorsqu'une autre branche le demande ; renvoie $null si le detenteur est encore actif.
function Get-StudioLockStaleReason($Lock) {
  $holderSlug = $Lock.branch -replace '[^A-Za-z0-9._-]', '-'
  if (-not (Test-Path (Join-Path $worktrees "csgo-$holderSlug"))) { return 'worktree supprime' }
  $holderPid = Join-Path $runDir "$holderSlug.pid"
  if (-not ((Test-Path $holderPid) -and (Get-Process -Id ([int](Get-Content $holderPid)) -ErrorAction SilentlyContinue))) {
    return 'Rojo arrete'
  }
  $entry = Get-Owners | Where-Object { $_.branch -eq $Lock.branch } | Select-Object -First 1
  $threads = @($entry.threads | Where-Object { $_ })
  if ($threads) {
    $states = python -I (Join-Path $PSScriptRoot 't3_threads.py') status @threads 2>$null | ConvertFrom-Json
    if ($states -and -not @($threads | Where-Object { $states.$_ -eq 'active' })) { return 'threads T3 termines' }
  }
  return $null
}

# Cette methode permet de lister les ports Rojo (checkout principal et worktrees) auxquels Studio est connecte en ce moment,
# lorsqu'il faut dire a l'agent ou a l'utilisateur s'il doit faire Disconnect avant de se connecter ailleurs.
function Get-StudioConnectedPorts {
  $ports = @($basePort) + @(Get-ChildItem -Path $runDir -Filter '*.port' -File -ErrorAction SilentlyContinue |
      ForEach-Object { [int](Get-Content $_.FullName) })
  @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
      Where-Object { $_.LocalPort -in $ports } | Select-Object -ExpandProperty LocalPort -Unique | Sort-Object)
}

# Cette methode permet de decrire en une ligne le detenteur du verrou Studio lorsqu'on l'affiche.
function Format-StudioLock($Lock) { "'$($Lock.branch)' (port $($Lock.port), depuis $($Lock.since))" }

# Cette methode permet d'executer une action sur le verrou Studio sous un mutex systeme, lorsque deux agents le demandent en meme temps.
function Invoke-StudioLocked([scriptblock]$Action) {
  $m = New-Object System.Threading.Mutex($false, 'Local\csgo-studio-lock')
  [void]$m.WaitOne()
  try { & $Action } finally { $m.ReleaseMutex() }
}

$studioTarget = Join-Path $runDir 'studio.target'
$studioStateFile = Join-Path $runDir 'studio.status'
$controlPort = 34870
$controlPidFile = Join-Path $runDir 'rojo-control.pid'

# Cette methode permet de demarrer le serveur de commande du plugin Rojo modifie (tools/rojo-plugin) lorsqu'il ne
# tourne pas encore ; sans le plugin modifie dans Studio, il ne sert a rien mais ne gene pas.
function Start-RojoControl {
  $health = try { (Invoke-WebRequest "http://localhost:$controlPort/health" -TimeoutSec 3).Content } catch { $null }
  if ($health -eq 'csgo-control 2') { return }
  # Ancienne version encore lancee : on l'arrete avant de demarrer celle du depot.
  @(Get-NetTCPConnection -LocalPort $controlPort -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique) |
    Where-Object { (Get-Process -Id $_ -ErrorAction SilentlyContinue).ProcessName -eq 'lune' } | ForEach-Object { taskkill /PID $_ /T /F *> $null }
  if (Test-Path $controlPidFile) {
    $old = [int](Get-Content $controlPidFile)
    if (Get-Process -Id $old -ErrorAction SilentlyContinue) { taskkill /PID $old /T /F *> $null }
  }
  $lune = (Get-Command lune -ErrorAction SilentlyContinue).Source
  $server = Join-Path $PSScriptRoot '..\tools\rojo-plugin\control-server.luau'
  if (-not ($lune -and (Test-Path $server))) { return }
  # Dossier de travail = celui du script : le shim Rokit de lune y trouve rokit.toml.
  $proc = Start-Process -FilePath (Get-Command pwsh).Source -WorkingDirectory (Split-Path -Parent $PSScriptRoot) `
    -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile',
    '-NonInteractive', '-Command', "& '$lune' run '$((Resolve-Path $server).Path)' '$studioTarget' '$studioStateFile' *>'$(Join-Path $runDir 'rojo-control.log')'"
  Set-Content -Path $controlPidFile -Value $proc.Id
}

# Cette methode permet de publier le port Rojo que Studio doit suivre lorsque le verrou change de main ;
# chaine vide = deconnecter. Le plugin modifie ne reagit qu'au changement de `rev`, renvoyee par la methode.
function Set-StudioTarget([string]$Port) {
  New-Item -ItemType Directory -Force $runDir | Out-Null
  $rev = [string](Get-Date).Ticks
  [pscustomobject]@{ port = $Port; rev = $rev } | ConvertTo-Json -Compress | Set-Content $studioTarget
  Start-RojoControl
  return $rev
}

# Cette methode permet d'attendre que le plugin modifie signale sa connexion pour cette cible (meme `rev`, meme port)
# lorsque -AcquireStudio vient de la publier ; renvoie $false apres le delai (plugin officiel, Studio ferme ou en Play).
function Wait-StudioConnected([string]$Rev, [int]$Port, [int]$Seconds = 15) {
  for ($i = 0; $i -lt $Seconds; $i++) {
    $s = try { Get-Content $studioStateFile -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null }
    if ($s -and $s.rev -eq $Rev -and $s.state -eq 'connected' -and $s.port -eq "$Port") { return $true }
    Start-Sleep -Seconds 1
  }
  return $false
}

# Cette methode permet de liberer le verrou Studio lorsqu'il est tenu par la branche courante (fin de verification, -Stop, -Remove) ;
# Studio est alors renvoye vers le checkout principal s'il sert, sinon deconnecte.
function Release-StudioLock {
  Invoke-StudioLocked {
    $lock = Get-StudioLock
    if ($lock -and $lock.branch -eq $Branch) {
      Remove-Item -Force $studioLock
      $mainUp = (Get-UrlCode "http://localhost:$basePort/api/rojo") -eq 200
      [void](Set-StudioTarget $(if ($mainUp) { "$basePort" } else { '' }))
      return $true
    }
    return $false
  }
}

$exists = Test-Path $dir
$currentPort = if (Test-Path $portFile) { [int](Get-Content $portFile) } else { 0 }

if ($StudioStatus) {
  $lock = Get-StudioLock
  Write-Host $(if ($lock) { "Studio reserve par $(Format-StudioLock $lock)." } else { 'Studio libre.' })
  $conn = Get-StudioConnectedPorts
  Write-Host $(if ($conn) { "Studio connecte au(x) port(s) Rojo : $($conn -join ', ')." } else { "Studio n'est connecte a aucun serveur Rojo." })
  return
}

if ($ReleaseStudio) {
  Write-Host $(if (Release-StudioLock) { "Studio libere par '$Branch'." } else { "Studio n'etait pas reserve par '$Branch'." })
  return
}

if ($AcquireStudio) {
  # Sans Rojo, le verrou serait aussitot considere comme abandonne (et Studio n'aurait rien a suivre).
  if (-not (Test-RojoRunning)) { throw "Rojo ne tourne pas pour '$Branch' : lancer d'abord .\scripts\csgo-worktree.ps1 $Branch." }
  $deadline = (Get-Date).AddMinutes($WaitStudio)
  while ($true) {
    $result = Invoke-StudioLocked {
      $lock = Get-StudioLock
      $taken = $null
      if ($lock -and $lock.branch -ne $Branch) {
        $stale = Get-StudioLockStaleReason $lock
        if (-not $stale) { return @{ ok = $false; lock = $lock } }
        $taken = "verrou de $(Format-StudioLock $lock) repris ($stale)"
      }
      New-Item -ItemType Directory -Force $runDir | Out-Null
      $since = if ($lock -and $lock.branch -eq $Branch) { $lock.since } else { Get-Date -Format 'yyyy-MM-dd HH:mm' }
      [pscustomobject]@{ branch = $Branch; port = $currentPort; since = $since } | ConvertTo-Json | Set-Content $studioLock
      $rev = Set-StudioTarget "$currentPort"
      return @{ ok = $true; taken = $taken; rev = $rev }
    }
    if ($result.ok) { break }
    if ((Get-Date) -ge $deadline) {
      Write-Host "Studio occupe par $(Format-StudioLock $result.lock)."
      Write-Host "Continuer le travail sans Studio, puis relancer avec -AcquireStudio (ou -WaitStudio <minutes> pour attendre)."
      exit 2
    }
    Start-Sleep -Seconds 15
  }
  if ($result.taken) { Write-Host "Note : $($result.taken)." }
  Write-Host "Studio reserve pour '$Branch' (port $currentPort). Liberer des la verification finie : -ReleaseStudio."
  if (Wait-StudioConnected $result.rev $currentPort) { Write-Host "Studio connecte au port $currentPort (plugin Rojo CSGO autoconnect)." }
  else {
    $conn = Get-StudioConnectedPorts
    Write-Host "Studio ne s'est pas connecte seul (plugin officiel, Studio ferme ou en Play ? voir tools/rojo-plugin/README.md)."
    $from = if ($conn) { "Disconnect dans le plugin Rojo (connecte au port $($conn -join ', ')), puis " } else { '' }
    Write-Host "Connexion (mode Edit, pas en Play) : $($from)plugin Rojo > port $currentPort > Connect."
  }
  return
}

if ($RegisterThread) {
  Register-Owner $RegisterThread
  Write-Host "Thread $RegisterThread inscrit pour le nettoyage de '$Branch'."
  return
}

if ($Stop -or $Remove) {
  $s = Stop-Rojo $currentPort
  Write-Host $(if ($s) { "Rojo arrete (port $currentPort)." } else { "Aucun Rojo en cours pour '$Branch'." })
  if (Release-StudioLock) { Write-Host "Studio libere par '$Branch'." }
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
Write-Host "  Studio : -AcquireStudio l'y connecte (plugin Rojo CSGO autoconnect), sinon plugin Rojo > port $port > Connect (mode Edit)."
if ($rojoCode -ne 200) { throw "Rojo ne repond pas sur le port $port : voir $logFile." }
