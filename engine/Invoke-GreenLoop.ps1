<#
.SYNOPSIS
  Green loop: o operario escreve num worktree, o motor mede noutro.

.DESCRIPTION
  Orquestrador do metodo gerente/operario.

  A decisao central deste desenho: quem escreve e onde se mede sao lugares
  diferentes.

      worktree-trabalho   o operario escreve aqui (sandbox workspace-write)
      worktree-medicao    os gates rodam aqui (o operario nunca teve acesso)

  A primeira versao usava um worktree so, e uma revisao adversarial mostrou por
  que isso nao sustenta veredito: o operario tinha escrita sobre o proprio
  oraculo. "Nao altere os testes" existia apenas no prompt. Um operario que
  enfraquecesse o teste de aceitacao produziria diff nao vazio, gates verdes e
  GREEN legitimo aos olhos do motor.

  O sandbox do Codex protege `.git`, `.agents` e `.codex` de forma nativa, mas
  nao ha forma documentada de declarar caminhos protegidos adicionais. Entao a
  protecao acontece aqui, e por ALLOWLIST: o patch contem exatamente os caminhos
  declarados em WRITE_SET, e nada mais.

  A versao anterior fazia o inverso -- incluia tudo e excluia o oraculo. Uma
  auditoria derrubou isso: o operario nao precisava tocar o oraculo, bastava
  criar um `conftest.py` AO LADO dele. Nao e caminho de oraculo, viaja no patch,
  desabilita a suite inteira. Blocklist exigiria antecipar todo arquivo que o
  TEST_CMD pudesse ler; allowlist nao precisa antecipar nada.

  Escrever fora do WRITE_SET, ou tocar o ORACULO, REPROVA a iteracao. Antes era
  apenas anotado, e o loop seguia -- o que tornava a violacao gratuita.

  CONTRATO DE TRES FAIXAS:
      0    passou
      1    reprovacao medida  -- consome iteracao, realimenta o operario
      >=2  nao foi possivel medir -- ambiente; NAO consome iteracao, aborta

.PARAMETER MissionPath
  Missao com TEST_CMD, FRONTEIRA, GATE_DA_FRONTEIRA, PRE_REQUISITOS_HUMANOS,
  ORACULO e WRITE_SET.

.PARAMETER HumanApproved
  Registra que um humano dispensou os pre-requisitos. E DECISAO, nunca fato.

.PARAMETER DryRun
  Roda o ciclo sem chamar o operario. Nunca produz GREEN: sem operario nao ha
  trabalho a atestar.

.OUTPUTS
  Exit 0 GREEN, 1 RED, 2 nao foi possivel medir.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$MissionPath,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateRange(1, 20)] [int]$MaxIterations = 5,
    [ValidateRange(30, 3600)] [int]$OperatorTimeoutSeconds = 420,
    [ValidateRange(10, 3600)] [int]$GateTimeoutSeconds = 600,
    [switch]$HumanApproved,
    [switch]$KeepWorktree,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'GenuinoEngine.psm1') -Force

$EXIT_GREEN = 0; $EXIT_RED = 1; $EXIT_UNKNOWN = 2

$script:state = [ordered]@{
    verdict   = 'RED'
    exitCode  = $EXIT_RED
    consumed  = 0
    worktrees = @()
    notes     = [System.Collections.Generic.List[string]]::new()
}

function Write-Log { param([string]$m) Write-Host "[$((Get-Date).ToUniversalTime().ToString('HH:mm:ss'))] $m" }

function Stop-Loop {
    param([int]$Code, [string]$Message, [string]$Verdict = 'ESCALAR')
    $script:state.verdict = $Verdict
    $script:state.exitCode = $Code
    Write-Log $Message
    throw [System.OperationCanceledException]::new($Message)
}

function Invoke-Git {
    param([string]$Dir, [string[]]$Arguments)
    $git = Resolve-ExternalCommand -Name 'git'
    if (-not $git) { Stop-Loop $EXIT_UNKNOWN 'git nao encontrado no PATH.' }
    return Invoke-ClosedStdinProcess -FilePath $git -WorkingDirectory $Dir -ArgumentList $Arguments
}

