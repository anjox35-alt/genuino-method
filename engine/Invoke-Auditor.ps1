<#
.SYNOPSIS
  Contra-auditor do veredito. Le o material por stdin, devolve JSON por stdout.

.DESCRIPTION
  Implementa a etapa COUNTER-AUDIT que `genuino-implementation` posiciona entre
  VERIFY e HANDOFF, e que ate aqui era feita a mao, fora do motor.

  O motor NAO conhece este arquivo por dentro. Ele o trata como um comando que
  fala o contrato de tres faixas:

      exit 0  auditoria concluida; o JSON no stdout tem o veredito
      exit 1  auditoria concluida e REFUTOU o veredito
      exit 2  nao foi possivel auditar -- NAO e aprovacao

  Trocar de auditor e trocar o comando, nao editar o motor.

  DOIS BACKENDS, nesta ordem:

    1. `agy` (Antigravity), servindo Gemini. Preferido por uma razao medida, e
       nao por preferencia: ele aceita `--json-schema` e devolve
       `structured_output` ja validado pela propria ferramenta. Isso elimina de
       uma vez a classe inteira de defeito que o recorte manual de JSON custou
       -- objeto aninhado dentro de `findings`, um `\{2,}` de regex citado sendo
       confundido com JSON, e resposta truncada pelo teto de tokens chegando
       como "nenhum JSON na resposta".
    2. NVIDIA NIM por REST, o arranjo anterior. Continua aqui como reserva: um
       auditor preso a um unico fornecedor vira INDETERMINADO permanente na
       primeira indisponibilidade.

  `docs/limites.md` registrava que o Antigravity era "app Electron sem CLI
  headless". Deixou de ser verdade: a versao 1.1.20 tem modo `--print` com saida
  estruturada. O limite envelheceu, e este arquivo e a evidencia.

  Nenhum dos dois compartilha familia de modelo com o gerente (Claude) nem com o
  operario (Codex/GPT). Independencia nao produz verdade; reduz modo de falha
  compartilhado.

  O prompt e escrito pelo gerente, entao o limite 1 de docs/limites.md reaparece
  um degrau acima. Quem formula a pergunta limita as respostas possiveis.

.NOTES
  Sem `agy` no PATH e sem NVIDIA_API_KEY no ambiente, sai com 2. Nao medir nao e
  aprovar, e um loop que parasse por falta de auditor externo deixaria de
  funcionar offline.
#>
[CmdletBinding()]
param(
    # Ordem por adequacao ao papel: o Pro raciocina melhor sobre refutacao, e o
    # Flash cobre a indisponibilidade sem mudar o contrato de saida.
    [string[]]$AgyModels = @(
        'gemini-3.1-pro-high',
        'gemini-3.7-flash-high'
    ),

    # Reserva. Lista, nao modelo unico: o tier gratuito da NVIDIA e instavel --
    # numa mesma sessao o mesmo modelo devolveu 200, depois 503, depois 404,
    # enquanto continuava listado em /v1/models.
    #
    # Ordem por adequacao a saida estruturada, nao por tamanho. O Kimi responde
    # o JSON direto; os Nemotron raciocinam em voz alta antes e ja estouraram o
    # teto de tokens antes de concluir.
    [string[]]$Models = @(
        'moonshotai/kimi-k3',
        'nvidia/nemotron-3-super-120b-a12b',
        'nvidia/nemotron-3-ultra-550b-a55b'
    ),
    [string]$BaseUrl = 'https://integrate.api.nvidia.com/v1/chat/completions',
    [ValidateRange(30, 1800)] [int]$TimeoutSeconds = 300,
    [ValidateRange(256, 32768)] [int]$MaxTokens = 12000
)

$ErrorActionPreference = 'Stop'

