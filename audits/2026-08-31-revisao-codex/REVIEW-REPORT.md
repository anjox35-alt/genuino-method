# Revisão adversarial do motor — Codex, 2026-08-31

Revisor: Codex (gpt-5.6-sol), `--sandbox read-only`, sem alterar arquivo.
Alvo: `engine/Invoke-GreenLoop.ps1`, `engine/GenuinoEngine.psm1`, `engine/tests/GenuinoEngine.Tests.ps1`.
Commit revisado: 207f09a mais alterações não commitadas do motor.

Encomendada pelo gerente sobre o próprio código, porque quem escreve não
pode ser quem atesta. O relatório abaixo é a saída do revisor, sem edição.

---

Conclusão: eu não atestaria este motor como independente ainda.

Respostas diretas:

1. **Sim**, há caminhos para GREEN sem medição confiável do trabalho.
2. **Sim**, falhas de infraestrutura podem chegar como exit 1 e consumir iterações.
3. **Não**, `runs/` não basta para auditoria independente.
4. **Não**, os 27 testes deixam o orquestrador e várias promessas críticas sem prova.
5. **Sim**, há corrida, bloqueios e caminhos de worktree órfão.

Revisão estritamente estática: não executei a suíte e não alterei nenhum arquivo.

Arquivos: [Invoke-GreenLoop.ps1](</engine/Invoke-GreenLoop.ps1:1>), [GenuinoEngine.psm1](</engine/GenuinoEngine.psm1:1>) e [GenuinoEngine.Tests.ps1](</engine/tests/GenuinoEngine.Tests.ps1:1>).

## Confirmado — 1. GREEN sem medição confiável

1. **Crítico — o operário pode alterar o próprio oráculo**

   - Arquivo/linhas: `Invoke-GreenLoop.ps1:181–195, 217–256`; `GenuinoEngine.psm1:397–402`.
   - O que quebra: Codex recebe `workspace-write` sobre o worktree, e os testes/gates são depois executados nesse mesmo worktree. “Não altere os testes” existe apenas no prompt; não há hash, snapshot, proteção de caminhos ou comparação com a versão escrita pelo gerente.
   - Cenário: o operário enfraquece um teste de aceitação ou altera um script/configuração chamado pelo gate para retornar zero. O gate mede o oráculo adulterado, encontra um diff não vazio e o motor declara GREEN.

2. **Alto — qualquer diff irrelevante substitui a ausência de baseline RED**

   - Arquivo/linhas: `Invoke-GreenLoop.ps1:167–180, 217–256`.
   - O que quebra: os gates não são executados antes da delegação. Depois, basta qualquer alteração detectada por `git status`.
   - Cenário: `HEAD` já passava nos gates; o operário altera somente `README.md`; os gates continuam retornando zero e o motor declara GREEN. Não foi provado que a alteração causou o sucesso.

3. **Alto — o próprio gate pode fabricar o diff atribuído ao operário**

   - Arquivo/linhas: `Invoke-GreenLoop.ps1:217–255`; `GenuinoEngine.psm1:431–432`.
   - O que quebra: `Test-WorktreeHasChanges` só roda depois dos gates.
   - Cenário: o teste cria coverage, snapshot, cache ou arquivo gerado não ignorado e retorna zero. Mesmo sem alteração do operário, esse artefato torna o status não vazio.
   - Variante concreta: com `-DryRun`, isso permite GREEN/exit 0 sem o operário ter sido chamado. O JSON registra `dry_run`, mas o veredito continua GREEN.

4. **Crítico — erro textual do `git diff` é aceito como patch**

   - Arquivo/linhas: `Invoke-GreenLoop.ps1:278–297`; `GenuinoEngine.psm1:331–376`.
   - O que quebra: os exit codes de `git add`, `git diff` e `git diff --name-status` são ignorados. O rebaixamento só ocorre quando `diff.Output` está vazio.
   - Cenário: `git diff` falha com exit 128 e saída `fatal: ...`. Essa mensagem é gravada em `diff.patch`, não é whitespace e, portanto, o GREEN permanece. A promessa “GREEN sem patch capturado deve ser rebaixado” não está efetivamente garantida.

