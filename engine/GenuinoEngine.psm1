<#
.SYNOPSIS
  Nucleo do green loop: leitura de missao, gate de admissao e execucao de gates.

.DESCRIPTION
  Porte do `green-loop.sh` de Bash para PowerShell 7, preservando as decisoes
  que foram pagas com defeito medido no motor original.

  Funcoes puras, sem efeito colateral de orquestracao, para que os testes
  exercitem a decisao sem subir worktree nem chamar o operario.

  CONTRATO DE TRES FAIXAS -- a decisao mais importante deste modulo:

      0    passou
      1    reprovacao medida; consome iteracao
      >=2  nao foi possivel medir; e falha de ambiente, NAO consome iteracao

  O `>=2` existe porque a alternativa e um exit code que significa tres coisas
  ao mesmo tempo. No motor original isso queimou 5 iteracoes num run real: um
  worktree ausente foi lido como "fronteira fechada", produziu 4 iteracoes
  instantaneas e um veredito RED sobre um ambiente quebrado. O codigo estava
  certo; o contrato e que estava errado.
#>

Set-StrictMode -Version Latest

$script:ExitPass          = 0
$script:ExitMeasuredFail  = 1
$script:ExitCannotMeasure = 2

# Campos sem os quais o loop nao pode comecar. Cada um responde uma pergunta
# que, sem resposta, transforma cada iteracao em chute.
$script:RequiredMissionFields = @(
    'TEST_CMD'                # o que prova que o trabalho ficou pronto
    'FRONTEIRA'               # onde o resultado precisa funcionar de verdade
    'GATE_DA_FRONTEIRA'       # o que prova que funciona la
    'PRE_REQUISITOS_HUMANOS'  # o que o loop nao pode resolver sozinho
)

function Get-RequiredMissionField {
    <#
    .SYNOPSIS
      Lista os campos obrigatorios de uma missao.
    #>
    [CmdletBinding()]
    param()
    return $script:RequiredMissionFields
}

function Read-Mission {
    <#
    .SYNOPSIS
      Le os campos declarados num arquivo de missao.

    .DESCRIPTION
      Formato: linhas `CAMPO: valor` na coluna zero. A primeira ocorrencia de
      cada campo vence -- uma segunda declaracao mais abaixo no documento e
      quase sempre prosa citando o campo, nao uma redefinicao.

      Devolve um hashtable. Campo ausente simplesmente nao aparece; quem decide
      se isso reprova e o gate de admissao, nao o leitor.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Arquivo de missao nao encontrado: $Path"
    }

    $fields = @{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding utf8) {
        if ($line -match '^([A-Z][A-Z0-9_]*):[ \t]*(.*)$') {
            $name  = $Matches[1]
            $value = $Matches[2].Trim()
            if (-not $fields.ContainsKey($name)) {
                $fields[$name] = $value
            }
        }
    }
    return $fields
}

function Test-MissionAdmission {
    <#
    .SYNOPSIS
      G0 de admissao. Decide se a missao pode entrar no loop.

    .DESCRIPTION
      Um loop so converge se houver sinal de erro vindo da fronteira onde o
      resultado precisa funcionar. Sem esse sinal cada iteracao e chute, e o
      agente pode produzir dezenas de versoes sem nunca dizer que falta um SDK
      na maquina de quem pediu.

      Pre-requisitos humanos nao satisfeitos param o loop. Se `HumanApproved`
      for informado, o loop segue -- mas isso e registrado como DECISAO do
      humano, jamais como fato verificado por este motor.

    .OUTPUTS
      PSCustomObject com Admitted, ExitCode, Reasons e HumanDecision.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Mission,

        [switch]$HumanApproved
    )

    $reasons = [System.Collections.Generic.List[string]]::new()

    foreach ($field in $script:RequiredMissionFields) {
        if (-not $Mission.ContainsKey($field) -or [string]::IsNullOrWhiteSpace($Mission[$field])) {
            $reasons.Add("Campo obrigatorio ausente ou vazio: '$field'.")
        }
    }

    if ($reasons.Count -gt 0) {
        return [PSCustomObject]@{
            Admitted      = $false
            ExitCode      = $script:ExitMeasuredFail
            Reasons       = $reasons.ToArray()
            HumanDecision = $false
        }
    }

    $prereq = $Mission['PRE_REQUISITOS_HUMANOS']
    if ($prereq -ne 'NENHUM' -and -not $HumanApproved) {
        $reasons.Add("A missao depende de pre-requisitos na maquina do humano: $prereq")
        $reasons.Add('O loop nao decide que o ambiente esta pronto. Reexecute com -HumanApproved para registrar essa decisao.')
        return [PSCustomObject]@{
            Admitted      = $false
            ExitCode      = $script:ExitMeasuredFail
            Reasons       = $reasons.ToArray()
            HumanDecision = $false
        }
    }

    return [PSCustomObject]@{
        Admitted      = $true
        ExitCode      = $script:ExitPass
        Reasons       = @()
        # Verdadeiro apenas quando um humano dispensou pre-requisitos reais.
        # E DECISAO registrada, nunca constatacao deste motor.
        HumanDecision = ($prereq -ne 'NENHUM' -and [bool]$HumanApproved)
    }
}