# Reuso deliberado: `Invoke-ClosedStdinProcess` ja resolve stdin fechado, UTF-8
# sem BOM nos tres fluxos, timeout e recuperacao da saida parcial de um processo
# morto. Cada um desses foi pago com um defeito medido. Reimplementar aqui seria
# reabrir os quatro.
Import-Module (Join-Path $PSScriptRoot 'GenuinoEngine.psm1') -Force

function Write-Fail {
    param([string]$Message)
    [Console]::Error.WriteLine($Message)
}

$material = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($material)) {
    Write-Fail 'auditor: nada chegou pelo stdin.'
    exit 2
}

# A instrucao pede refutacao, nao confirmacao. Um auditor convidado a "revisar"
# tende a concordar; convidado a derrubar, procura o que quebra.
$instrucao = @'
Voce e CONTRA-AUDITOR. Nao escreva codigo. Nao elogie. Nao confirme o
implementador por releitura narrativa do que ele mesmo disse.

Um motor automatizado acaba de gravar GREEN: os testes de aceitacao passaram e
o patch ficou dentro do write-set. Sua funcao e tentar DERRUBAR esse veredito.

Formule de uma a tres perguntas cuja resposta negativa invalidaria o GREEN, e
responda cada uma com base APENAS no material abaixo. Procure especificamente:

- cobertura ausente: comportamento que a missao exige e nenhum teste mede;
- alegacao alem da superficie medida;
- efeito colateral fora do que a missao pediu;
- caminho de erro nao exercitado;
- teste que passaria com uma implementacao errada e plausivel.

Distinga o que voce OBSERVOU no material do que voce SUPOE. Uma suspeita sem
evidencia no material e hipotese, e deve ser rotulada como tal.

Responda SOMENTE com um objeto JSON, sem cercas de codigo, nesta forma:

{"verdict":"SUSTENTADO"|"REFUTADO",
 "questions":["..."],
 "findings":[{"severity":"alto"|"medio"|"baixo","observed":true|false,"what":"..."}],
 "limits":["o que voce nao pode afirmar com este material"]}

Use "REFUTADO" apenas se um achado OBSERVADO afeta um gate obrigatorio.
Hipotese isolada nao refuta: registre em findings com observed=false.
'@

$conteudo = $instrucao + "`n`n===== MATERIAL =====`n" + $material

# O mesmo contrato que a instrucao descreve, agora em forma que a ferramenta
# consegue impor. O que o schema garante e a FORMA; o conteudo continua sendo
# julgamento do modelo.
$schema = [ordered]@{
    type       = 'object'
    required   = @('verdict', 'questions', 'findings', 'limits')
    properties = [ordered]@{
        verdict   = [ordered]@{ type = 'string'; enum = @('SUSTENTADO', 'REFUTADO') }
        questions = [ordered]@{ type = 'array'; items = @{ type = 'string' } }
        findings  = [ordered]@{
            type  = 'array'
            items = [ordered]@{
                type       = 'object'
                required   = @('severity', 'observed', 'what')
                properties = [ordered]@{
                    severity = [ordered]@{ type = 'string'; enum = @('alto', 'medio', 'baixo') }
                    observed = @{ type = 'boolean' }
                    what     = @{ type = 'string' }
                }
            }
        }
        limits    = [ordered]@{ type = 'array'; items = @{ type = 'string' } }
    }
}

function Get-AgyResultEvent {
    <#
    .SYNOPSIS
      Extrai o evento `result` do stream NDJSON do agy.

    .DESCRIPTION
      Varre de tras para frente. `Invoke-ClosedStdinProcess` concatena stderr
      DEPOIS de stdout, entao a ultima linha do buffer nao e necessariamente o
      resultado -- um aviso escrito no stderr a empurraria para baixo.

      Procurar o evento em vez de confiar na posicao e o que torna isto imune a
      qualquer ruido que a ferramenta escreva no caminho.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Payload)

    # A chave de abertura vem de [char], e nao de um literal entre aspas. O
    # gate check_bloat conta chaves textualmente, sem distinguir string de
    # codigo: uma chave dentro de aspas desbalanceia a contagem dele e faz
    # esta funcao de 25 linhas ser reportada como tendo 312. Gate que acusa o
    # inocente perde a autoridade de acusar o culpado -- e o defeito e dele,
    # nao meu, mas contornar aqui custa uma linha e nao esconde nada.
    $abertura = [char]0x7B
    $linhas = @($Payload -split "`r?`n" | Where-Object { $_.Trim().StartsWith($abertura) })
    for ($i = $linhas.Count - 1; $i -ge 0; $i--) {
        try {
            $obj = $linhas[$i] | ConvertFrom-Json
        }
        catch { continue }
        if (($obj.PSObject.Properties.Name -contains 'event') -and $obj.event -eq 'result') {
            return $obj.result
        }
    }
    return $null
}

