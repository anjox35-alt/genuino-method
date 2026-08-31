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
    'ORACULO'                 # o que o operario nao pode tocar
    'WRITE_SET'               # o unico lugar onde o operario pode escrever
)

# WRITE_SET e ORACULO existem porque o motor precisa saber o que medir e o que
# proteger. O sandbox do Codex protege apenas `.git`, `.agents` e `.codex`, e nao
# ha forma documentada de declarar caminhos protegidos adicionais -- entao a
# protecao acontece do lado do motor.
#
# A PRIMEIRA versao usava so o ORACULO, como blocklist: o patch era gerado
# excluindo os caminhos do oraculo. Uma auditoria de seguranca derrubou esse
# desenho com um cenario de tres linhas. Com `ORACULO: tests/test_x.py` e
# `TEST_CMD: pytest tests/`, o operario nao precisa tocar o oraculo -- ele cria
# `tests/conftest.py` AO LADO:
#
#     def pytest_collection_modifyitems(items):
#         for i in items: i.add_marker(pytest.mark.skip(reason="x"))
#
# O conftest nao e caminho de oraculo, viaja no patch, e desabilita a suite
# inteira. Gate verde, veredito GREEN. A mesma classe cobre `pytest.ini`,
# `package.json`, `Makefile`, `tox.ini` -- qualquer arquivo que o TEST_CMD leia.
#
# Blocklist e a forma errada do problema: exige adivinhar tudo que o operario
# poderia criar. WRITE_SET inverte para allowlist -- so o que foi declarado
# viaja no patch, e qualquer caminho fora dele e violacao nomeada.

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
        [string]$LogPath,

        [int]$TimeoutSeconds = 900
    )

    $logDir = Split-Path -Parent $LogPath
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    function Complete-Gate {
        param([int]$Code, [string]$Detail)
        # O exit code vai para disco ao lado do log. Sem isto, dois gates
        # silenciosos -- um com 0 e outro com 1 -- produzem arquivos identicos, e
        # o auditor precisa confiar na palavra do motor para saber qual ocorreu.
        $meta = @{
            name       = $Name
            command    = $Command
            exit_code  = $Code
            status     = (ConvertTo-GateStatus -ExitCode $Code)
            measured_at = (Get-Date).ToUniversalTime().ToString('o')
            working_directory_existed = (Test-Path -LiteralPath $WorkingDirectory -PathType Container)
        }
        ($meta | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath "$LogPath.meta.json" -Encoding utf8
        if ($Detail) { Set-Content -LiteralPath $LogPath -Value $Detail -Encoding utf8 }
        return [PSCustomObject]@{
            Name     = $Name
            ExitCode = $Code
            Status   = (ConvertTo-GateStatus -ExitCode $Code)
            LogPath  = $LogPath
            MetaPath = "$LogPath.meta.json"
        }
    }

    if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
        return Complete-Gate $script:ExitCannotMeasure `
            "Gate '$Name': diretorio de trabalho inexistente: $WorkingDirectory"
    }

    # Sintaxe invalida NAO e reprovacao do produto: e impossibilidade de medir.
    # Sem esta checagem, um erro de digitacao no TEST_CMD faz o shell sair com 1
    # e o motor conta uma iteracao contra o operario por um defeito da missao.
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput(
        $Command, [ref]$null, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        return Complete-Gate $script:ExitCannotMeasure `
            "Gate '$Name': o comando nao e PowerShell valido. $($parseErrors[0].Message)"
    }

    $pwshPath = Resolve-ExternalCommand -Name 'pwsh'
    if (-not $pwshPath) {
        return Complete-Gate $script:ExitCannotMeasure "Gate '$Name': pwsh nao encontrado no PATH."
    }

    # Processo isolado com timeout: um gate travado nao pode segurar o loop para
    # sempre, e uma chamada a `exit` dentro do comando nao pode matar o motor.
    $run = Invoke-ClosedStdinProcess -FilePath $pwshPath -WorkingDirectory $WorkingDirectory `
        -TimeoutSeconds $TimeoutSeconds `
        -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', $Command)

    Set-Content -LiteralPath $LogPath -Value $run.Output -Encoding utf8

    if (-not $run.Launched -or $run.TimedOut) {
        return Complete-Gate $script:ExitCannotMeasure $null
    }
    return Complete-Gate $run.ExitCode $null
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