function Invoke-Gate {
    <#
    .SYNOPSIS
      Executa um gate e classifica o resultado nas tres faixas.

    .DESCRIPTION
      O comando roda em `WorkingDirectory` e toda a saida vai para `LogPath`.
      Nada e interpretado do texto: o veredito vem do exit code, porque texto
      de ferramenta muda entre versoes e exit code e contrato.

      Um diretorio de trabalho inexistente devolve 2, nunca 1. Confundir "nao
      consegui rodar" com "rodou e reprovou" e o defeito que este contrato
      existe para impedir.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory)]
        [string]$LogPath
    )

    if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
        $message = "Gate '$Name': diretorio de trabalho inexistente: $WorkingDirectory"
        Set-Content -LiteralPath $LogPath -Value $message -Encoding utf8
        return [PSCustomObject]@{
            Name     = $Name
            ExitCode = $script:ExitCannotMeasure
            Status   = 'INDETERMINADO'
            LogPath  = $LogPath
        }
    }

    $logDir = Split-Path -Parent $LogPath
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $previous = $PWD
    $exitCode = $script:ExitCannotMeasure
    try {
        Set-Location -LiteralPath $WorkingDirectory
        # pwsh -Command isola o gate: uma chamada a `exit` dentro do comando
        # encerraria este motor se fosse avaliada no processo atual.
        $output = & pwsh -NoProfile -NonInteractive -Command $Command 2>&1
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = $script:ExitPass }
        $output | Out-String | Set-Content -LiteralPath $LogPath -Encoding utf8
    }
    catch {
        # Falha ao sequer lancar o processo e ambiente, nao veredito.
        Set-Content -LiteralPath $LogPath -Value "Falha ao executar o gate: $($_.Exception.Message)" -Encoding utf8
        $exitCode = $script:ExitCannotMeasure
    }
    finally {
        Set-Location -LiteralPath $previous
    }

    return [PSCustomObject]@{
        Name     = $Name
        ExitCode = $exitCode
        Status   = ConvertTo-GateStatus -ExitCode $exitCode
        LogPath  = $LogPath
    }
}

function ConvertTo-GateStatus {
    <#
    .SYNOPSIS
      Traduz um exit code para o rotulo das tres faixas.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ExitCode
    )

    if ($ExitCode -eq 0) { return 'PASS' }
    if ($ExitCode -eq 1) { return 'FAIL' }
    return 'INDETERMINADO'
}

function Test-IterationConsumed {
    <#
    .SYNOPSIS
      Decide se um resultado de gate consome uma iteracao do loop.

    .DESCRIPTION
      Reprovacao medida consome: o operario recebe o log e tenta de novo.
      Falha de ambiente NAO consome: tentar de novo com o ambiente quebrado
      apenas queima o teto de iteracoes sem produzir informacao.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ExitCode
    )

    return ($ExitCode -eq $script:ExitPass -or $ExitCode -eq $script:ExitMeasuredFail)
}

Export-ModuleMember -Function @(
    'Get-RequiredMissionField'
    'Read-Mission'
    'Test-MissionAdmission'
    'Invoke-Gate'
    'ConvertTo-GateStatus'
    'Test-IterationConsumed'
)