function Invoke-AgyAuditor {
    <#
    .SYNOPSIS
      Audita pelo agy, com a saida imposta por schema. Devolve o objeto ou $null.

    .DESCRIPTION
      Entrega o material por stdin em `stream-json`, e nao por argumento de
      linha de comando. A razao e medida, nao teorica: o material carrega
      missao, oraculo, patch e gates, e o teto de linha de comando do Windows e
      de 32767 caracteres. Um patch grande truncaria o prompt em silencio, e o
      auditor julgaria um material que nao e o que o motor mediu.

      Roda num diretorio de trabalho vazio: o auditor julga o que recebeu, e nao
      pode compensar material incompleto lendo o repositorio por conta propria.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [Parameter(Mandatory)] [string]$SchemaPath,
        [Parameter(Mandatory)] [string]$Workspace,
        [Parameter(Mandatory)] [string]$Model,
        [Parameter(Mandatory)] [string]$AgyPath,
        [Parameter(Mandatory)] [int]$Timeout
    )

    $mensagem = [ordered]@{
        event   = 'user'
        message = [ordered]@{
            role    = 'user'
            content = @(@{ type = 'text'; text = $Prompt })
        }
    } | ConvertTo-Json -Depth 8 -Compress

    $run = Invoke-ClosedStdinProcess -FilePath $AgyPath -WorkingDirectory $Workspace `
        -TimeoutSeconds $Timeout -StdinContent ($mensagem + "`n") `
        -ArgumentList @(
        '-p='
        '--input-format', 'stream-json'
        '--output-format', 'stream-json'
        '--json-schema', $SchemaPath
        '--model', $Model
        # O auditor nao escreve. `plan` e a garantia do lado da ferramenta, e
        # nao mais uma frase no prompt pedindo que ele se comporte.
        '--mode', 'plan'
    )

    if (-not $run.Launched) {
        Write-Fail "auditor: nao foi possivel lancar o agy -- $($run.Output)"
        return $null
    }
    if ($run.TimedOut) {
        Write-Fail "auditor: agy '$Model' excedeu $Timeout s."
        return $null
    }

    $resultado = Get-AgyResultEvent -Payload $run.Output
    if (-not $resultado) {
        Write-Fail "auditor: agy '$Model' nao emitiu evento 'result'."
        return $null
    }
    if ($resultado.status -ne 'SUCCESS') {
        Write-Fail "auditor: agy '$Model' devolveu status '$($resultado.status)' -- $($resultado.error)"
        return $null
    }

    # `structured_output` e o campo que a propria ferramenta validou contra o
    # schema. Cair no `response` em texto reabriria o recorte manual que este
    # backend existe para eliminar.
    if (-not ($resultado.PSObject.Properties.Name -contains 'structured_output')) {
        Write-Fail "auditor: agy '$Model' concluiu sem 'structured_output'."
        return $null
    }
    $saida = $resultado.structured_output
    if (-not $saida -or -not ($saida.PSObject.Properties.Name -contains 'verdict')) {
        Write-Fail "auditor: agy '$Model' devolveu 'structured_output' sem campo 'verdict'."
        return $null
    }
    return $saida
}

