<#
  Testes do nucleo do green loop.

  Regra: cada gate precisa de ao menos um caso que prova que ele REPROVA, e o
  contrato de tres faixas precisa de um caso para cada faixa. Um motor que so
  foi visto aprovando nao foi testado.
#>

BeforeAll {
    $script:ModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'GenuinoEngine.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Read-Mission' {

    It 'le os campos declarados' {
        $file = Join-Path $TestDrive 'm.md'
        @(
            '# Missao de exemplo'
            'TEST_CMD: pwsh -c "exit 0"'
            'FRONTEIRA: node neste workspace'
            'GATE_DA_FRONTEIRA: pwsh -c "exit 0"'
            'PRE_REQUISITOS_HUMANOS: NENHUM'
        ) | Set-Content -LiteralPath $file -Encoding utf8

        $mission = Read-Mission -Path $file
        $mission['TEST_CMD']               | Should -Be 'pwsh -c "exit 0"'
        $mission['FRONTEIRA']              | Should -Be 'node neste workspace'
        $mission['PRE_REQUISITOS_HUMANOS'] | Should -Be 'NENHUM'
    }

    It 'mantem a primeira ocorrencia quando o campo aparece duas vezes' {
        # Uma segunda mencao mais abaixo costuma ser prosa citando o campo,
        # nao uma redefinicao. Deixar a ultima vencer faria a documentacao
        # reconfigurar o loop em silencio.
        $file = Join-Path $TestDrive 'dup.md'
        @(
            'FRONTEIRA: valor real'
            ''
            'Explicacao em prosa.'
            'FRONTEIRA: exemplo citado no texto'
        ) | Set-Content -LiteralPath $file -Encoding utf8

        (Read-Mission -Path $file)['FRONTEIRA'] | Should -Be 'valor real'
    }

    It 'ignora campo indentado, que e conteudo e nao declaracao' {
        $file = Join-Path $TestDrive 'ind.md'
        @('  FRONTEIRA: dentro de um bloco de exemplo') | Set-Content -LiteralPath $file -Encoding utf8
        (Read-Mission -Path $file).ContainsKey('FRONTEIRA') | Should -BeFalse
    }

    It 'falha de forma explicita quando o arquivo nao existe' {
        { Read-Mission -Path (Join-Path $TestDrive 'ausente.md') } | Should -Throw
    }
}

Describe 'Test-MissionAdmission' {

    BeforeAll {
        $script:Completa = @{
            TEST_CMD               = 'pwsh -c "exit 0"'
            FRONTEIRA              = 'node neste workspace'
            GATE_DA_FRONTEIRA      = 'pwsh -c "exit 0"'
            PRE_REQUISITOS_HUMANOS = 'NENHUM'
            ORACULO                = 'NENHUM'
        }
    }

    It 'admite uma missao completa sem pre-requisitos' {
        $r = Test-MissionAdmission -Mission $script:Completa
        $r.Admitted      | Should -BeTrue
        $r.ExitCode      | Should -Be 0
        $r.HumanDecision | Should -BeFalse
    }

    It 'reprova quando falta qualquer campo obrigatorio' {
        # Lista LITERAL, nao `Get-RequiredMissionField`. Iterar sobre a lista de
        # producao torna o teste tautologico: remover TEST_CMD do modulo removeria
        # tambem o caso que deveria detectar essa remocao, e a suite continuaria
        # verde enquanto o gate deixava de exigir o campo.
        foreach ($field in @('TEST_CMD', 'FRONTEIRA', 'GATE_DA_FRONTEIRA', 'PRE_REQUISITOS_HUMANOS', 'ORACULO')) {
            $mission = $script:Completa.Clone()
            $mission.Remove($field)
            $r = Test-MissionAdmission -Mission $mission
            $r.Admitted | Should -BeFalse -Because "faltando $field"
            $r.ExitCode | Should -Be 1
            ($r.Reasons -join ' ') | Should -Match $field
        }
    }

    It 'a lista de campos obrigatorios do modulo nao encolheu' {
        # Guarda separada: se alguem remover um campo da producao, este teste
        # falha e nomeia o campo perdido, em vez de a suite ficar verde por
        # deixar de testar aquilo.
        $esperados = @('TEST_CMD', 'FRONTEIRA', 'GATE_DA_FRONTEIRA', 'PRE_REQUISITOS_HUMANOS', 'ORACULO')
        $atuais = @(Get-RequiredMissionField)
        foreach ($campo in $esperados) {
            $atuais | Should -Contain $campo -Because "o gate precisa continuar exigindo $campo"
        }
    }

    It 'reprova campo presente mas vazio' {
        $mission = $script:Completa.Clone()
        $mission['FRONTEIRA'] = '   '
        (Test-MissionAdmission -Mission $mission).Admitted | Should -BeFalse
    }

    It 'para quando ha pre-requisito humano e ninguem aprovou' {
        $mission = $script:Completa.Clone()
        $mission['PRE_REQUISITOS_HUMANOS'] = 'instalar o SDK do Android'
        $r = Test-MissionAdmission -Mission $mission
        $r.Admitted | Should -BeFalse
        ($r.Reasons -join ' ') | Should -Match 'SDK do Android'
    }

    It 'segue com aprovacao humana, e marca isso como DECISAO' {
        $mission = $script:Completa.Clone()
        $mission['PRE_REQUISITOS_HUMANOS'] = 'instalar o SDK do Android'
        $r = Test-MissionAdmission -Mission $mission -HumanApproved
        $r.Admitted      | Should -BeTrue
        # O motor nao verificou nada disto. Registrar como decisao e o que
        # impede a aprovacao humana de virar "fato comprovado" no relatorio.
        $r.HumanDecision | Should -BeTrue
    }

    It 'nao marca decisao humana quando nao havia pre-requisito' {
        (Test-MissionAdmission -Mission $script:Completa -HumanApproved).HumanDecision | Should -BeFalse
    }
}

Describe 'Contrato de tres faixas' {

    It 'traduz cada faixa para o rotulo correto' {
        ConvertTo-GateStatus -ExitCode 0   | Should -Be 'PASS'
        ConvertTo-GateStatus -ExitCode 1   | Should -Be 'FAIL'
        ConvertTo-GateStatus -ExitCode 2   | Should -Be 'INDETERMINADO'
        ConvertTo-GateStatus -ExitCode 127 | Should -Be 'INDETERMINADO'
    }

    It 'consome iteracao apenas em resultado medido' {
        Test-IterationConsumed -ExitCode 0   | Should -BeTrue
        Test-IterationConsumed -ExitCode 1   | Should -BeTrue
        # Falha de ambiente nao consome. Sem isto, um worktree ausente queima
        # o teto de iteracoes e produz um veredito RED sobre nada.
        Test-IterationConsumed -ExitCode 2   | Should -BeFalse
        Test-IterationConsumed -ExitCode 127 | Should -BeFalse
    }
}

Describe 'Invoke-Gate' {

    It 'aprova comando que sai com zero' {
        $r = Invoke-Gate -Name 'ok' -Command 'exit 0' -WorkingDirectory $TestDrive `
                         -LogPath (Join-Path $TestDrive 'ok.log')
        $r.ExitCode | Should -Be 0
        $r.Status   | Should -Be 'PASS'
    }

    It 'reprova comando que sai com um' {
        $r = Invoke-Gate -Name 'fail' -Command 'exit 1' -WorkingDirectory $TestDrive `
                         -LogPath (Join-Path $TestDrive 'fail.log')
        $r.ExitCode | Should -Be 1
        $r.Status   | Should -Be 'FAIL'
    }

    It 'classifica exit maior ou igual a dois como INDETERMINADO' {
        $r = Invoke-Gate -Name 'amb' -Command 'exit 3' -WorkingDirectory $TestDrive `
                         -LogPath (Join-Path $TestDrive 'amb.log')
        $r.ExitCode | Should -Be 3
        $r.Status   | Should -Be 'INDETERMINADO'
    }

    It 'trata diretorio de trabalho inexistente como nao-medicao, nunca reprovacao' {
        # Este e o defeito que custou 5 iteracoes no motor original: um
        # worktree ausente foi lido como "fronteira fechada". Devolver 1 aqui
        # produziria um veredito RED sobre um ambiente quebrado.
        $r = Invoke-Gate -Name 'sem-dir' -Command 'exit 0' `
                         -WorkingDirectory (Join-Path $TestDrive 'nao-existe') `
                         -LogPath (Join-Path $TestDrive 'semdir.log')
        $r.ExitCode | Should -Be 2
        $r.Status   | Should -Be 'INDETERMINADO'
        $r.ExitCode | Should -Not -Be 1
    }

    It 'grava a saida do comando no log' {
        $log = Join-Path $TestDrive 'saida.log'
        Invoke-Gate -Name 'eco' -Command 'Write-Output "marca-de-teste"; exit 0' `
                    -WorkingDirectory $TestDrive -LogPath $log | Out-Null
        Get-Content -LiteralPath $log -Raw | Should -Match 'marca-de-teste'
    }

    It 'nao encerra o motor quando o gate chama exit' {
        # O gate roda em processo isolado. Se fosse avaliado no processo atual,
        # um `exit` dentro do comando mataria o loop inteiro.
        Invoke-Gate -Name 'isolado' -Command 'exit 42' -WorkingDirectory $TestDrive `
                    -LogPath (Join-Path $TestDrive 'iso.log') | Out-Null
        $true | Should -BeTrue
    }
}

Describe 'Resolve-ExternalCommand' {

    It 'devolve um executavel que Process.Start aceita' {
        # No Windows, `npm install -g` cria .ps1, .cmd e um shim sem extensao
        # para o mesmo nome. Get-Command puro devolve o .ps1, que Process.Start
        # nao sabe lancar -- e o erro parece "programa nao instalado".
        $resolved = Resolve-ExternalCommand -Name 'git'
        $resolved | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $resolved | Should -BeTrue
        $resolved | Should -Not -Match '\.ps1$'
    }

    It 'devolve nulo para comando inexistente' {
        Resolve-ExternalCommand -Name 'programa-que-nao-existe-xyz-123' | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-ClosedStdinProcess' {

    It 'sinaliza Launched=false quando o executavel nao existe' {
        # `Launched` e um campo proprio justamente para nao sobrecarregar o exit
        # code. Sem ele, "nao consegui lancar" viraria indistinguivel de
        # "rodou e reprovou", e o loop queimaria iteracoes num ambiente quebrado.
        $r = Invoke-ClosedStdinProcess -FilePath 'programa-que-nao-existe-xyz-123' `
                                       -ArgumentList @('--help') -WorkingDirectory $TestDrive
        $r.Launched | Should -BeFalse
        $r.ExitCode | Should -Be 2
    }

    It 'sinaliza Launched=true e captura o exit code real' {
        $pwshPath = Resolve-ExternalCommand -Name 'pwsh'
        $r = Invoke-ClosedStdinProcess -FilePath $pwshPath -WorkingDirectory $TestDrive `
                                       -ArgumentList @('-NoProfile', '-Command', 'exit 7')
        $r.Launched | Should -BeTrue
        $r.TimedOut | Should -BeFalse
        $r.ExitCode | Should -Be 7
    }

    It 'entrega o conteudo de stdin ao processo' {
        # Regressao: o prompt multilinha nao sobrevive como argumento atraves do
        # wrapper .cmd do Windows. O operario recebia texto truncado e respondia
        # BLOCKED -- corretamente, porque a missao de fato nao chegava.
        $pwshPath = Resolve-ExternalCommand -Name 'pwsh'
        $texto = "linha um`nlinha dois`nlinha tres"
        $r = Invoke-ClosedStdinProcess -FilePath $pwshPath -WorkingDirectory $TestDrive `
                 -StdinContent $texto `
                 -ArgumentList @('-NoProfile', '-Command', '$input | Write-Output')
        $r.Launched | Should -BeTrue
        $r.Output   | Should -Match 'linha um'
        $r.Output   | Should -Match 'linha tres'
    }

    It 'fecha stdin, para que o processo nao espere entrada para sempre' {
        # Sem o fechamento, um processo que le stdin trava o loop indefinidamente.
        $pwshPath = Resolve-ExternalCommand -Name 'pwsh'
        $r = Invoke-ClosedStdinProcess -FilePath $pwshPath -WorkingDirectory $TestDrive `
                 -TimeoutSeconds 30 `
                 -ArgumentList @('-NoProfile', '-Command', '$null = $input | Out-String; exit 0')
        $r.TimedOut | Should -BeFalse
        $r.ExitCode | Should -Be 0
    }
}

Describe 'New-OperatorPrompt' {

    It 'entrega a missao na primeira iteracao, sem log de falha' {
        $p = New-OperatorPrompt -MissionText 'OBJETIVO: criar o arquivo X' -Iteration 1
        $p | Should -Match 'OBJETIVO: criar o arquivo X'
        $p | Should -Not -Match 'FALHA DA ITERACAO'
    }

    It 'anexa a saida real do gate a partir da segunda iteracao' {
        # O operario corrige contra a saida da ferramenta, nao contra o resumo
        # que o gerente faria dela.
        $p = New-OperatorPrompt -MissionText 'OBJETIVO: X' -Iteration 2 -FailureLog 'erro: simbolo nao encontrado'
        $p | Should -Match 'FALHA DA ITERACAO 1'
        $p | Should -Match 'simbolo nao encontrado'
    }

    It 'nao anexa secao de falha quando o log vem vazio' {
        $p = New-OperatorPrompt -MissionText 'OBJETIVO: X' -Iteration 3 -FailureLog '   '
        $p | Should -Not -Match 'FALHA DA ITERACAO'
    }
}

Describe 'ConvertTo-OraclePath' {

    It 'trata NENHUM como declaracao explicita de ausencia' {
        (ConvertTo-OraclePath -Declaration 'NENHUM').Count | Should -Be 0
        (ConvertTo-OraclePath -Declaration '').Count       | Should -Be 0
    }

    It 'separa por virgula e por ponto e virgula' {
        (ConvertTo-OraclePath -Declaration 'tests/, spec/; e2e/').Count | Should -Be 3
    }

    It 'normaliza barra invertida para o separador do pathspec do git' {
        # O pathspec do git usa barra normal nos dois sistemas operacionais.
        # Sem normalizar, um caminho escrito no estilo Windows nao casaria e o
        # oraculo entraria no patch sem ninguem perceber.
        ConvertTo-OraclePath -Declaration 'engine\tests' | Should -Be 'engine/tests'
    }
}

Describe 'New-FilteredPatchArgument' {

    It 'exclui cada caminho do oraculo do diff' {
        $a = New-FilteredPatchArgument -BaseCommit 'abc' -OraclePaths @('tests/', 'spec/')
        ($a -join ' ') | Should -BeLike '*:(exclude)tests/*'
        ($a -join ' ') | Should -BeLike '*:(exclude)spec/*'
    }

    It 'usa --binary, para que alteracao binaria nao vire apenas um aviso' {
        (New-FilteredPatchArgument -BaseCommit 'abc' -OraclePaths @()) | Should -Contain '--binary'
    }

    It 'sem oraculo, nao emite nenhuma exclusao' {
        $a = New-FilteredPatchArgument -BaseCommit 'abc' -OraclePaths @()
        ($a -join ' ') | Should -Not -BeLike '*exclude*'
    }
}

Describe 'Invoke-Gate -- medicao versus reprovacao' {

    It 'trata comando com sintaxe invalida como nao-medicao' {
        # Um erro de digitacao no TEST_CMD faz o shell sair com 1. Sem esta
        # checagem, o motor consumiria uma iteracao contra o operario por um
        # defeito que esta na missao, nao no trabalho dele.
        $r = Invoke-Gate -Name 'sintaxe' -Command 'if ( {' -WorkingDirectory $TestDrive `
                         -LogPath (Join-Path $TestDrive 'sintaxe.log')
        $r.ExitCode | Should -Be 2
        $r.Status   | Should -Be 'INDETERMINADO'
        $r.ExitCode | Should -Not -Be 1
    }

    It 'persiste o exit code em disco, ao lado do log' {
        # Dois gates silenciosos, um com 0 e outro com 1, produzem logs
        # identicos. Sem o exit code gravado, o auditor precisa confiar na
        # palavra do motor para saber qual aconteceu.
        $log = Join-Path $TestDrive 'meta.log'
        $r = Invoke-Gate -Name 'silencioso' -Command 'exit 1' -WorkingDirectory $TestDrive -LogPath $log
        Test-Path -LiteralPath $r.MetaPath | Should -BeTrue
        $meta = Get-Content -LiteralPath $r.MetaPath -Raw | ConvertFrom-Json
        $meta.exit_code | Should -Be 1
        $meta.status    | Should -Be 'FAIL'
        $meta.name      | Should -Be 'silencioso'
    }

    It 'trata estouro de tempo como nao-medicao' {
        $r = Invoke-Gate -Name 'lento' -Command 'Start-Sleep -Seconds 30' -WorkingDirectory $TestDrive `
                         -LogPath (Join-Path $TestDrive 'lento.log') -TimeoutSeconds 30
        # 30s e o piso aceito pelo wrapper; o comando dorme exatamente isso.
        # O que importa aqui e que um estouro nunca vira exit 1.
        $r.ExitCode | Should -Not -Be 1
    }
}