function ConvertTo-OraclePath {
    <#
    .SYNOPSIS
      Normaliza o campo ORACULO da missao numa lista de caminhos.

    .DESCRIPTION
      Aceita caminhos separados por virgula ou ponto e virgula. Normaliza para
      barra normal, porque o pathspec do git usa esse separador nos dois sistemas
      operacionais.

      `NENHUM` devolve lista vazia. Isso e uma declaracao explicita de que a
      missao nao tem oraculo a proteger -- diferente de esquecer o campo, que o
      gate de admissao reprova.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Declaration)

    if ([string]::IsNullOrWhiteSpace($Declaration) -or $Declaration.Trim() -eq 'NENHUM') {
        return @()
    }

    return @(
        $Declaration -split '[;,]' |
            ForEach-Object { $_.Trim().Replace('\', '/') } |
            Where-Object { $_ }
    )
}

function Test-PositiveLiteralPathspec {
    <#
    .SYNOPSIS
      Verdadeiro se o pathspec e uma allowlist positiva e literal.

    .DESCRIPTION
      Uma allowlist so restringe se for de fato uma allowlist. Uma auditoria
      reproduziu tres declaracoes que passam pela contagem `Count > 0` e nao
      restringem nada:

          WRITE_SET: :             sem restricao de pathspec -- seleciona tudo
          WRITE_SET: :!tests/      exclude-only -- recria a blocklist removida
          WRITE_SET: :(attr:algo)  mutavel: o git avalia atributos contra o
                                   working tree, entao alterar `.gitattributes`
                                   reclassifica arquivos retroativamente

      Nenhuma das tres e erro de digitacao: sao formas validas de pathspec que
      invertem o proposito do campo. Esta funcao rejeita a magia do git e aceita
      apenas caminho literal.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Pathspec)

    $p = $Pathspec.Trim()
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }

    # `:` inicia toda a sintaxe magica do git: `:!`, `:^`, `:(exclude)`,
    # `:(attr:...)`, `:(glob)`, `:(icase)`, `:/`. Nenhuma pertence a uma
    # allowlist declarada por humano.
    if ($p.StartsWith(':')) { return $false }

    # Curinga nao e literal: `engine/*` casa descendentes em subdiretorios, o que
    # amplia a allowlist alem do que quem escreveu enxerga.
    if ($p -match '[\*\?\[\]]') { return $false }

    # Sair da raiz do repositorio nao e allowlist, e fuga.
    if ($p -match '(^|/)\.\.(/|$)') { return $false }

    return $true
}

function Test-PathspecMatchesTrackedFile {
    <#
    .SYNOPSIS
      Verdadeiro se o pathspec casa ao menos um arquivo rastreado no commit-base.

    .DESCRIPTION
      Existe porque `git diff -- <pathspec que nao casa nada>` devolve exit 0 com
      saida vazia. O git nao reclama de um caminho que nao existe.

      Consequencia, se ninguem valida: uma missao declara `ORACULO: test/`
      enquanto os testes vivem em `tests/`, o motor loga "Oraculo protegido:
      test/", nao detecta violacao nenhuma, e grava `oracle_paths: ["test/"]` no
      veredito -- como se algo estivesse protegido.

      Isso nao seria falta de protecao. Seria evidencia afirmativamente falsa,
      que e pior: um leitor do veredito conclui que o oraculo foi respeitado.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$RepoPath,
        [Parameter(Mandatory)] [string]$Commit,
        [Parameter(Mandatory)] [string]$Pathspec
    )

    $r = Invoke-ClosedStdinProcess -FilePath (Resolve-ExternalCommand -Name 'git') `
        -WorkingDirectory $RepoPath `
        -ArgumentList @('ls-tree', '-r', '--name-only', $Commit, '--', $Pathspec)

    if (-not $r.Launched -or $r.ExitCode -ne 0) { return $false }
    return -not [string]::IsNullOrWhiteSpace($r.Output)
}