function Assert-Git {
    # Exit code de git nunca e ignorado. Uma mensagem `fatal: ...` gravada como
    # se fosse patch faz um GREEN sobreviver sem prova nenhuma.
    param([string]$Dir, [string[]]$Arguments, [string]$What)
    $r = Invoke-Git -Dir $Dir -Arguments $Arguments
    if (-not $r.Launched -or $r.ExitCode -ne 0) {
        Stop-Loop $EXIT_UNKNOWN "Falha em $What (exit $($r.ExitCode)): $($r.Output)"
    }
    return $r
}

function New-Worktree {
    param([string]$Path, [string]$Branch, [string]$Commit)
    Assert-Git -Dir $RepoRoot -What "criar worktree $Branch" `
        -Arguments @('worktree', 'add', '-b', $Branch, $Path, $Commit) | Out-Null
    $script:state.worktrees += @{ Path = $Path; Branch = $Branch }
}

function Remove-AllWorktrees {
    if ($KeepWorktree) { $script:state.notes.Add('Worktrees mantidos por -KeepWorktree.'); return }
    foreach ($wt in $script:state.worktrees) {
        $r = Invoke-Git -Dir $RepoRoot -Arguments @('worktree', 'remove', '--force', $wt.Path)
        # Falha de limpeza e registrada, nunca engolida: um worktree orfao que
        # ninguem nomeia vira lixo silencioso na maquina.
        if (-not $r.Launched -or $r.ExitCode -ne 0) {
            $script:state.notes.Add("Worktree nao removido: $($wt.Path) (exit $($r.ExitCode))")
        }
        Invoke-Git -Dir $RepoRoot -Arguments @('branch', '-D', $wt.Branch) | Out-Null
    }
}

# ---------------------------------------------------------------------------
# G0 -- admissao
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $MissionPath -PathType Leaf)) {
    Write-Log "Missao nao encontrada: $MissionPath"; exit $EXIT_UNKNOWN
}

$missionFile = (Resolve-Path -LiteralPath $MissionPath).Path
$missionText = Get-Content -LiteralPath $missionFile -Raw -Encoding utf8
$mission     = Read-Mission -Path $missionFile
$missionId   = [IO.Path]::GetFileNameWithoutExtension($missionFile)

$admission = Test-MissionAdmission -Mission $mission -HumanApproved:$HumanApproved
if (-not $admission.Admitted) {
    Write-Log 'G0 REPROVOU. O loop nao comeca.'
    foreach ($reason in $admission.Reasons) { Write-Log "  $reason" }
    exit $admission.ExitCode
}

$codexPath = if ($DryRun) { 'codex' } else { Resolve-ExternalCommand -Name 'codex' }
if (-not $DryRun -and -not $codexPath) {
    Write-Log "Executavel 'codex' nao encontrado. Instale com: npm install -g @openai/codex"
    exit $EXIT_UNKNOWN
}

$testCmd      = $mission['TEST_CMD']
$boundaryGate = $mission['GATE_DA_FRONTEIRA']
$oraclePaths  = @(ConvertTo-OraclePath -Declaration $mission['ORACULO'])
$writeSet     = @(ConvertTo-OraclePath -Declaration $mission['WRITE_SET'])

if ($writeSet.Count -eq 0) {
    Write-Log "G0 REPROVOU: WRITE_SET nao pode ser NENHUM. Sem allowlist, qualquer arquivo que o operario criar entra na medicao."
    exit $EXIT_RED
}

# Contar caminhos nao basta: `:`, `:!tests/` e `:(attr:x)` passam pela contagem
# e nao restringem nada -- o primeiro seleciona tudo, o segundo recria a
# blocklist, o terceiro muda de significado quando `.gitattributes` muda.
foreach ($path in ($writeSet + $oraclePaths)) {
    if (-not (Test-PositiveLiteralPathspec -Pathspec $path)) {
        Write-Log "G0 REPROVOU: '$path' nao e um caminho positivo e literal."
        Write-Log "  Allowlist nao aceita magia de pathspec do git (':', ':!', ':(attr:...)') nem curinga."
        exit $EXIT_RED
    }
}

Write-Log "G0 admitiu '$missionId'."
Write-Log "  write-set: $($writeSet -join ', ')"
Write-Log "  oraculo:   $(if ($oraclePaths) { $oraclePaths -join ', ' } else { 'NENHUM (declarado)' })"
if ($admission.HumanDecision) {
    Write-Log 'G0: pre-requisitos dispensados por DECISAO humana. Este motor nao verificou nada disso.'
}

# ---------------------------------------------------------------------------
# Evidencia
# ---------------------------------------------------------------------------

$runId  = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmss.fffZ')
$runDir = Join-Path $RepoRoot "runs/$missionId/$runId"
if (Test-Path -LiteralPath $runDir) {
    Write-Log "Diretorio de evidencia ja existe: $runId. Abortado para nao sobrescrever."; exit $EXIT_UNKNOWN
}
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
Write-Log "Evidencia: $runDir"

$workTree = Join-Path ([IO.Path]::GetTempPath()) "genuino-work-$missionId-$runId"
$measTree = Join-Path ([IO.Path]::GetTempPath()) "genuino-meas-$missionId-$runId"

# Envolve TUDO: qualquer excecao nao prevista vira exit 2, nunca 1. Publicar 1
# para uma impossibilidade de medir seria mentir no contrato externo.
try {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) {
        Stop-Loop $EXIT_UNKNOWN "RepoRoot nao e um repositorio git: $RepoRoot"
    }

    # Commit-base congelado. Todo diff e toda deteccao de violacao comparam com
    # ele, nunca com um HEAD que pode ter se movido durante a execucao.
    $baseCommit = (Assert-Git -Dir $RepoRoot -Arguments @('rev-parse', 'HEAD') -What 'ler HEAD').Output.Trim()
    Write-Log "Commit-base congelado: $baseCommit"

    # Cada caminho do oraculo precisa casar um arquivo que existe de verdade.
    #
    # `git diff -- <pathspec que nao casa nada>` devolve exit 0 e saida vazia. Um
    # `ORACULO: test/` quando os testes vivem em `tests/` passaria por todo o
    # mecanismo em silencio: nenhuma violacao detectada, e o veredito gravaria
    # `oracle_paths: ["test/"]` como se algo estivesse protegido. Evidencia
    # afirmativamente falsa e pior que protecao ausente.
    foreach ($path in $oraclePaths) {
        if (-not (Test-PathspecMatchesTrackedFile -RepoPath $RepoRoot -Commit $baseCommit -Pathspec $path)) {
            Stop-Loop $EXIT_UNKNOWN "ORACULO declara '$path', que nao casa nenhum arquivo rastreado em $($baseCommit.Substring(0,7)). Corrija a declaracao: o motor nao protege o que nao encontra."
        }
    }
    if ($oraclePaths.Count -gt 0) {
        Write-Log "Oraculo validado: os $($oraclePaths.Count) caminho(s) casam arquivos rastreados."
    }

    New-Worktree -Path $workTree -Branch "wt-work/$missionId-$runId" -Commit $baseCommit
    New-Worktree -Path $measTree -Branch "wt-meas/$missionId-$runId" -Commit $baseCommit

    # --- baseline RED -----------------------------------------------------
    # Os gates rodam no worktree limpo ANTES de delegar. Se ja passam, nao ha o
    # que o operario possa provar, e qualquer GREEN posterior seria atribuido a
    # um trabalho que nao causou nada.
    Write-Log '=== baseline: medindo o estado ANTES de delegar ==='
    $baseline = Invoke-Gate -Name 'baseline-G5' -Command $testCmd -WorkingDirectory $measTree `
        -LogPath (Join-Path $runDir 'baseline-g5.log') -TimeoutSeconds $GateTimeoutSeconds
    Write-Log "  baseline: exit=$($baseline.ExitCode) [$($baseline.Status)]"

    if ($baseline.ExitCode -eq 0) {
        Stop-Loop $EXIT_UNKNOWN 'ABORTADO: o teste de aceitacao JA PASSA no commit-base. RED nao confirmado; nao ha o que delegar.'
    }
    if (-not (Test-IterationConsumed -ExitCode $baseline.ExitCode)) {
        Stop-Loop $EXIT_UNKNOWN "ABORTADO: o baseline nao pode ser medido (exit $($baseline.ExitCode))."
    }

    if ($DryRun) {
        $script:state.notes.Add('DryRun: o operario nao foi chamado; nenhum GREEN e possivel.')
        Stop-Loop $EXIT_UNKNOWN 'DryRun concluido: admissao e baseline verificados, sem delegacao.' 'DRY_RUN'
    }

    # --- loop -------------------------------------------------------------
    $failureLog = ''
    while ($script:state.consumed -lt $MaxIterations) {
        $iteration = $script:state.consumed + 1
        $iterDir = Join-Path $runDir "iter$iteration"
        New-Item -ItemType Directory -Path $iterDir -Force | Out-Null
        Write-Log "=== iteracao $iteration/$MaxIterations ==="

        $prompt = New-OperatorPrompt -MissionText $missionText -Iteration $iteration -FailureLog $failureLog
        Set-Content -LiteralPath (Join-Path $iterDir 'operator-prompt.txt') -Value $prompt -Encoding utf8

        Write-Log 'Delegando ao operario (codex exec, workspace-write).'
        $operator = Invoke-ClosedStdinProcess -FilePath $codexPath -WorkingDirectory $RepoRoot `
            -StdinContent $prompt -TimeoutSeconds $OperatorTimeoutSeconds `
            -ArgumentList @('exec', '-C', $workTree, '--sandbox', 'workspace-write', '-')
        Set-Content -LiteralPath (Join-Path $iterDir 'operator.log') -Value $operator.Output -Encoding utf8
        Write-Log "codex exec exit=$($operator.ExitCode) launched=$($operator.Launched)"

        # Exit nao zero do operario e falha de delegacao, nao trabalho reprovado.
        if (-not $operator.Launched -or $operator.TimedOut -or $operator.ExitCode -ne 0) {
            Stop-Loop $EXIT_UNKNOWN "ABORTADO: o operario nao completou (launched=$($operator.Launched) timeout=$($operator.TimedOut) exit=$($operator.ExitCode)). Iteracao nao consumida."
        }

        # --- congela o estado ANTES de medir ------------------------------
        Assert-Git -Dir $workTree -Arguments @('add', '-A') -What 'preparar o worktree de trabalho' | Out-Null

        # --- contrato do operario: oraculo intocado, escrita dentro do write-set
        #
        # Antes isto era apenas anotado e o loop seguia -- entao adulterar o
        # oraculo era gratuito: nao custava iteracao, nao reprovava, e o GREEN
        # continuava possivel. Um operario mal-alinhado descobre o caminho barato
        # rapido. Violacao agora REPROVA.
        $violation = @(Get-OracleViolation -WorktreePath $workTree -BaseCommit $baseCommit -OraclePaths $oraclePaths)
        $outside   = @(Get-PathOutsideWriteSet -WorktreePath $workTree -BaseCommit $baseCommit -WriteSetPaths $writeSet)

        # O sentinela de nao-medicao nao pode virar acusacao: se o git falhou, o
        # motor nao sabe se houve violacao, e run nao verificavel nao e atestavel.
        $indeterminado = @(($violation + $outside) | Where-Object { $_ -like '<INDETERMINADO:*' })
        if ($indeterminado.Count -gt 0) {
            Stop-Loop $EXIT_UNKNOWN "ABORTADO: nao foi possivel verificar o contrato do operario. $($indeterminado[0])"
        }

        if ($violation.Count -gt 0 -or $outside.Count -gt 0) {
            Set-Content -LiteralPath (Join-Path $iterDir 'VIOLACAO-DE-CONTRATO.txt') -Encoding utf8 -Value (
                @('O operario violou o contrato da missao.', '') +
                $(if ($violation.Count) { @('Alterou o ORACULO:') + $violation + '' }) +
                $(if ($outside.Count)   { @('Escreveu FORA do WRITE_SET:') + $outside + '' }) +
                @('Nenhuma dessas alteracoes foi medida. A iteracao reprova.'))
            $resumo = @()
            if ($violation.Count) { $resumo += "oraculo: $($violation -join ', ')" }
            if ($outside.Count)   { $resumo += "fora do write-set: $($outside -join ', ')" }
            $script:state.consumed = $iteration
            Stop-Loop $EXIT_RED "REPROVADO na iteracao ${iteration}: violacao de contrato ($($resumo -join ' | '))." 'RED'
        }

        $patchArgs = New-FilteredPatchArgument -BaseCommit $baseCommit -WriteSetPaths $writeSet -OraclePaths $oraclePaths
        $patch = Assert-Git -Dir $workTree -Arguments $patchArgs -What 'gerar o patch filtrado'
        $patchFile = Join-Path $iterDir 'operator.patch'
        Set-Content -LiteralPath $patchFile -Value $patch.Output -Encoding utf8 -NoNewline

        if ([string]::IsNullOrWhiteSpace($patch.Output)) {
            Stop-Loop $EXIT_UNKNOWN 'ABORTADO: o operario nao produziu alteracao fora do oraculo. Nada a medir.'
        }

        # --- mede no worktree limpo ---------------------------------------
        Assert-Git -Dir $measTree -Arguments @('reset', '--hard', $baseCommit) -What 'restaurar o worktree de medicao' | Out-Null
        Assert-Git -Dir $measTree -Arguments @('clean', '-fdx') -What 'limpar o worktree de medicao' | Out-Null
        Assert-Git -Dir $measTree -Arguments @('apply', '--whitespace=nowarn', $patchFile) -What 'aplicar o patch do operario' | Out-Null

        $gates = @(
            Invoke-Gate -Name 'G5-testes' -Command $testCmd -WorkingDirectory $measTree `
                -LogPath (Join-Path $iterDir 'g5-testes.log') -TimeoutSeconds $GateTimeoutSeconds
        )
        if ($boundaryGate -ne 'NENHUM') {
            $gates += Invoke-Gate -Name 'G0-fronteira' -Command $boundaryGate -WorkingDirectory $measTree `
                -LogPath (Join-Path $iterDir 'g0-fronteira.log') -TimeoutSeconds $GateTimeoutSeconds
        }
        foreach ($g in $gates) { Write-Log "  $($g.Name): exit=$($g.ExitCode) [$($g.Status)]" }

        $unmeasurable = @($gates | Where-Object { -not (Test-IterationConsumed -ExitCode $_.ExitCode) })
        if ($unmeasurable.Count -gt 0) {
            Stop-Loop $EXIT_UNKNOWN "ABORTADO: '$($unmeasurable[0].Name)' nao pode medir (exit $($unmeasurable[0].ExitCode)). Iteracao nao consumida."
        }

        $script:state.consumed = $iteration
        $failed = @($gates | Where-Object { $_.ExitCode -ne 0 })

        if ($failed.Count -eq 0) {
            $script:state.verdict = 'GREEN'; $script:state.exitCode = $EXIT_GREEN
            Copy-Item -LiteralPath $patchFile -Destination (Join-Path $runDir 'diff.patch') -Force
            Write-Log "GREEN na iteracao $iteration."
            break
        }

        $failureLog = ($failed | ForEach-Object {
            "--- $($_.Name) exit=$($_.ExitCode) ---`n" + (Get-Content -LiteralPath $_.LogPath -Raw -ErrorAction SilentlyContinue)
        }) -join "`n"
        Write-Log "RED na iteracao $iteration."
    }

    if ($script:state.verdict -ne 'GREEN') {
        Write-Log "Teto de $MaxIterations iteracoes atingido. RED persistente."
    }
}
catch [System.OperationCanceledException] {
    # Ja registrado por Stop-Loop.
}
catch {
    $script:state.verdict = 'ESCALAR'
    $script:state.exitCode = $EXIT_UNKNOWN
    $script:state.notes.Add("Excecao nao prevista: $($_.Exception.Message)")
    Write-Log "ABORTADO por excecao: $($_.Exception.Message)"
}
finally {
    $verdictFile = Join-Path $runDir 'verdict.json'
    ([ordered]@{
        mission        = $missionId
        run_id         = $runId
        verdict        = $script:state.verdict
        exit_code      = $script:state.exitCode
        iterations     = $script:state.consumed
        max_iterations = $MaxIterations
        base_commit    = if (Get-Variable baseCommit -Scope 0 -EA SilentlyContinue) { $baseCommit } else { $null }
        oracle_paths   = $oraclePaths
        write_set      = $writeSet
        dry_run        = [bool]$DryRun
        human_decision = $admission.HumanDecision
        kept_worktrees = [bool]$KeepWorktree
        test_cmd       = $testCmd
        boundary_gate  = $boundaryGate
        engine_sha256  = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
        mission_sha256 = (Get-FileHash -LiteralPath $missionFile -Algorithm SHA256).Hash
        notes          = @($script:state.notes)
        limits         = @(
            'O veredito vale para os gates declarados nesta missao e para o ambiente desta maquina.'
            'GREEN local nao promove automaticamente para producao.'
            'Apenas os caminhos do WRITE_SET foram medidos; qualquer alteracao fora dele reprova a iteracao.'
        )
    } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $verdictFile -Encoding utf8
    Write-Log "Veredito gravado em $verdictFile"
    Remove-AllWorktrees
}

exit $script:state.exitCode