## Confirmado — 2. Ambiente contado como reprovação

5. **Crítico — o contrato de três faixas não é imposto aos comandos dos gates**

   - Arquivo/linhas: `GenuinoEngine.psm1:202–205, 235–256`; `Invoke-GreenLoop.ps1:229–243`.
   - O que quebra: qualquer exit 1 do `pwsh` é classificado como reprovação medida. O motor não distingue falha do produto de falha ao executar a medição.
   - Cenário: executável de teste ausente, erro de parsing, módulo ausente ou arquivo de teste inexistente fazem o shell retornar 1. A iteração é consumida.
   - Cenário provável: o gerente cria um teste de aceitação, mas ainda não o commita. Como o worktree nasce de `HEAD`, o teste não existe nele; sua ausência vira RED consumido.

6. **Alto — exit não zero do Codex lançado é ignorado**

   - Arquivo/linhas: `Invoke-GreenLoop.ps1:189–212`.
   - O que quebra: somente `Launched = false` e `TimedOut = true` abortam. `$operator.ExitCode` não participa da decisão.
   - Cenário: Codex inicia e falha por autenticação, quota, configuração ou runtime, saindo 1/2 sem editar. O motor roda os gates no estado antigo; se retornarem 1, consome a iteração como tentativa medida.

7. **Alto — exceções ambientais podem escapar como exit 1 do próprio script**

   - Arquivo/linhas: `Invoke-GreenLoop.ps1:89–142, 167–321`; `GenuinoEngine.psm1:331–370`.
   - O que quebra: não existe um `catch` superior que normalize exceções ambientais para exit 2. Apenas `Process.Start` é protegido; escrita em stdin, persistência dos logs, criação de `runs/` e várias outras operações podem lançar.
   - Cenário: permissão negada ou disco cheio ao criar/gravar `runs/`, ou `IOException` ao escrever no stdin de um filho que fechou o pipe. O host PowerShell pode terminar com exit 1.
   - Precisão: esse caminho pode não incrementar `$consumed`; ainda assim viola o contrato externo ao publicar 1 para uma impossibilidade de medir.

**Controle correto:** quando um gate efetivamente retorna `>=2`, `Invoke-GreenLoop.ps1:229–242` aborta antes de `$consumed++`. Não encontrei defeito nesse ramo específico.

## Confirmado — 3. Evidência insuficiente em `runs/`

8. **Crítico — exit codes dos gates não são persistidos**

   - Arquivo/linhas: `GenuinoEngine.psm1:202–220`; `Invoke-GreenLoop.ps1:225, 300–318`.
   - O que quebra: os arquivos dos gates contêm apenas a saída textual. Exit code e status ficam no objeto em memória e em `Write-Host`; `verdict.json` traz apenas o veredito agregado.
   - Cenário: um gate silencioso com exit 0 e outro silencioso com exit 1 produzem logs vazios indistinguíveis. O auditor precisa confiar no motor para saber qual aconteceu.

9. **Crítico — commits no worktree desaparecem do patch**

   - Arquivo/linhas: `Invoke-GreenLoop.ps1:137–138, 248, 279–288`; `GenuinoEngine.psm1:431–432`.
   - O que quebra: o motor compara com o `HEAD` atual, não com o commit-base congelado antes da delegação. `git status --porcelain` também ignora commits já feitos.
   - Cenário: a implementação é commitada no worktree e sobra um `WORKER-REPORT.md` não commitado. O status vê somente o relatório; os gates passam; `git diff --cached HEAD` arquiva apenas o relatório. A implementação fica no commit da branch que depois é apagada.

