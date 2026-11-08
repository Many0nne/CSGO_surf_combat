<#
  Tests de limites des scripts de worktree (csgo-worktree.ps1, csgo-worktree-cleanup.ps1), dans un bac a sable jetable
  (voir Sandbox.psm1). Chaque test decrit le comportement attendu : un echec signale un bug, pas un test a ajuster.
  Lancement (Windows, pwsh 7, Pester 3.4 livre avec Windows), depuis la racine du depot ou d'un worktree :
    Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester tests/scripts
  Les tests qui demarrent un faux Rojo ou declarent un pid passent -Slot >= 600 pour rester loin des ports reels.
#>
Import-Module (Join-Path $PSScriptRoot 'Sandbox.psm1') -Force

Describe 'csgo-worktree.ps1 : cycle nominal' {
  $sb = New-Sandbox
  Set-FakeT3 $sb -Sessions @{ 'S-nom' = 'T-nom' } -Threads @{ 'T-nom' = 'active' }
  $p = Get-SbPaths $sb 'feature/1-nominal'

  It 'cree le worktree, reserve le port du slot et inscrit le thread T3' {
    $r = Invoke-Wt $sb @('feature/1-nominal', '-NoUp', '-Slot', '600') 'S-nom'
    $r.Code | Should Be 0
    $p.Dir | Should Exist
    (Get-Content $p.Port) | Should Be '35472'
    $entry = Get-SbOwners $sb | Where-Object { $_.branch -eq 'feature/1-nominal' }
    @($entry.threads) -contains 'T-nom' | Should Be $true
  }

  It 'est idempotent : relance sur le meme worktree garde le slot' {
    $r = Invoke-Wt $sb @('feature/1-nominal', '-NoUp') 'S-nom'
    $r.Code | Should Be 0
    (Get-Content $p.Port) | Should Be '35472'
  }

  It 'demarre Rojo et repond 200, puis -Stop l''arrete' {
    $r = Invoke-Wt $sb @('feature/1-nominal') 'S-nom'
    $r.Output | Should Match 'OK \(200\)'
    $rojoPid = [int](Get-Content $p.Pid)
    (Invoke-Wt $sb @('feature/1-nominal', '-Stop')).Code | Should Be 0
    Start-Sleep -Milliseconds 500
    Test-Alive $rojoPid | Should Be $false
  }

  It 'refuse -Remove avec des modifications non commitees' {
    Set-Content (Join-Path $p.Dir 'brouillon.txt') 'x'
    (Invoke-Wt $sb @('feature/1-nominal', '-Remove')).Code | Should Not Be 0
    $p.Dir | Should Exist
    Remove-Item (Join-Path $p.Dir 'brouillon.txt')
  }

  It '-Remove supprime le worktree, le port et l''entree du registre' {
    (Invoke-Wt $sb @('feature/1-nominal', '-Remove')).Code | Should Be 0
    $p.Dir | Should Not Exist
    $p.Port | Should Not Exist
    @(Get-SbOwners $sb | Where-Object { $_.branch -eq 'feature/1-nominal' }).Count | Should Be 0
  }

  It 'accepte une branche avec des accents' {
    $r = Invoke-Wt $sb @('feature/2-réglages', '-NoUp', '-Slot', '601')
    $r.Code | Should Be 0
    (Get-SbPaths $sb 'feature/2-réglages').Dir | Should Exist
  }

  Remove-Sandbox $sb
}

Describe 'csgo-worktree.ps1 : entrees qui se chevauchent ou echouent' {
  $sb = New-Sandbox
  Set-FakeT3 $sb -Sessions @{ 'S-c' = 'T-c' } -Threads @{ 'T-c' = 'active' }

  It 'deux branches au meme slug : -Remove de l''une ne supprime pas le worktree de l''autre' {
    (Invoke-Wt $sb @('feature/a-b', '-NoUp', '-Slot', '602')).Code | Should Be 0
    Invoke-Wt $sb @('feature-a/b', '-Remove') | Out-Null
    (Get-SbPaths $sb 'feature/a-b').Dir | Should Exist
  }

  It 'une creation qui echoue (base inexistante) ne laisse ni port reserve ni entree au registre' {
    $r = Invoke-Wt $sb @('feature/3-base', '-Base', 'nexistepas', '-NoUp', '-Slot', '603') 'S-c'
    $r.Code | Should Not Be 0
    (Get-SbPaths $sb 'feature/3-base').Port | Should Not Exist
    @(Get-SbOwners $sb | Where-Object { $_.branch -eq 'feature/3-base' }).Count | Should Be 0
  }

  It 'un registre .owners.json illisible ne bloque pas la creation d''un worktree' {
    $p = Get-SbPaths $sb 'feature/4-registre'
    New-Item -ItemType Directory -Force (Split-Path $p.Owners) | Out-Null
    Set-Content $p.Owners '[{"branch": "feature/x", tronque'
    $r = Invoke-Wt $sb @('feature/4-registre', '-NoUp', '-Slot', '604') 'S-c'
    $r.Code | Should Be 0
    $p.Dir | Should Exist
  }

  Remove-Sandbox $sb
}