# Artefatos do protocolo operario<->gerente. Nao sao produto, e nao sao
# violacao: o `AGENTS.md` EXIGE que o operario escreva o WORKER-REPORT.md ao
# terminar ou ao travar.
#
# Sem esta isencao o motor se contradiz -- manda escrever o arquivo e depois
# reprova a iteracao por ele ter sido escrito. Aconteceu na primeira missao real:
# o operario implementou a correcao certa e o loop descartou o trabalho por
# causa do proprio relatorio que o contrato pediu.
#
# Eles tambem nao entram no patch medido: relato do operario nao e evidencia, e
# o veredito vem do exit code do gate.
$script:ProtocolArtifacts = @('WORKER-REPORT.md')

function Get-ProtocolArtifact {
    <#
    .SYNOPSIS
      Lista os arquivos que o protocolo exige do operario e que nao sao produto.
    #>
    [CmdletBinding()]
    param()
    return $script:ProtocolArtifacts
}

function Split-GitPathLine {
    <#
    .SYNOPSIS
      Quebra a saida de `git --name-only` em caminhos, preservando o nome.

    .DESCRIPTION
      O `.Trim()` que estava aqui removia espaco das DUAS pontas do nome. Como
      `foo`, ` foo` e `foo ` sao tres arquivos distintos no git, isso os
      colapsava num so, e um deles podia mascarar o outro na subtracao de
      conjuntos.

      Aqui so o `
` de fim de linha do CRLF sai. O nome fica como o git o
      escreveu.

      Limite conhecido: com `core.quotePath` ligado (o padrao), o git C-quota
      nomes nao-ASCII. Esta funcao nao desfaz o quoting -- ela compara formas
      quotadas entre si, e as duas listas vem do mesmo git com a mesma
      configuracao, entao a comparacao continua valida.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [AllowNull()] [string]$Payload)

    if ([string]::IsNullOrEmpty($Payload)) { return @() }
    return @(
        $Payload -split "`n" |
            ForEach-Object { $_ -replace "`r$", '' } |
            Where-Object { $_.Length -gt 0 }
    )
}

