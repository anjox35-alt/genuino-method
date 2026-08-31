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
            'WRITE_SET: src/'
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
            'WRITE_SET: src/'
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
            'WRITE_SET: src/'
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
            'WRITE_SET: src/'
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
            'WRITE_SET: src/'
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
            'WRITE_SET: src/'
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
            'WRITE_SET: src/'
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
            'WRITE_SET: src/'
        )
        Invoke-Loop -Root $repo -Mission $m | Out-Null
        $primeiro = @(Get-ChildItem (Join-Path $repo 'runs/colisao') -Directory)[0]
        Invoke-Loop -Root $repo -Mission $m | Out-Null
        # Duas execucoes produzem dois diretorios distintos, nunca um sobrescrito.
        @(Get-ChildItem (Join-Path $repo 'runs/colisao') -Directory).Count | Should -BeGreaterThan 1
        Test-Path -LiteralPath (Join-Path $primeiro.FullName 'verdict.json') | Should -BeTrue
    }
}

Describe 'Orquestrador -- contrato do operario' {

    It 'aborta quando o ORACULO nao casa nenhum arquivo rastreado' {
        # `git diff -- <pathspec que nao casa nada>` devolve exit 0 e saida vazia.
        # Sem esta validacao, um typo faria o motor logar "oraculo protegido",
        # nao detectar violacao, e gravar oracle_paths no veredito -- evidencia
        # afirmativamente falsa, pior que protecao ausente.
        $repo = New-Sandbox
        $m = New-TestMission -Root $repo -Name 'typo' -Lines @(
            'TEST_CMD: exit 1'
            'FRONTEIRA: local'
            'GATE_DA_FRONTEIRA: NENHUM'
            'PRE_REQUISITOS_HUMANOS: NENHUM'
            'ORACULO: caminho/que/nao/existe/'
            'WRITE_SET: src/'
        )
        $r = Invoke-Loop -Root $repo -Mission $m
        $r.ExitCode | Should -Be 2
        $r.Output   | Should -Match 'nao casa nenhum arquivo rastreado'
    }

    It 'aceita ORACULO que casa arquivo real' {
        $repo = New-Sandbox
        # LEIAME.txt existe no commit-base criado por New-TestRepo.
        $m = New-TestMission -Root $repo -Name 'oraculo-ok' -Lines @(
            'TEST_CMD: exit 1'
            'FRONTEIRA: local'
            'GATE_DA_FRONTEIRA: NENHUM'
            'PRE_REQUISITOS_HUMANOS: NENHUM'
            'ORACULO: LEIAME.txt'
            'WRITE_SET: src/'
        )
        $r = Invoke-Loop -Root $repo -Mission $m
        $r.Output   | Should -Match 'Oraculo validado'
        $r.ExitCode | Should -Be 2   # DryRun sempre para antes de GREEN
    }

    It 'recusa WRITE_SET NENHUM' {
        # Sem allowlist, qualquer arquivo que o operario criar entra na medicao --
        # que e exatamente o furo do conftest.py.
        $repo = New-Sandbox
        $m = New-TestMission -Root $repo -Name 'sem-ws' -Lines @(
            'TEST_CMD: exit 1'
            'FRONTEIRA: local'
            'GATE_DA_FRONTEIRA: NENHUM'
            'PRE_REQUISITOS_HUMANOS: NENHUM'
            'ORACULO: NENHUM'
            'WRITE_SET: NENHUM'
        )
        $r = Invoke-Loop -Root $repo -Mission $m
        $r.ExitCode | Should -Be 1
        $r.Output   | Should -Match 'WRITE_SET nao pode ser NENHUM'
    }

    It 'reprova a admissao quando falta WRITE_SET' {
        $repo = New-Sandbox
        $m = New-TestMission -Root $repo -Name 'falta-ws' -Lines @(
            'TEST_CMD: exit 1'
            'FRONTEIRA: local'
            'GATE_DA_FRONTEIRA: NENHUM'
            'PRE_REQUISITOS_HUMANOS: NENHUM'
            'ORACULO: NENHUM'
        )
        $r = Invoke-Loop -Root $repo -Mission $m
        $r.ExitCode | Should -Be 1
        $r.Output   | Should -Match 'WRITE_SET'
    }
}