10. **Alto — não é possível reconstruir exatamente o estado medido**

   - Arquivo/linhas: `Invoke-GreenLoop.ps1:273–318`.
   - Faltam: SHA do commit-base, tree ID final medido, versão/hash do motor, snapshot/hash autenticado da missão, resultados de cada comando de captura e versões das ferramentas.
   - `git diff` também não usa `--binary`; mudanças binárias podem virar apenas “Binary files differ”. Arquivos ignorados não entram, e filtros Git podem alterar a representação.
   - Não há manifest de hashes, assinatura ou armazenamento append-only. Alterações posteriores nos logs, patch ou JSON são indetectáveis.
   - `human_decision` é somente booleano: não registra autor, instante próprio ou declaração aprovada.

Portanto, outra pessoa pode fazer diagnóstico com `runs/`, mas não reproduzir nem atestar o veredito sem confiar no motor.

## Confirmado — 4. Os testes não provam as promessas centrais

11. **Crítico — o orquestrador inteiro está fora dos 27 testes**

   - Arquivo/linhas: `GenuinoEngine.Tests.ps1:9–12`.
   - O que quebra: a suíte apenas importa `GenuinoEngine.psm1`; não chama `Invoke-GreenLoop.ps1`.
   - Mutantes invisíveis por inspeção: substituir o orquestrador por `exit 0`, remover o gate de fronteira, incrementar a iteração antes de tratar `>=2`, remover o cleanup ou voltar para `git diff HEAD`.
   - Não há teste de `Test-WorktreeHasChanges`, arquivo untracked, `diff.patch`, `verdict.json`, worktree ou cleanup.

12. **Crítico — o teste dos campos obrigatórios usa produção como oráculo**

   - Arquivo/linhas: `GenuinoEngine.Tests.ps1:76–84`; `GenuinoEngine.psm1:33–38`.
   - O que quebra: o teste itera sobre `Get-RequiredMissionField`.
   - Cenário: remover `TEST_CMD` da lista de produção também remove automaticamente o caso que deveria detectar sua ausência. O teste “falta qualquer campo obrigatório” continuaria passando.

13. **Alto — há asserções que passam com comportamento quebrado**

   - `GenuinoEngine.Tests.ps1:170–175`: o marcador procurado no log aparece literalmente no próprio comando. Uma implementação que grave `$Command` em vez da saída ainda passa.
   - Linhas `177–183`: o teste de isolamento descarta o resultado e termina com `$true | Should -BeTrue`. Ele não prova que `exit 42` foi executado nem capturado.
   - Linhas `87–99`: campo vazio e pré-requisito não aprovado não verificam o `ExitCode`; poderiam devolver 0 ou 2 mantendo `Admitted = false`.
   - Linhas `16–30`: o fixture contém `GATE_DA_FRONTEIRA`, mas nenhuma asserção verifica que o parser o leu.
   - Linhas `186–200`: “Process.Start aceita” apenas verifica que o caminho existe; não chama `Process.Start`.

## Confirmado — 5. Corridas, bloqueios e worktrees sobreviventes

14. **Alto — `runId` colide dentro do mesmo segundo**

   - Arquivo/linhas: `Invoke-GreenLoop.ps1:120–130`.
   - O que quebra: run, branch e worktree usam timestamp com precisão de um segundo; `New-Item -Force` reutiliza o diretório.
   - Cenário: duas execuções da mesma missão no mesmo segundo disputam a mesma branch/worktree e escrevem nos mesmos `iter1`, `diff.patch` e `verdict.json`. Uma execução sequencial rápida também pode sobrescrever a anterior. Isso contradiz “jamais sobrescrito”.

15. **Crítico — falha de evidência impede o cleanup; falha de cleanup é ocultada**

   - Arquivo/linhas: `Invoke-GreenLoop.ps1:144–153, 269–321`.
   - O que quebra: `Remove-Worktree` é a última instrução do mesmo `finally`. Uma exceção ao gravar patch/JSON interrompe o bloco antes do cleanup.
   - Além disso, `$cleanupDone` vira verdadeiro antes das operações, e os exits de `git worktree remove` e `git branch -D` são descartados.
   - Cenário: disco cheio impede `verdict.json`; worktree e branch sobrevivem. Ou um arquivo bloqueado faz `worktree remove` falhar, mas o run permanece GREEN e nada registra o órfão.
   - `-KeepWorktree` também não é registrado no JSON, então retenção intencional e falha silenciosa são indistinguíveis.

