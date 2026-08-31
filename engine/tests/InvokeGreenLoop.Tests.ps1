<#
  Testes do ORQUESTRADOR, nao apenas do modulo.

  Achado 11 da revisao adversarial: a suite importava GenuinoEngine.psm1 e nunca
  chamava Invoke-GreenLoop.ps1. Trocar o orquestrador inteiro por `exit 0`
  passaria verde. Um motor cuja peca central nunca e executada nos testes nao
  esta testado.

  Estes casos rodam o script de verdade, num repositorio git descartavel, sempre
  com -DryRun: o operario nao e chamado e nenhuma cota e gasta. O que se prova
  aqui e o esqueleto -- admissao, baseline, evidencia, limpeza -- que e
  justamente o que nenhum teste cobria.
#>

BeforeAll {
    $script:EngineDir = Split-Path -Parent $PSScriptRoot
    $script:Loop = Join-Path $script:EngineDir 'Invoke-GreenLoop.ps1'
    Import-Module (Join-Path $script:EngineDir 'GenuinoEngine.psm1') -Force

    function New-TestRepo {
        <#
          Repositorio git minimo com o motor dentro, para o orquestrador
          encontrar o modulo pelo caminho relativo que ele espera.
        #>
        param([string]$Root)
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
        & git -C $Root init -q
        & git -C $Root config user.email 'teste@local'
        & git -C $Root config user.name  'teste'
        & git -C $Root config commit.gpgsign false
        New-Item -ItemType Directory -Path (Join-Path $Root 'engine') -Force | Out-Null
        Copy-Item (Join-Path $script:EngineDir 'GenuinoEngine.psm1') (Join-Path $Root 'engine') -Force
        Copy-Item $script:Loop (Join-Path $Root 'engine') -Force
        New-Item -ItemType Directory -Path (Join-Path $Root 'missions') -Force | Out-Null
        'inicial' | Set-Content -LiteralPath (Join-Path $Root 'LEIAME.txt')
        & git -C $Root add -A
        & git -C $Root commit -qm 'base'
        return $Root
    }

    function New-TestMission {
        param([string]$Root, [string]$Name, [string[]]$Lines)
        $path = Join-Path $Root "missions/$Name.md"
        $Lines | Set-Content -LiteralPath $path -Encoding utf8
        return $path
    }

    function Invoke-Loop {
        # Processo separado: o orquestrador chama `exit`, que encerraria o Pester.
        param([string]$Root, [string]$Mission, [string[]]$Extra = @())
        $args = @('-NoProfile', '-NonInteractive', '-File', (Join-Path $Root 'engine/Invoke-GreenLoop.ps1'),
                  '-MissionPath', $Mission, '-RepoRoot', $Root, '-DryRun') + $Extra
        $out = & pwsh @args 2>&1 | Out-String
        return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = $out }
    }

    $script:Sandboxes = [System.Collections.Generic.List[string]]::new()
    function New-Sandbox {
        $p = Join-Path ([IO.Path]::GetTempPath()) "greenloop-e2e-$(Get-Random)"
        $script:Sandboxes.Add($p)
        return (New-TestRepo -Root $p)
    }
}