# Issue #111 : l'inscription plantait (« propriete sessions introuvable ») selon la forme du registre ou le shell.
Describe 'csgo-worktree.ps1 : inscription quelle que soit la forme du registre' {
  $sb = New-Sandbox
  Set-FakeT3 $sb -Sessions @{ 'S-r' = 'T-r' } -Threads @{ 'T-r' = 'active' }
  $owners = (Get-SbPaths $sb 'x').Owners
  New-Item -ItemType Directory -Force (Split-Path $owners) | Out-Null
  $hasPs5 = [bool](Get-Command powershell -ErrorAction SilentlyContinue)

  It 'registre vide : la session est inscrite, sans entree nulle' {
    Set-Content $owners ''
    (Invoke-Wt $sb @('feature/5-vide', '-NoUp', '-Slot', '620') 'S-r').Code | Should Be 0
    $all = @(Get-SbOwners $sb)
    $all.Count | Should Be 1
    @($all[0].sessions) -contains 'S-r' | Should Be $true
  }

  It 'entree sans propriete sessions (ancien format) : la session est ajoutee, les threads gardes' {
    Set-Content $owners '[{"branch":"feature/6-ancien","threads":["T-old"]}]'
    (Invoke-Wt $sb @('feature/6-ancien', '-NoUp', '-Slot', '621') 'S-r').Code | Should Be 0
    $entry = Get-SbOwners $sb | Where-Object { $_.branch -eq 'feature/6-ancien' }
    @($entry.sessions) -contains 'S-r' | Should Be $true
    @($entry.threads) -contains 'T-old' | Should Be $true
    @($entry.threads) -contains 'T-r' | Should Be $true
  }

  It 'Windows PowerShell 5.1, branche deja inscrite : la relance reussit' {
    if (-not $hasPs5) { return }
    Set-Content $owners '[{"branch":"feature/7-ps5","sessions":["S-a"],"threads":[]},{"branch":"feature/autre","sessions":[],"threads":[]}]'
    $r = Invoke-Wt $sb @('feature/7-ps5', '-NoUp', '-Slot', '622') 'S-r' 'powershell'
    $r.Output | Should Not Match 'sessions'
    $r.Code | Should Be 0
    $entry = Get-SbOwners $sb | Where-Object { $_.branch -eq 'feature/7-ps5' }
    @($entry.sessions) -contains 'S-a' | Should Be $true
    @($entry.sessions) -contains 'S-r' | Should Be $true
  }

  It 'Windows PowerShell 5.1, nouvelle branche : les entrees existantes restent intactes' {
    if (-not $hasPs5) { return }
    Set-Content $owners '[{"branch":"feature/autre","sessions":["S-a"],"threads":[]}]'
    (Invoke-Wt $sb @('feature/8-ps5', '-NoUp', '-Slot', '623') 'S-r' 'powershell').Code | Should Be 0
    $branches = @(Get-SbOwners $sb | ForEach-Object { $_.branch })
    ($branches -join ',') | Should Be 'feature/autre,feature/8-ps5'
  }

  Remove-Sandbox $sb
}