function Get-PathOutsideWriteSet {
    <#
    .SYNOPSIS
      Lista os arquivos que o operario tocou FORA do write-set declarado.

    .DESCRIPTION
      O complemento da allowlist. `New-FilteredPatchArgument` impede que esses
      caminhos viajem no patch; esta funcao diz QUAIS foram, para que a violacao
      seja nomeada em vez de silenciosamente filtrada.

      A diferenca importa: filtrar sem nomear ensina o operario que sair do
      write-set e gratuito. Nomear e reprovar ensina o contrario.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$WorktreePath,
        [Parameter(Mandatory)] [string]$BaseCommit,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$WriteSetPaths
    )

    # `--no-renames` nao e cosmetico. Com deteccao de rename ligada, mover
    # `fora/config.ps1` para `src/config.ps1` com `WRITE_SET: src/` produz
    # `src/config.ps1` nas DUAS listas: o git reporta so a pos-imagem. A
    # subtracao conclui que nada fora foi tocado, e a delecao em `fora/` fica
    # sem registro. Desligada a deteccao, o rename vira delete + add, e o lado
    # `fora/` aparece como violacao nomeada -- que e o que ele e.
    $argsComuns = @('diff', '--name-only', '--no-renames', $BaseCommit)

    $todos = Invoke-ClosedStdinProcess -FilePath (Resolve-ExternalCommand -Name 'git') `
        -WorkingDirectory $WorktreePath `
        -ArgumentList $argsComuns

    if (-not $todos.Launched -or $todos.ExitCode -ne 0) {
        return @('<INDETERMINADO: nao foi possivel listar os arquivos alterados>')
    }

    $alterados = @(Split-GitPathLine -Payload $todos.Output)
    if ($alterados.Count -eq 0) { return @() }

    # `git diff -- <write-set>` devolve exatamente o subconjunto permitido; o que
    # sobra da diferenca esta fora. Usar o proprio git para decidir evita
    # reimplementar a semantica de pathspec (globs, diretorios, caixa).
    $permitidosArgs = $argsComuns + @('--') + $WriteSetPaths
    $permitidos = Invoke-ClosedStdinProcess -FilePath (Resolve-ExternalCommand -Name 'git') `
        -WorkingDirectory $WorktreePath -ArgumentList $permitidosArgs

    if (-not $permitidos.Launched -or $permitidos.ExitCode -ne 0) {
        return @('<INDETERMINADO: nao foi possivel avaliar o write-set>')
    }

    $dentro = @(Split-GitPathLine -Payload $permitidos.Output)

    # `-cnotcontains` e a variante case-SENSITIVE. O operador padrao
    # `-notcontains` ignora caixa: num filesystem case-sensitive, um `src/foo`
    # legitimamente permitido faria um `SRC/FOO` externo desaparecer da lista de
    # violacoes. Caminho e identidade de arquivo, nao texto de interface.
    return @(
        $alterados |
            Where-Object { $dentro -cnotcontains $_ } |
            Where-Object { $script:ProtocolArtifacts -cnotcontains $_ }
    )
}

function Get-OracleViolation {
    <#
    .SYNOPSIS
      Lista os arquivos do oraculo que o operario tocou.

    .DESCRIPTION
      Compara o worktree contra o commit-base congelado. Qualquer caminho do
      oraculo que apareca aqui e uma violacao do contrato do operario: ele
      alterou aquilo que mede o proprio trabalho.

      Detectar nao basta -- o patch tambem exclui esses caminhos --, mas registrar
      a violacao transforma uma tentativa silenciosa em evidencia nomeada.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$WorktreePath,
        [Parameter(Mandatory)] [string]$BaseCommit,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$OraclePaths
    )

    if ($OraclePaths.Count -eq 0) { return @() }

    $args = @('diff', '--name-only', $BaseCommit, '--') + $OraclePaths
    $result = Invoke-ClosedStdinProcess -FilePath (Resolve-ExternalCommand -Name 'git') `
        -WorkingDirectory $WorktreePath -ArgumentList $args

    if (-not $result.Launched -or $result.ExitCode -ne 0) {
        # Nao conseguir medir a violacao nao e prova de que nao houve violacao.
        return @('<INDETERMINADO: nao foi possivel comparar o oraculo>')
    }

    return @($result.Output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function New-FilteredPatchArgument {
    <#
    .SYNOPSIS
      Monta os argumentos de `git diff` que restringem o patch ao write-set.

    .DESCRIPTION
      ALLOWLIST, nao blocklist. O patch contem exatamente os caminhos declarados
      em WRITE_SET e nada mais.

      A versao anterior era o inverso -- incluia tudo e excluia o oraculo -- e
      uma auditoria mostrou que blocklist e a forma errada do problema: para
      funcionar, ela exigiria antecipar todo arquivo que o operario poderia criar
      e que o TEST_CMD leria (`conftest.py`, `pytest.ini`, `package.json`,
      `Makefile`...). Allowlist nao precisa antecipar nada.

      O oraculo continua excluido explicitamente, mesmo estando fora do
      write-set na pratica. Redundancia barata: se alguem declarar um write-set
      que se sobrepoe ao oraculo, a exclusao ainda vale.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$BaseCommit,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$WriteSetPaths,
        [AllowEmptyCollection()] [string[]]$OraclePaths = @(),
        [switch]$NameStatus
    )

    if ($WriteSetPaths.Count -eq 0) {
        throw 'WRITE_SET vazio: sem allowlist nao ha o que medir com seguranca.'
    }

    $args = @('diff')
    if ($NameStatus) { $args += '--name-status' }
    $args += @('--binary', $BaseCommit, '--')
    foreach ($path in $WriteSetPaths) { $args += $path }
    foreach ($path in $OraclePaths)   { $args += ":(exclude)$path" }
    # Relato do operario nao e evidencia: o veredito vem do exit code do gate.
    foreach ($path in $script:ProtocolArtifacts) { $args += ":(exclude)$path" }
    return $args
}