AfterAll {
    foreach ($s in $script:Sandboxes) {
        & git -C $s worktree prune 2>$null
        Remove-Item -LiteralPath $s -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Orquestrador -- gate de admissao' {

    It 'recusa missao sem os campos obrigatorios, com exit 1' {
        $repo = New-Sandbox
        $m = New-TestMission -Root $repo -Name 'incompleta' -Lines @(
            '# missao incompleta'
            'TEST_CMD: exit 1'
        )
        $r = Invoke-Loop -Root $repo -Mission $m
        $r.ExitCode | Should -Be 1
        $r.Output   | Should -Match 'G0 REPROVOU'
        $r.Output   | Should -Match 'ORACULO'
    }

    It 'recusa arquivo de missao inexistente como nao-medicao' {
        $repo = New-Sandbox
        $r = Invoke-Loop -Root $repo -Mission (Join-Path $repo 'missions/nao-existe.md')
        $r.ExitCode | Should -Be 2
    }

    It 'para quando ha pre-requisito humano e ninguem aprovou' {
        $repo = New-Sandbox
        $m = New-TestMission -Root $repo -Name 'prereq' -Lines @(
            'TEST_CMD: exit 1'
            'FRONTEIRA: local'
            'GATE_DA_FRONTEIRA: NENHUM'
            'PRE_REQUISITOS_HUMANOS: instalar o SDK do Android'
            'ORACULO: NENHUM'
        )
        $r = Invoke-Loop -Root $repo -Mission $m
        $r.ExitCode | Should -Be 1
        $r.Output   | Should -Match 'SDK do Android'
    }
}

Describe 'Orquestrador -- baseline RED' {

    It 'aborta quando o teste JA PASSA no commit-base' {
        # Sem RED confirmado nao ha o que o operario possa provar. Um GREEN
        # posterior seria atribuido a um trabalho que nao causou nada.
        $repo = New-Sandbox
        $m = New-TestMission -Root $repo -Name 'ja-verde' -Lines @(
            'TEST_CMD: exit 0'
            'FRONTEIRA: local'
            'GATE_DA_FRONTEIRA: NENHUM'
            'PRE_REQUISITOS_HUMANOS: NENHUM'
            'ORACULO: NENHUM'
        )
        $r = Invoke-Loop -Root $repo -Mission $m
        $r.ExitCode | Should -Be 2
        $r.Output   | Should -Match 'JA PASSA'
    }

    It 'confirma RED e segue, quando o teste falha no commit-base' {
        $repo = New-Sandbox
        $m = New-TestMission -Root $repo -Name 'red-ok' -Lines @(
            'TEST_CMD: exit 1'
            'FRONTEIRA: local'
            'GATE_DA_FRONTEIRA: NENHUM'
            'PRE_REQUISITOS_HUMANOS: NENHUM'
            'ORACULO: NENHUM'
        )
        $r = Invoke-Loop -Root $repo -Mission $m
        $r.Output   | Should -Match 'baseline: exit=1'
        # DryRun nunca produz GREEN: sem operario nao ha trabalho a atestar.
        $r.ExitCode | Should -Be 2
        $r.Output   | Should -Match 'DryRun'
    }

    It 'DryRun NUNCA devolve exit 0' {
        # Mutante que este caso mata: um orquestrador trocado por `exit 0`.
        $repo = New-Sandbox
        $m = New-TestMission -Root $repo -Name 'dry' -Lines @(
            'TEST_CMD: exit 1'
            'FRONTEIRA: local'
            'GATE_DA_FRONTEIRA: NENHUM'
            'PRE_REQUISITOS_HUMANOS: NENHUM'
            'ORACULO: NENHUM'
        )
        (Invoke-Loop -Root $repo -Mission $m).ExitCode | Should -Not -Be 0
    }
}

Describe 'Orquestrador -- evidencia e limpeza' {

    It 'grava verdict.json com commit-base, hashes e limites' {
        $repo = New-Sandbox
        $m = New-TestMission -Root $repo -Name 'evid' -Lines @(
            'TEST_CMD: exit 1'
            'FRONTEIRA: local'
            'GATE_DA_FRONTEIRA: NENHUM'
            'PRE_REQUISITOS_HUMANOS: NENHUM'
            'ORACULO: tests/, spec/'
        )
        Invoke-Loop -Root $repo -Mission $m | Out-Null

        $verdicts = @(Get-ChildItem (Join-Path $repo 'runs/evid') -Recurse -Filter 'verdict.json')
        $verdicts.Count | Should -BeGreaterThan 0

        $v = Get-Content -LiteralPath $verdicts[0].FullName -Raw | ConvertFrom-Json
        $v.base_commit    | Should -Match '^[0-9a-f]{40}$'
        $v.engine_sha256  | Should -Not -BeNullOrEmpty
        $v.mission_sha256 | Should -Not -BeNullOrEmpty
        $v.oracle_paths   | Should -Contain 'tests/'
        $v.limits.Count   | Should -BeGreaterThan 0
        $v.dry_run        | Should -BeTrue
    }

    It 'grava o exit code do baseline em disco, nao so na tela' {
        $repo = New-Sandbox
        $m = New-TestMission -Root $repo -Name 'meta' -Lines @(
            'TEST_CMD: exit 1'
            'FRONTEIRA: local'
            'GATE_DA_FRONTEIRA: NENHUM'
            'PRE_REQUISITOS_HUMANOS: NENHUM'
            'ORACULO: NENHUM'
        )
        Invoke-Loop -Root $repo -Mission $m | Out-Null
        $metas = @(Get-ChildItem (Join-Path $repo 'runs/meta') -Recurse -Filter 'baseline-g5.log.meta.json')
        $metas.Count | Should -BeGreaterThan 0
        (Get-Content -LiteralPath $metas[0].FullName -Raw | ConvertFrom-Json).exit_code | Should -Be 1
    }

    It 'nao deixa worktree para tras' {
        # Worktree orfao vira lixo silencioso que ninguem nomeia.
        $repo = New-Sandbox
        $m = New-TestMission -Root $repo -Name 'limpo' -Lines @(
            'TEST_CMD: exit 1'
            'FRONTEIRA: local'
            'GATE_DA_FRONTEIRA: NENHUM'
            'PRE_REQUISITOS_HUMANOS: NENHUM'
            'ORACULO: NENHUM'
        )
        Invoke-Loop -Root $repo -Mission $m | Out-Null
        $lista = (& git -C $repo worktree list | Out-String) -split "`r?`n" | Where-Object { $_.Trim() }
        # So o worktree principal deve restar.
        $lista.Count | Should -Be 1
    }

    It 'recusa sobrescrever um diretorio de evidencia existente' {
        $repo = New-Sandbox
        $m = New-TestMission -Root $repo -Name 'colisao' -Lines @(
            'TEST_CMD: exit 1'
            'FRONTEIRA: local'
            'GATE_DA_FRONTEIRA: NENHUM'
            'PRE_REQUISITOS_HUMANOS: NENHUM'
            'ORACULO: NENHUM'
        )
        Invoke-Loop -Root $repo -Mission $m | Out-Null
        $primeiro = @(Get-ChildItem (Join-Path $repo 'runs/colisao') -Directory)[0]
        Invoke-Loop -Root $repo -Mission $m | Out-Null
        # Duas execucoes produzem dois diretorios distintos, nunca um sobrescrito.
        @(Get-ChildItem (Join-Path $repo 'runs/colisao') -Directory).Count | Should -BeGreaterThan 1
        Test-Path -LiteralPath (Join-Path $primeiro.FullName 'verdict.json') | Should -BeTrue
    }
}