16. **Alto — existem bloqueios sem timeout efetivo e recursos sem descarte determinístico**

   - Arquivo/linhas: `GenuinoEngine.psm1:351–376` e `196–214`.
   - `StandardInput.Write()` ocorre antes das leituras e antes de alcançar `WaitForExit`; pai e filho podem bloquear nos pipes antes do timeout.
   - `Invoke-Gate` não possui timeout.
   - O objeto `Process` nunca recebe `Dispose()`. No timeout, `Kill($true)` tem exceção engolida, não há `WaitForExit` posterior e as leituras não são aguardadas.
   - Cenário: Codex ou gate trava; o processo pode continuar escrevendo ou segurando arquivos enquanto o motor tenta remover o worktree.

17. **Alto — há TOCTOU entre gate e patch**

   - Arquivo/linhas: `Invoke-GreenLoop.ps1:217–288`.
   - O que quebra: não há snapshot/tree ID no instante em que o último gate retorna zero.
   - Cenário: watcher ou processo em background altera o worktree depois do gate e antes de `git add -A`. O patch contém código que nenhum gate mediu.

## Hipóteses e não verificado

- Não verifiquei se atualmente existem worktrees, branches ou runs corrompidos; isso exigiria ampliar o alvo operacional.
- A possibilidade de o operário mover `HEAD` é uma falha de validação confirmada no motor; se o sandbox atual bloqueia escrita nos metadados Git, a exploração pelo Codex fica reduzida, mas gates e outros processos ainda podem mover `HEAD`.
- A ausência de `Dispose()` está confirmada; exaustão concreta de handles nas no máximo 20 iterações não foi demonstrada.
- Não executei os mutantes citados: dizer que seriam invisíveis é inferência estática baseada no fato de que o orquestrador nunca é importado pela suíte.

Também confirmei três pontos positivos: os quatro campos estão hoje na lista de admissão; a aprovação humana é rotulada como decisão no objeto e no JSON; e o relato textual do operário não é usado diretamente para decidir GREEN. Esses controles, porém, não fecham os caminhos acima.
tokens used
97.082
Conclusão: eu não atestaria este motor como independente ainda.

Respostas diretas:

1. **Sim**, há caminhos para GREEN sem medição confiável do trabalho.
2. **Sim**, falhas de infraestrutura podem chegar como exit 1 e consumir iterações.
3. **Não**, `runs/` não basta para auditoria independente.
4. **Não**, os 27 testes deixam o orquestrador e várias promessas críticas sem prova.
5. **Sim**, há corrida, bloqueios e caminhos de worktree órfão.

Revisão estritamente estática: não executei a suíte e não alterei nenhum arquivo.

Arquivos: [Invoke-GreenLoop.ps1](</engine/Invoke-GreenLoop.ps1:1>), [GenuinoEngine.psm1](</engine/GenuinoEngine.psm1:1>) e [GenuinoEngine.Tests.ps1](</engine/tests/GenuinoEngine.Tests.ps1:1>).

## Confirmado — 1. GREEN sem medição confiável

1. **Crítico — o operário pode alterar o próprio oráculo**

   - Arquivo/linhas: `Invoke-GreenLoop.ps1:181–195, 217–256`; `GenuinoEngine.psm1:397–402`.
   - O que quebra: Codex recebe `workspace-write` sobre o worktree, e os testes/gates são depois executados nesse mesmo worktree. “Não altere os testes” existe apenas no prompt; não há hash, snapshot, proteção de caminhos ou comparação com a versão escrita pelo gerente.
   - Cenário: o operário enfraquece um teste de aceitação ou altera um script/configuração chamado pelo gate para retornar zero. O gate mede o oráculo adulterado, encontra um diff não vazio e o motor declara GREEN.

2. **Alto — qualquer diff irrelevante substitui a ausência de baseline RED**