Describe 'csgo-worktree.ps1 : creations simultanees (plusieurs agents)' {
  $sb = New-Sandbox
  $branches = 1..4 | ForEach-Object { "feature/5$_-parallele" }
  $sessions = @{}; $threads = @{}
  foreach ($i in 1..4) { $sessions["S-p$i"] = "T-p$i"; $threads["T-p$i"] = 'active' }
  Set-FakeT3 $sb -Sessions $sessions -Threads $threads
  $results = Invoke-WtParallel $sb @(1..4 | ForEach-Object { @{ Args = @($branches[$_ - 1], '-NoUp'); Session = "S-p$_" } })

  It 'les quatre creations reussissent' {
    @($results | Where-Object { $_.Code -ne 0 }).Count | Should Be 0
  }

  It 'chaque worktree recoit un port different' {
    $ports = @($branches | ForEach-Object { $f = (Get-SbPaths $sb $_).Port; if (Test-Path $f) { Get-Content $f } })
    @($ports | Select-Object -Unique).Count | Should Be 4
  }

  It 'le registre garde les quatre branches' {
    $known = @(Get-SbOwners $sb | ForEach-Object { $_.branch })
    @($branches | Where-Object { $_ -notin $known }).Count | Should Be 0
  }

  Remove-Sandbox $sb
}

Describe 'csgo-worktree.ps1 : pid recycle par Windows (apres un redemarrage)' {
  $sb = New-Sandbox
  $p = Get-SbPaths $sb 'feature/6-pid'
  (Invoke-Wt $sb @('feature/6-pid', '-NoUp', '-Slot', '605')).Code | Out-Null

  It '-Stop ne tue pas un processus sans rapport qui a recupere le pid de l''ancien Rojo' {
    $dummy = Start-Dummy $sb
    Set-Content $p.Pid $dummy
    Invoke-Wt $sb @('feature/6-pid', '-Stop') | Out-Null
    Test-Alive $dummy | Should Be $true
  }

  It 'le demarrage relance Rojo meme si le pid enregistre appartient a un autre processus' {
    $dummy = Start-Dummy $sb
    Set-Content $p.Pid $dummy
    $r = Invoke-Wt $sb @('feature/6-pid')
    $r.Output | Should Match 'OK \(200\)'
  }

  Remove-Sandbox $sb
}

Describe 'csgo-worktree.ps1 : verrou Studio' {
  $sb = New-Sandbox
  Set-FakeT3 $sb -Sessions @{ 'S-a' = 'T-a'; 'S-b' = 'T-b' } -Threads @{ 'T-a' = 'active'; 'T-b' = 'active' }
  $a = Get-SbPaths $sb 'feature/7-studio-a'
  $b = Get-SbPaths $sb 'feature/7-studio-b'
  Invoke-Wt $sb @('feature/7-studio-a', '-NoUp', '-Slot', '606') 'S-a' | Out-Null
  Invoke-Wt $sb @('feature/7-studio-b', '-NoUp', '-Slot', '607') 'S-b' | Out-Null
  # Rojo simule par un processus vivant : seul le pid compte pour le verrou.
  $rojoA = Start-Dummy $sb; Set-Content $a.Pid $rojoA
  $rojoB = Start-Dummy $sb; Set-Content $b.Pid $rojoB

  It 'reserve Studio pour la premiere branche' {
    (Invoke-Wt $sb @('feature/7-studio-a', '-AcquireStudio')).Code | Should Be 0
    (Get-Content $a.Lock -Raw | ConvertFrom-Json).branch | Should Be 'feature/7-studio-a'
  }

  It 'refuse la seconde branche (code 2) tant que la premiere est active' {
    (Invoke-Wt $sb @('feature/7-studio-b', '-AcquireStudio')).Code | Should Be 2
  }

  It 'reprend le verrou quand le Rojo du detenteur est mort' {
    Stop-Process -Id $rojoA -Force; Start-Sleep -Milliseconds 300
    $r = Invoke-Wt $sb @('feature/7-studio-b', '-AcquireStudio')
    $r.Code | Should Be 0
    $r.Output | Should Match 'repris'
  }

  It 'reprend le verrou quand les threads du detenteur sont termines' {
    Set-FakeT3 $sb -Sessions @{ 'S-a' = 'T-a'; 'S-b' = 'T-b' } -Threads @{ 'T-a' = 'active'; 'T-b' = 'settled' }
    $rojoA2 = Start-Dummy $sb; Set-Content $a.Pid $rojoA2
    (Invoke-Wt $sb @('feature/7-studio-a', '-AcquireStudio')).Code | Should Be 0
  }

  It 'un verrou illisible est considere comme libre' {
    Set-Content $a.Lock '{tronque'
    (Invoke-Wt $sb @('feature/7-studio-b', '-AcquireStudio')).Code | Should Be 0
  }

  It '-ReleaseStudio d''une autre branche ne libere pas le verrou' {
    Invoke-Wt $sb @('feature/7-studio-a', '-ReleaseStudio') | Out-Null
    (Get-Content $a.Lock -Raw | ConvertFrom-Json).branch | Should Be 'feature/7-studio-b'
  }

  Remove-Sandbox $sb
}