Describe 'Allowlist de write-set contra repositorio real' {

    BeforeAll {
        # Reproduz o cenario exato da auditoria: o operario nao toca o oraculo,
        # cria um arquivo AO LADO que o TEST_CMD leria.
        $script:R = New-Sandbox
        New-Item -ItemType Directory -Path (Join-Path $script:R 'src') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:R 'tests') -Force | Out-Null
        'base'          | Set-Content -LiteralPath (Join-Path $script:R 'src/app.txt')
        'assert real'   | Set-Content -LiteralPath (Join-Path $script:R 'tests/oracle.txt')
        & git -C $script:R add -A
        & git -C $script:R commit -qm 'com oraculo'
        $script:Base = (& git -C $script:R rev-parse HEAD).Trim()

        # o operario: trabalha no write-set, adultera o oraculo, e planta o conftest
        'impl'            | Set-Content -LiteralPath (Join-Path $script:R 'src/app.txt')
        'assert SEMPRE OK'| Set-Content -LiteralPath (Join-Path $script:R 'tests/oracle.txt')
        'skip tudo'       | Set-Content -LiteralPath (Join-Path $script:R 'tests/conftest.txt')
        & git -C $script:R add -A
    }

    It 'detecta o conftest plantado FORA do write-set' {
        $fora = @(Get-PathOutsideWriteSet -WorktreePath $script:R -BaseCommit $script:Base -WriteSetPaths @('src/'))
        $fora | Should -Contain 'tests/conftest.txt'
        $fora | Should -Contain 'tests/oracle.txt'
    }

    It 'detecta a adulteracao do oraculo' {
        $v = @(Get-OracleViolation -WorktreePath $script:R -BaseCommit $script:Base -OraclePaths @('tests/oracle.txt'))
        $v | Should -Contain 'tests/oracle.txt'
    }

    It 'o patch carrega SO o write-set -- nem oraculo, nem conftest' {
        $a = New-FilteredPatchArgument -BaseCommit $script:Base -WriteSetPaths @('src/') -OraclePaths @('tests/oracle.txt')
        $patch = (& git -C $script:R @a) | Out-String
        $patch | Should -Match 'src/app.txt'
        # Estes dois sao o achado da auditoria: sob blocklist, o conftest viajava.
        $patch | Should -Not -Match 'conftest'
        $patch | Should -Not -Match 'oracle.txt'
    }

    It 'Test-PathspecMatchesTrackedFile separa caminho real de typo' {
        Test-PathspecMatchesTrackedFile -RepoPath $script:R -Commit $script:Base -Pathspec 'tests/' | Should -BeTrue
        Test-PathspecMatchesTrackedFile -RepoPath $script:R -Commit $script:Base -Pathspec 'test/'  | Should -BeFalse
    }
}

Describe 'Get-PathOutsideWriteSet -- achados da auditoria do Codex' {

    BeforeAll {
        $script:RN = New-Sandbox
        New-Item -ItemType Directory -Path (Join-Path $script:RN 'src')  -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:RN 'fora') -Force | Out-Null
        'conteudo que sai de fora' | Set-Content -LiteralPath (Join-Path $script:RN 'fora/config.txt')
        'base'                     | Set-Content -LiteralPath (Join-Path $script:RN 'src/app.txt')
        & git -C $script:RN add -A
        & git -C $script:RN commit -qm 'antes do rename'
        $script:BaseRN = (& git -C $script:RN rev-parse HEAD).Trim()

        # O operario move um arquivo de FORA do write-set para DENTRO dele.
        # Com deteccao de rename ligada, `git diff --name-only` reporta apenas a
        # pos-imagem `src/config.txt` -- que esta no write-set -- e a delecao em
        # `fora/` desaparece das duas listas.
        & git -C $script:RN mv 'fora/config.txt' 'src/config.txt'
        & git -C $script:RN add -A
    }

    It 'nomeia o lado de FORA de um rename que entra no write-set' {
        $fora = @(Get-PathOutsideWriteSet -WorktreePath $script:RN -BaseCommit $script:BaseRN -WriteSetPaths @('src/'))
        $fora | Should -Contain 'fora/config.txt'
    }

    It 'o git realmente detectaria o rename, se nao fosse --no-renames' {
        # Sem este caso, o teste acima passaria mesmo que o git nunca tivesse
        # casado o rename -- e nao provaria nada sobre a correcao.
        $comDeteccao = (& git -C $script:RN diff --name-only --find-renames $script:BaseRN) -join "`n"
        $comDeteccao | Should -Not -Match 'fora/config.txt'
        $comDeteccao | Should -Match 'src/config.txt'
    }
}