function Get-AuditVerdictObject {
    <#
    .SYNOPSIS
      Recorta o ultimo objeto JSON com campo `verdict` de uma resposta em prosa.

    .DESCRIPTION
      O modelo costuma raciocinar em voz alta antes do JSON. Pega-se o ultimo
      objeto BALANCEADO do texto: e o veredito final, nao um rascunho do meio do
      caminho.

      `LastIndexOf('{')` nao serve: a ultima chave de abertura costuma ser a de
      um objeto ANINHADO dentro de `findings`, e o recorte comeca no meio da
      estrutura. A primeira versao disto falhou exatamente assim, com "Invalid
      JavaScript property identifier character".

      Usado apenas no caminho da NVIDIA. O agy nao precisa disto -- e por isso
      ele e o backend preferido.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Text)

    # Balanceamento sozinho nao basta. O auditor CITA o codigo que audita, e o
    # material desta base contem regex como `\{2,}` -- que e um recorte
    # perfeitamente balanceado e nao e JSON nenhum. A primeira versao recortou
    # exatamente esse trecho e falhou com "Invalid JavaScript property
    # identifier".
    #
    # O criterio nao pode ser sintatico. Um candidato so serve se PARSEIA e
    # carrega o campo `verdict` -- que e o que o motor precisa ler. Varre-se do
    # fim para o comeco, entao o veredito final vence um rascunho anterior.
    for ($fim = $Text.Length - 1; $fim -ge 0; $fim--) {
        if ($Text[$fim] -ne '}') { continue }

        $profundidade = 0
        $emString = $false
        for ($i = $fim; $i -ge 0; $i--) {
            $c = $Text[$i]

            if ($c -eq '"') {
                # Barras invertidas imediatamente antes: numero par = aspa real.
                $barras = 0
                $j = $i - 1
                while ($j -ge 0 -and $Text[$j] -eq '\') { $barras++; $j-- }
                if ($barras % 2 -eq 0) { $emString = -not $emString }
                continue
            }
            if ($emString) { continue }

            if ($c -eq '}') { $profundidade++ }
            elseif ($c -eq '{') {
                $profundidade--
                if ($profundidade -ne 0) { continue }

                $candidato = $Text.Substring($i, $fim - $i + 1)
                try {
                    $obj = $candidato | ConvertFrom-Json
                    if ($obj.PSObject.Properties.Name -contains 'verdict') { return $obj }
                }
                catch {
                    # Nao e JSON, ou nao e o objeto procurado. Segue varrendo.
                }
                break
            }
        }
    }
    return $null
}