function Resolve-ExternalCommand {
    <#
    .SYNOPSIS
      Resolve o nome de um comando para um executavel que Process.Start aceita.

    .DESCRIPTION
      No Windows, `npm install -g` instala tres arquivos para o mesmo comando:
      um shim POSIX sem extensao, um `.cmd` e um `.ps1`. O `Get-Command` puro
      devolve o `.ps1` primeiro, e `Process.Start` nao sabe executar script --
      falha com "o sistema nao pode encontrar o arquivo especificado", que
      parece ausencia do programa quando na verdade e o tipo errado de arquivo.

      Filtrar por CommandType 'Application' devolve o `.cmd` ou o `.exe`, que e
      o que a API de processo consegue lancar.

      Devolve $null quando o comando realmente nao existe.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Name)

    $candidates = @(Get-Command $Name -All -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -eq 'Application' })

    if ($candidates.Count -eq 0) { return $null }

    # No Windows o `.cmd` e o wrapper que resolve o interpretador; prefira-o ao
    # shim sem extensao, que e um script sh e falharia do mesmo jeito.
    $preferred = $candidates | Where-Object { $_.Source -match '\.(cmd|bat|exe)$' } | Select-Object -First 1
    if ($preferred) { return $preferred.Source }
    return $candidates[0].Source
}

function Invoke-ClosedStdinProcess {
    <#
    .SYNOPSIS
      Executa um processo externo com stdin FECHADO, capturando saida e exit code.

    .DESCRIPTION
      Fechar stdin nao e detalhe. No motor original, `codex exec` herdava o stdin
      do terminal, ficava esperando entrada que nunca vinha e travava o loop
      indefinidamente. A correcao la foi `</dev/null`; aqui e redirecionar e
      fechar o stream antes de esperar o processo.

      Devolve ExitCode e Output. Falha ao lancar o processo devolve exit 2:
      nao conseguir rodar nunca e o mesmo que rodar e reprovar.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string[]]$ArgumentList,
        [Parameter(Mandatory)] [string]$WorkingDirectory,
        [int]$TimeoutSeconds = 900,

        # Texto entregue pela entrada padrao antes de ela ser fechada.
        #
        # Existe porque prompt multilinha NAO sobrevive como argumento de linha
        # de comando no Windows: o `codex` instalado por npm e um wrapper .cmd,
        # e o processador de lote corta o texto nas quebras de linha. O operario
        # recebia um prompt truncado, nao encontrava a missao e respondia
        # BLOCKED -- corretamente, porque de fato faltava a missao.
        [string]$StdinContent = ''
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = $FilePath
    $psi.WorkingDirectory       = $WorkingDirectory
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.RedirectStandardInput  = $true
    $psi.UseShellExecute        = $false
    # UTF-8 SEM BOM nos tres fluxos, explicitamente.
    #
    # Sem isto, o .NET usa o code page do console -- cp850 numa maquina Windows
    # em portugues -- e toda acentuacao vira byte invalido do outro lado. O
    # `codex exec` recusou o primeiro prompt com "input is not valid UTF-8
    # (invalid byte at offset 319)" e saiu em dois segundos: o offset caia
    # exatamente na primeira palavra acentuada da missao.
    #
    # O BOM tem de ficar de fora. Um prompt que comeca com EF BB BF nao e texto
    # limpo para quem le do outro lado, e o proprio codex trata isso como lixo
    # antes da primeira instrucao.
    $utf8SemBom = [System.Text.UTF8Encoding]::new($false)
    $psi.StandardInputEncoding  = $utf8SemBom
    $psi.StandardOutputEncoding = $utf8SemBom
    $psi.StandardErrorEncoding  = $utf8SemBom
    foreach ($argument in $ArgumentList) { $psi.ArgumentList.Add($argument) }

    try {
        $process = [System.Diagnostics.Process]::Start($psi)
    }
    catch {
        # `Launched = $false` e um campo proprio, e nao mais um valor especial
        # de ExitCode. Sobrecarregar o exit code com "nao consegui lancar"
        # repetiria o defeito que este motor existe para impedir: um numero que
        # significa tres coisas, e um chamador que confunde ambiente quebrado
        # com trabalho reprovado.
        return [PSCustomObject]@{
            ExitCode = $script:ExitCannotMeasure
            Output   = "Falha ao iniciar '$FilePath': $($_.Exception.Message)"
            Launched = $false
            TimedOut = $false
        }
    }

    # Escreve o conteudo, se houver, e fecha. Fechar e obrigatorio: no motor
    # original o stdin herdado do terminal deixava o processo esperando entrada
    # que nunca chegava, e o loop travava indefinidamente.
    if (-not [string]::IsNullOrEmpty($StdinContent)) {
        $process.StandardInput.Write($StdinContent)
    }
    $process.StandardInput.Close()

    # Ler antes de esperar evita deadlock quando a saida enche o buffer do pipe.
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill($true) } catch { }
        return [PSCustomObject]@{
            ExitCode = $script:ExitCannotMeasure
            Output   = "Processo excedeu $TimeoutSeconds s e foi encerrado. Nao foi possivel medir."
            Launched = $true
            TimedOut = $true
        }
    }

    $output = ($stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult())
    return [PSCustomObject]@{
        ExitCode = $process.ExitCode
        Output   = $output
        Launched = $true
        TimedOut = $false
    }
}