Describe 'csgo-worktree-cleanup.ps1 : decisions' {
  $sb = New-Sandbox
  $threads = @{ 'T-act' = 'active'; 'T-fin' = 'settled'; 'T-mrg' = 'settled'; 'T-unp' = 'archived'; 'T-clo' = 'settled'; 'T-off' = 'active' }
  $sessions = @{}; foreach ($t in $threads.Keys) { $sessions["S$($t.Substring(1))"] = $t }
  Set-FakeT3 $sb -Sessions $sessions -Threads $threads
  $slot = 610
  $pidOf = @{}
  foreach ($k in 'act', 'fin', 'mrg', 'unp', 'clo', 'off') {
    Invoke-Wt $sb @("feature/8-$k", '-NoUp', '-Slot', "$slot") "S-$k" | Out-Null
    $slot++
    $pidOf[$k] = Start-Dummy $sb
    Set-Content (Get-SbPaths $sb "feature/8-$k").Pid $pidOf[$k]
  }
  $shaMrg = Add-SbCommit $sb 'feature/8-mrg' -Push
  $shaUnp = Add-SbCommit $sb 'feature/8-unp' -Push
  Add-SbCommit $sb 'feature/8-unp' 'oubli.txt' | Out-Null
  $shaClo = Add-SbCommit $sb 'feature/8-clo' -Push
  Set-FakeGh $sb -Prs @{
    'feature/8-mrg' = @(@{ number = 1; state = 'MERGED'; headRefOid = $shaMrg })
    'feature/8-unp' = @(@{ number = 2; state = 'MERGED'; headRefOid = $shaUnp })
    'feature/8-clo' = @(@{ number = 3; state = 'CLOSED'; headRefOid = $shaClo })
  }
  # Panne du helper T3 : 'off' a un thread actif, mais le helper ne repond plus au moment du nettoyage.
  $cleanup = $null

  It 'le nettoyage se termine sans erreur' {
    $script:cleanup = Invoke-Cleanup $sb
    $script:cleanup.Code | Should Be 0
  }

  It 'thread actif : Rojo garde' { Test-Alive $pidOf['act'] | Should Be $true }
  It 'thread termine, pas de PR : Rojo arrete, worktree garde' {
    Test-Alive $pidOf['fin'] | Should Be $false
    (Get-SbPaths $sb 'feature/8-fin').Dir | Should Exist
  }
  It 'PR mergee, tout pousse : worktree et branche locale supprimes' {
    (Get-SbPaths $sb 'feature/8-mrg').Dir | Should Not Exist
    (git -C $sb.Repo branch --list 'feature/8-mrg') | Should BeNullOrEmpty
  }
  It 'PR mergee mais commit non pousse : worktree garde' {
    (Get-SbPaths $sb 'feature/8-unp').Dir | Should Exist
  }
  It 'PR fermee sans merge : worktree supprime, branche locale gardee' {
    (Get-SbPaths $sb 'feature/8-clo').Dir | Should Not Exist
    (git -C $sb.Repo branch --list 'feature/8-clo') | Should Not BeNullOrEmpty
  }

  It 'helper T3 en panne : aucun Rojo d''un thread actif n''est arrete' {
    Set-FakeT3 $sb -Fail
    Invoke-Cleanup $sb | Out-Null
    Test-Alive $pidOf['off'] | Should Be $true
    Test-Alive $pidOf['act'] | Should Be $true
  }

  It 'gh en panne : rien n''est supprime' {
    Set-FakeT3 $sb -Sessions $sessions -Threads $threads
    Set-FakeGh $sb -Fail
    Invoke-Cleanup $sb | Out-Null
    (Get-SbPaths $sb 'feature/8-unp').Dir | Should Exist
  }

  It 'registre illisible : le nettoyage le signale dans son journal' {
    $p = Get-SbPaths $sb 'feature/8-act'
    Set-Content $p.Owners '[{"branch": tronque'
    Invoke-Cleanup $sb | Out-Null
    (Test-Path $p.Log) -and ((Get-Content $p.Log -Raw) -match 'owners') | Should Be $true
  }

  Remove-Sandbox $sb
}