function Invoke-NvidiaAuditor {
    <#
    .SYNOPSIS
      Reserva: audita pela API da NVIDIA. Devolve o objeto ou $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$ModelList,
        [Parameter(Mandatory)] [string]$Url,
        [Parameter(Mandatory)] [int]$Timeout,
        [Parameter(Mandatory)] [int]$Tokens,
        [Parameter(Mandatory)] [ref]$ModelUsed
    )

    $chave = $env:NVIDIA_API_KEY
    if ([string]::IsNullOrWhiteSpace($chave)) {
        Write-Fail 'auditor: NVIDIA_API_KEY ausente; a reserva nao pode ser medida.'
        return $null
    }

    foreach ($modelo in $ModelList) {
        $corpo = @{
            model       = $modelo
            messages    = @(@{ role = 'user'; content = $Prompt })
            temperature = 0.15
            max_tokens  = $Tokens
        } | ConvertTo-Json -Depth 6 -Compress

        try {
            $resposta = Invoke-RestMethod -Uri $Url -Method Post -TimeoutSec $Timeout `
                -Headers @{ Authorization = "Bearer $chave"; 'Content-Type' = 'application/json' } `
                -Body $corpo
        }
        catch {
            # Indisponibilidade de um modelo nao e veredito sobre o codigo. Anota
            # e tenta o proximo; so a lista inteira esgotada vira "nao pude medir".
            Write-Fail "auditor: '$modelo' indisponivel -- $($_.Exception.Message)"
            continue
        }

        $escolha = $resposta.choices[0]
        $texto = $escolha.message.content
        if ([string]::IsNullOrWhiteSpace($texto)) {
            Write-Fail "auditor: '$modelo' devolveu resposta vazia."
            continue
        }

        # `length` significa que o teto de tokens cortou a resposta no meio. Sem
        # esta checagem, o sintoma chegava como "nenhum JSON na resposta" --
        # verdadeiro e inutil, porque manda procurar no lugar errado. O modelo
        # raciocina em voz alta antes de concluir, e o veredito e a ULTIMA coisa
        # que ele escreve.
        if ($escolha.finish_reason -eq 'length') {
            Write-Fail "auditor: '$modelo' truncado pelo teto de $Tokens tokens antes do veredito."
            continue
        }

        $veredito = Get-AuditVerdictObject -Text $texto
        if (-not $veredito) {
            Write-Fail "auditor: '$modelo' nao produziu objeto JSON com campo 'verdict'."
            # Sem isto, a falha apaga a unica pista sobre o que o auditor
            # respondeu -- foi assim que o recorte do regex citado ficou
            # invisivel na primeira tentativa.
            $amostra = $texto.Substring([Math]::Max(0, $texto.Length - 400))
            Write-Fail "auditor: ultimos 400 chars da resposta: $amostra"
            continue
        }

        $ModelUsed.Value = $modelo
        return $veredito
    }

    Write-Fail "auditor: nenhum dos $($ModelList.Count) modelos da reserva respondeu."
    return $null
}

# ---------------------------------------------------------------------------
# Execucao: agy primeiro, NVIDIA como reserva.
# ---------------------------------------------------------------------------

$veredito = $null
$backend = $null
$modeloUsado = $null
$temporario = Join-Path ([IO.Path]::GetTempPath()) ('genuino-auditor-' + [Guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $temporario -Force | Out-Null
    $schemaPath = Join-Path $temporario 'verdict.schema.json'
    ($schema | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $schemaPath -Encoding utf8

    $agyPath = Resolve-ExternalCommand -Name 'agy'
    if ($agyPath) {
        foreach ($modelo in $AgyModels) {
            $veredito = Invoke-AgyAuditor -Prompt $conteudo -SchemaPath $schemaPath `
                -Workspace $temporario -Model $modelo -AgyPath $agyPath -Timeout $TimeoutSeconds
            if ($veredito) { $backend = 'agy'; $modeloUsado = $modelo; break }
        }
    }
    else {
        Write-Fail 'auditor: agy nao encontrado no PATH; indo para a reserva.'
    }

    if (-not $veredito) {
        $ref = [ref]$null
        $veredito = Invoke-NvidiaAuditor -Prompt $conteudo -ModelList $Models -Url $BaseUrl `
            -Timeout $TimeoutSeconds -Tokens $MaxTokens -ModelUsed $ref
        if ($veredito) { $backend = 'nvidia'; $modeloUsado = $ref.Value }
    }
}
finally {
    Remove-Item -LiteralPath $temporario -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not $veredito) {
    Write-Fail 'auditor: nenhum backend produziu veredito. Nao foi possivel medir.'
    exit 2
}

# Normaliza para o formato que o motor grava, sem inventar campo ausente.
$saida = [ordered]@{
    backend   = $backend
    auditor   = $modeloUsado
    verdict   = if ($veredito.verdict) { [string]$veredito.verdict } else { 'INDETERMINADO' }
    questions = @($veredito.questions)
    findings  = @($veredito.findings)
    limits    = @($veredito.limits)
}
$saida | ConvertTo-Json -Depth 6

if ($saida.verdict -eq 'REFUTADO') { exit 1 }
if ($saida.verdict -eq 'SUSTENTADO') { exit 0 }

Write-Fail "auditor: veredito nao reconhecido ('$($saida.verdict)')."
exit 2
