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
        }
    }

    It 'admite uma missao completa sem pre-requisitos' {
        $r = Test-MissionAdmission -Mission $script:Completa
        $r.Admitted      | Should -BeTrue
        $r.ExitCode      | Should -Be 0
        $r.HumanDecision | Should -BeFalse
    }

    It 'reprova quando falta qualquer campo obrigatorio' {
        foreach ($field in Get-RequiredMissionField) {
            $mission = $script:Completa.Clone()
            $mission.Remove($field)
            $r = Test-MissionAdmission -Mission $mission
            $r.Admitted | Should -BeFalse -Because "faltando $field"
            $r.ExitCode | Should -Be 1
            ($r.Reasons -join ' ') | Should -Match $field
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