Describe 'Split-GitPathLine' {

    It 'preserva espaco nas pontas: foo, " foo" e "foo " sao tres arquivos' {
        $r = @(Split-GitPathLine -Payload "foo`n foo`nfoo ")
        $r.Count | Should -Be 3
        $r       | Should -Contain ' foo'
        $r       | Should -Contain 'foo '
    }

    It 'remove o CR do CRLF sem tocar o resto do nome' {
        $r = @(Split-GitPathLine -Payload "src/a.txt`r`nsrc/b.txt`r`n")
        $r | Should -Be @('src/a.txt', 'src/b.txt')
    }

    It 'saida vazia ou nula devolve colecao vazia, nao um item em branco' {
        @(Split-GitPathLine -Payload '').Count   | Should -Be 0
        @(Split-GitPathLine -Payload $null).Count | Should -Be 0
    }
}

# A deteccao roda AQUI, no nivel do arquivo, e nao num `BeforeAll`.
#
# No Pester 5 o argumento de `-Skip:` e avaliado na fase de Discovery, que
# acontece ANTES de qualquer `BeforeAll`. Escrito la dentro, a variavel ainda
# era $null na hora da decisao, `-not $null` dava $true, e o caso se pulava em
# TODO sistema operacional -- inclusive no ubuntu, onde ele deveria rodar.
#
# O resultado era a pior forma de teste: verde na matriz inteira, com a
# aparencia de cobertura condicional, sem executar em lugar nenhum.
$script:FsCaseSensitive = $(
    $sonda = Join-Path ([IO.Path]::GetTempPath()) ("GenuinoCaixa-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $sonda -Force | Out-Null
    try {
        'x' | Set-Content -LiteralPath (Join-Path $sonda 'Probe.txt')
        -not (Test-Path -LiteralPath (Join-Path $sonda 'probe.txt'))
    } finally {
        Remove-Item -LiteralPath $sonda -Recurse -Force -ErrorAction SilentlyContinue
    }
)

Describe 'Get-PathOutsideWriteSet -- comparacao sensivel a caixa' {

    BeforeAll {
        $script:RC = New-Sandbox
    }

    # No NTFS, `src/foo.txt` e `SRC/FOO.txt` sao o mesmo arquivo e o cenario nao
    # pode ser montado. A matriz da CI roda ubuntu, onde ele roda de verdade.
    It 'um caminho permitido nao mascara um caminho externo de caixa diferente' -Skip:(-not $script:FsCaseSensitive) {
        New-Item -ItemType Directory -Path (Join-Path $script:RC 'src') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:RC 'SRC') -Force | Out-Null
        'permitido' | Set-Content -LiteralPath (Join-Path $script:RC 'src/foo.txt')
        & git -C $script:RC add -A
        & git -C $script:RC commit -qm 'base caixa'
        $base = (& git -C $script:RC rev-parse HEAD).Trim()

        'alterado' | Set-Content -LiteralPath (Join-Path $script:RC 'src/foo.txt')
        'externo'  | Set-Content -LiteralPath (Join-Path $script:RC 'SRC/FOO.txt')
        & git -C $script:RC add -A

        $fora = @(Get-PathOutsideWriteSet -WorktreePath $script:RC -BaseCommit $base -WriteSetPaths @('src/'))
        # Com `-notcontains` (case-insensitive), 'SRC/FOO.txt' casaria com
        # 'src/foo.txt' da lista de permitidos e sumiria daqui.
        $fora | Should -Contain 'SRC/FOO.txt'
    }

    # Sem este caso, um `-Skip:` sempre-verdadeiro voltaria a passar despercebido:
    # a suite ficaria verde com o caso acima pulado em toda a matriz, exatamente
    # como aconteceu antes desta correcao.
    #
    # `-ForEach` e o caminho pelo qual o Pester leva um valor da fase de
    # Discovery para a de Run. Ler `$script:FsCaseSensitive` direto aqui dentro
    # devolve $null: sao escopos distintos, e foi assim que a primeira versao
    # deste guarda falhou.
    It 'a decisao de pular veio de um booleano, nao de $null' -ForEach @(
        @{ Sonda = $script:FsCaseSensitive }
    ) {
        $Sonda | Should -BeOfType [bool]
    }
}