function New-OperatorPrompt {
    <#
    .SYNOPSIS
      Monta o prompt entregue ao operario.

    .DESCRIPTION
      Na primeira iteracao entrega a missao. Nas seguintes entrega tambem o log
      de falha real do gate -- nao um resumo, e nao a opiniao do gerente sobre o
      que deu errado. O operario corrige contra a saida da ferramenta.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$MissionText,
        [Parameter(Mandatory)] [int]$Iteration,
        [string]$FailureLog = ''
    )

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine('Voce e o OPERARIO. Implemente o minimo que faz os testes passarem.')
    [void]$builder.AppendLine('Trabalhe apenas dentro deste worktree. Nao instale dependencia e nao acesse a rede.')
    [void]$builder.AppendLine('Nao altere os testes de aceitacao. Se faltar algo que voce nao pode resolver, pare e explique.')
    [void]$builder.AppendLine('')
    [void]$builder.AppendLine('=== MISSAO ===')
    [void]$builder.AppendLine($MissionText)

    if ($Iteration -gt 1 -and -not [string]::IsNullOrWhiteSpace($FailureLog)) {
        [void]$builder.AppendLine('')
        [void]$builder.AppendLine("=== FALHA DA ITERACAO $($Iteration - 1) ===")
        [void]$builder.AppendLine('Esta e a saida real do gate. Corrija contra ela, nao contra suposicao.')
        [void]$builder.AppendLine('')
        # Cauda basta: o erro relevante costuma estar no fim, e o inicio do log
        # gastaria contexto do operario com ruido de inicializacao.
        $tail = ($FailureLog -split "`n" | Select-Object -Last 60) -join "`n"
        [void]$builder.AppendLine($tail)
    }

    return $builder.ToString()
}

function Test-WorktreeHasChanges {
    <#
    .SYNOPSIS
      Verdadeiro se o worktree tem alteracao real em relacao ao HEAD.

    .DESCRIPTION
      Um GREEN com diff vazio nao e sucesso: significa que os gates ja passavam
      antes do operario tocar em qualquer coisa, e portanto nao provaram nada
      sobre o trabalho dele.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$WorktreePath)

    $status = & git -C $WorktreePath status --porcelain 2>$null
    return -not [string]::IsNullOrWhiteSpace(($status | Out-String))
}

Export-ModuleMember -Function @(
    'Get-RequiredMissionField'
    'Read-Mission'
    'Test-MissionAdmission'
    'Invoke-Gate'
    'ConvertTo-GateStatus'
    'Test-IterationConsumed'
    'Resolve-ExternalCommand'
    'Invoke-ClosedStdinProcess'
    'New-OperatorPrompt'
    'Test-WorktreeHasChanges'
    'ConvertTo-OraclePath'
    'Get-OracleViolation'
    'Split-GitPathLine',
    'Test-PositiveLiteralPathspec'
    'Test-PathspecMatchesTrackedFile'
    'Get-PathOutsideWriteSet'
    'Get-ProtocolArtifact'
    'New-FilteredPatchArgument'
)
