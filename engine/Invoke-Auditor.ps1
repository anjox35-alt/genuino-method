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

  Trocar de auditor e trocar o comando, nao editar o motor. Este aqui usa o
  Nemotron 3 Ultra servido pela NVIDIA, escolhido por nao compartilhar familia
  de modelo com o gerente (Claude) nem com o operario (Codex): independencia
  nao produz verdade, mas reduz modo de falha compartilhado.

  O prompt e escrito pelo gerente, entao o limite 1 de docs/limites.md reaparece
  um degrau acima. Quem formula a pergunta limita as respostas possiveis.

.NOTES
  Sem NVIDIA_API_KEY no ambiente, sai com 2. Nao medir nao e aprovar, e um
  loop que parasse por falta de auditor externo deixaria de funcionar offline.
#>
[CmdletBinding()]
param(
    # Lista, nao modelo unico. O tier gratuito da NVIDIA e instavel: numa mesma
    # sessao o mesmo modelo devolveu 200, depois 503, depois 404 -- enquanto
    # continuava listado em /v1/models. Um auditor preso a um modelo vira
    # INDETERMINADO permanente na primeira indisponibilidade.
    #
    # Ordem por adequacao a saida estruturada, nao por tamanho. O Kimi responde
    # o JSON direto; os Nemotron raciocinam em voz alta antes e ja estouraram o
    # teto de tokens antes de concluir. Nenhum deles compartilha familia de
    # modelo com o gerente (Claude) nem com o operario (GPT).
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

function Write-Fail {
    param([string]$Message)
    [Console]::Error.WriteLine($Message)
}

$material = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($material)) {
    Write-Fail 'auditor: nada chegou pelo stdin.'
    exit 2
}

$chave = $env:NVIDIA_API_KEY
if ([string]::IsNullOrWhiteSpace($chave)) {
    Write-Fail 'auditor: NVIDIA_API_KEY ausente; a contra-auditoria nao pode ser medida.'
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

$resposta = $null
$modeloUsado = $null
foreach ($modelo in $Models) {
    $corpo = @{
        model       = $modelo
        messages    = @(@{ role = 'user'; content = $conteudo })
        temperature = 0.15
        max_tokens  = $MaxTokens
    } | ConvertTo-Json -Depth 6 -Compress

    try {
        $resposta = Invoke-RestMethod -Uri $BaseUrl -Method Post -TimeoutSec $TimeoutSeconds `
            -Headers @{ Authorization = "Bearer $chave"; 'Content-Type' = 'application/json' } `
            -Body $corpo
        $modeloUsado = $modelo
        break
    }
    catch {
        # Indisponibilidade de um modelo nao e veredito sobre o codigo. Anota e
        # tenta o proximo; so a lista inteira esgotada vira "nao pude medir".
        Write-Fail "auditor: '$modelo' indisponivel -- $($_.Exception.Message)"
    }
}

if (-not $resposta) {
    Write-Fail "auditor: nenhum dos $($Models.Count) modelos respondeu. Nao foi possivel medir."
    exit 2
}

$escolha = $resposta.choices[0]
$texto = $escolha.message.content
if ([string]::IsNullOrWhiteSpace($texto)) {
    Write-Fail 'auditor: resposta vazia.'
    exit 2
}

# `length` significa que o teto de tokens cortou a resposta no meio. Sem esta
# checagem, o sintoma chegava como "nenhum JSON na resposta" -- verdadeiro e
# inutil, porque manda procurar no lugar errado. O modelo raciocina em voz alta
# antes de concluir, e o veredito e a ULTIMA coisa que ele escreve.
if ($escolha.finish_reason -eq 'length') {
    Write-Fail "auditor: resposta truncada pelo teto de $MaxTokens tokens antes do veredito."
    Write-Fail 'auditor: aumente -MaxTokens. Nao foi possivel medir.'
    exit 2
}

# O modelo costuma raciocinar em voz alta antes do JSON. Pega-se o ultimo objeto
# BALANCEADO do texto: e o veredito final, nao um rascunho do meio do caminho.
#
# `LastIndexOf('{')` nao serve: a ultima chave de abertura costuma ser a de um
# objeto ANINHADO dentro de `findings`, e o recorte comeca no meio da estrutura.
# A primeira versao disto falhou exatamente assim, com "Invalid JavaScript
# property identifier character".
#
# Aqui a profundidade e contada de tras para frente a partir do ultimo `}`, e o
# recorte fecha quando ela zera. Aspas sao respeitadas: uma chave dentro de
# string nao conta como estrutura.
function Get-AuditVerdictObject {
    param([string]$Text)

    # Balanceamento sozinho nao basta. O auditor CITA o codigo que audita, e o
    # material desta base contem regex como `\{2,}` -- que e um recorte
    # perfeitamente balanceado e nao e JSON nenhum. A primeira versao recortou
    # exatamente `{2,}` e falhou com "Invalid JavaScript property identifier".
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

$veredito = Get-AuditVerdictObject -Text $texto
if (-not $veredito) {
    Write-Fail 'auditor: nenhum objeto JSON com campo `verdict` na resposta; nao foi possivel medir.'
    # Sem isto, a falha apaga a unica pista sobre o que o auditor respondeu --
    # foi assim que o recorte `{2,}` ficou invisivel na primeira tentativa.
    $amostra = $texto.Substring([Math]::Max(0, $texto.Length - 400))
    Write-Fail "auditor: ultimos 400 chars da resposta: $amostra"
    exit 2
}

# Normaliza para o formato que o motor grava, sem inventar campo ausente.
$saida = [ordered]@{
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
