# Julgamento Técnico dos 17 Achados da Revisão Adversarial (Codex)

Como Juiz Técnico, realizei a auditoria estática e independente do código-fonte fornecido ([`Invoke-GreenLoop.ps1`](file:///engine/Invoke-GreenLoop.ps1), [`GenuinoEngine.psm1`](file:///engine/GenuinoEngine.psm1) e [`GenuinoEngine.Tests.ps1`](file:///engine/tests/GenuinoEngine.Tests.ps1)) confrontando cada uma das 17 alegações do relatório de auditoria (`audits/2026-08-31-revisao-codex/REVIEW-REPORT.md`).

---

## 1. Tabela Consolidada de Vereditos

| # | Achado | Veredito | Severidade Original | Severidade Julgada |
|:---|:---|:---:|:---:|:---:|
| **1** | Operário pode alterar o próprio oráculo | **PROCEDE** | Crítico | **Crítico** |
| **2** | Qualquer diff irrelevante substitui ausência de baseline RED | **PROCEDE** | Alto | **Alto** |
| **3** | O próprio gate pode fabricar o diff atribuído ao operário | **PROCEDE** | Alto | **Alto** |
| **4** | Erro textual do `git diff` é aceito como patch | **PROCEDE** | Crítico | **Alto** |
| **5** | Contrato de 3 faixas não é imposto aos comandos dos gates | **PROCEDE** | Crítico | **Crítico** |
| **6** | Exit não zero do Codex lançado é ignorado | **PROCEDE** | Alto | **Alto** |
| **7** | Exceções ambientais podem escapar como exit 1 do script | **PROCEDE** | Alto | **Alto** |
| **8** | Exit codes dos gates não são persistidos | **PROCEDE** | Crítico | **Médio** |
| **9** | Commits no worktree desaparecem do patch | **PROCEDE** | Crítico | **Crítico** |
| **10** | Não é possível reconstruir exatamente o estado medido | **PROCEDE** | Alto | **Médio** |
| **11** | O orquestrador inteiro está fora dos 27 testes | **PROCEDE** | Crítico | **Crítico** |
| **12** | O teste dos campos obrigatórios usa produção como oráculo | **PROCEDE** | Crítico | **Médio** |
| **13** | Há asserções nos testes que passam com comportamento quebrado | **PROCEDE** | Alto | **Médio** |
| **14** | `runId` colide dentro do mesmo segundo | **PROCEDE** | Alto | **Médio** |
| **15** | Falha de evidência impede cleanup; falha de cleanup é ocultada | **PROCEDE** | Crítico | **Alto** |
| **16** | Bloqueios sem timeout efetivo e recursos sem descarte determinístico | **PROCEDE** | Alto | **Alto** |
| **17** | TOCTOU entre execução do gate e geração do patch | **PROCEDE** | Alto | **Médio** |

---

## 2. Julgamento Detalhado por Achado

### Achado 1: O operário pode alterar o próprio oráculo
- **Veredito:** `PROCEDE`
- **Severidade:** **Crítico** (Mantida)
- **Localização:** [`Invoke-GreenLoop.ps1:189–195, 217–224`](file:///engine/Invoke-GreenLoop.ps1#L189-L224); [`GenuinoEngine.psm1:397–402`](file:///engine/GenuinoEngine.psm1#L397-L402).
- **Justificativa:** O Codex recebe permissão de escrita em todo o worktree (`--sandbox workspace-write` na linha 193) e os gates executam os testes diretamente nesse diretório modificado (linha 217). A regra "não altere os testes" existe apenas como texto no prompt (linha 399), sem validação por hash, snapshot ou bloqueio de escrita nos arquivos de teste.

---

### Achado 2: Qualquer diff irrelevante substitui a ausência de baseline RED
- **Veredito:** `PROCEDE`
- **Severidade:** **Alto** (Mantida)
- **Localização:** [`Invoke-GreenLoop.ps1:168–180, 248–256`](file:///engine/Invoke-GreenLoop.ps1#L168-L256); [`GenuinoEngine.psm1:431–432`](file:///engine/GenuinoEngine.psm1#L431-L432).
- **Justificativa:** O motor não executa os gates antes da primeira delegação para comprovar que o estado inicial falhava. Como `Test-WorktreeHasChanges` (linha 248) apenas checa se `git status --porcelain` retornou alguma linha, qualquer edição cosmética (como alterar um `README.md`) em um projeto cujos testes já passavam em `HEAD` faz o motor declarar `GREEN` falso.

---

### Achado 3: O próprio gate pode fabricar o diff atribuído ao operário
- **Veredito:** `PROCEDE`
- **Severidade:** **Alto** (Mantida)
- **Localização:** [`Invoke-GreenLoop.ps1:217–255`](file:///engine/Invoke-GreenLoop.ps1#L217-L255); [`GenuinoEngine.psm1:431–432`](file:///engine/GenuinoEngine.psm1#L431-L432).
- **Justificativa:** A verificação de alterações ocorre estritamente após a execução dos gates. Se o comando de teste gerar arquivos não ignorados (e.g. `.coverage`, logs locais ou arquivos temporários), `Test-WorktreeHasChanges` retornará `$true` mesmo sem intervenção do operário. Além disso, com `-DryRun`, a verificação de diff é explicitamente ignorada (linha 248), permitindo `GREEN` com exit 0 sem nenhuma alteração.

---

### Achado 4: Erro textual do `git diff` é aceito como patch
- **Veredito:** `PROCEDE`
- **Severidade:** **Alto** (Ajustada de Crítico para Alto, pois requer falha do Git no momento do diff).
- **Localização:** [`Invoke-GreenLoop.ps1:281–297`](file:///engine/Invoke-GreenLoop.ps1#L281-L297); [`GenuinoEngine.psm1:370`](file:///engine/GenuinoEngine.psm1#L370).
- **Justificativa:** O exit code de `git diff` é descartado. Se o comando falhar (e.g., exit 128 com mensagem `fatal: ...` no stderr), o texto de erro é gravado em `diff.patch` (linha 283) e, como a saída não é nula/espaço em branco, a condição da linha 291 é ignorada, mantendo o veredito `GREEN`.

---

### Achado 5: O contrato de três faixas não é imposto aos comandos dos gates
- **Veredito:** `PROCEDE`
- **Severidade:** **Crítico** (Mantida)
- **Localização:** [`GenuinoEngine.psm1:202–205, 235–238, 256`](file:///engine/GenuinoEngine.psm1#L202-L256); [`Invoke-GreenLoop.ps1:242–243`](file:///engine/Invoke-GreenLoop.ps1#L242-L243).
- **Justificativa:** O PowerShell retorna exit code 1 por padrão para falhas de sintaxe, executáveis inexistentes ou arquivos de teste não encontrados. O motor mapeia cegamente qualquer exit 1 para `FAIL` (linha 236) e consome iterações (`Test-IterationConsumed` na linha 256), tratando falhas de infraestrutura/ambiente do gate como se fossem reprovações legítimas do código sob teste.

---

### Achado 6: Exit não zero do Codex lançado é ignorado
- **Veredito:** `PROCEDE`
- **Severidade:** **Alto** (Mantida)
- **Localização:** [`Invoke-GreenLoop.ps1:189–213, 242`](file:///engine/Invoke-GreenLoop.ps1#L189-L242).
- **Justificativa:** O motor apenas aborta a delegação se o processo não iniciar ou estourar o tempo (`-not $operator.Launched -or $operator.TimedOut` na linha 201). Se o Codex falhar com exit 1 ou 2 por erro de autenticação, quota ou configuração, o motor prossegue para os gates, mede o worktree intocado, recebe exit 1 do teste e consome a iteração (linha 242) indevidamente.

---

### Achado 7: Exceções ambientais podem escapar como exit 1 do próprio script
- **Veredito:** `PROCEDE`
- **Severidade:** **Alto** (Mantida)
- **Localização:** [`Invoke-GreenLoop.ps1:61, 89–142, 163, 167–324`](file:///engine/Invoke-GreenLoop.ps1#L61-L324); [`GenuinoEngine.psm1:352`](file:///engine/GenuinoEngine.psm1#L352).
- **Justificativa:** O script roda sob `$ErrorActionPreference = 'Stop'` (linha 61) e não possui um bloco `catch` global que capture exceções de E/S (disco cheio, permissão ao criar `runs/`, quebra de pipe em `StandardInput.Write`). Ao terminar por exceção não tratada, o host PowerShell encerra com exit 1, violando o contrato externo que reserva exit 1 exclusivamente para reprovação medida.

---

### Achado 8: Exit codes dos gates não são persistidos
- **Veredito:** `PROCEDE`
- **Severidade:** **Médio** (Ajustada de Crítico para Médio; trata-se de um defeito de auditabilidade e telemetria, não de corrupção do fluxo de controle).
- **Localização:** [`GenuinoEngine.psm1:205`](file:///engine/GenuinoEngine.psm1#L205); [`Invoke-GreenLoop.ps1:225, 301–318`](file:///engine/Invoke-GreenLoop.ps1#L225-L318).
- **Justificativa:** `Invoke-Gate` grava apenas o texto do stdout/stderr no log (`g5-testes.log`), descartando o exit code do arquivo. O exit code individual de cada gate por iteração é impresso no console via `Write-Host` (linha 225), mas não é persistido em `verdict.json` nem nos arquivos de log.

---

### Achado 9: Commits no worktree desaparecem do patch
- **Veredito:** `PROCEDE`
- **Severidade:** **Crítico** (Mantida)
- **Localização:** [`Invoke-GreenLoop.ps1:138, 151–152, 281–283`](file:///engine/Invoke-GreenLoop.ps1#L138-L283); [`GenuinoEngine.psm1:431`](file:///engine/GenuinoEngine.psm1#L431).
- **Justificativa:** Na captura de evidências, o motor executa `git diff --cached HEAD` (linha 282). Se o operário realizar commits no worktree, o `HEAD` avança. A comparação contra o `HEAD` atual resulta em um diff vazio para as alterações já commitadas. O branch é então apagado com `git branch -D` (linha 152), destruindo o código implementado sem arquivá-lo no patch.

---

### Achado 10: Não é possível reconstruir exatamente o estado medido
- **Veredito:** `PROCEDE`
- **Severidade:** **Médio** (Ajustada de Alto para Médio; é uma limitação de rastreabilidade forense).
- **Localização:** [`Invoke-GreenLoop.ps1:281–288, 301–318`](file:///engine/Invoke-GreenLoop.ps1#L281-L318).
- **Justificativa:** `verdict.json` omite o commit SHA base, a árvore Git (tree ID), os hashes dos arquivos de missão e as versões das ferramentas. Além disso, `git diff` não utiliza `--binary`, truncando arquivos binários.

---

### Achado 11: O orquestrador inteiro está fora dos 27 testes
- **Veredito:** `PROCEDE`
- **Severidade:** **Crítico** (Mantida)
- **Localização:** [`GenuinoEngine.Tests.ps1:9–12`](file:///engine/tests/GenuinoEngine.Tests.ps1#L9-L12).
- **Justificativa:** O arquivo de teste importa unicamente o módulo `GenuinoEngine.psm1`. O script principal [`Invoke-GreenLoop.ps1`](file:///engine/Invoke-GreenLoop.ps1) nunca é executado nem instanciado na suíte; todo o fluxo de criação de worktrees, controle de iterações, fallback de falha e descarte permanece com 0% de cobertura de testes.

---

### Achado 12: O teste dos campos obrigatórios usa produção como oráculo
- **Veredito:** `PROCEDE`
- **Severidade:** **Médio** (Ajustada de Crítico para Médio; trata-se de tautologia em teste unitário).
- **Localização:** [`GenuinoEngine.Tests.ps1:76–84`](file:///engine/tests/GenuinoEngine.Tests.ps1#L76-L84); [`GenuinoEngine.psm1:33–48`](file:///engine/GenuinoEngine.psm1#L33-L48).
- **Justificativa:** O teste itera diretamente sobre `Get-RequiredMissionField` (função de produção). Se um campo for removido de `$script:RequiredMissionFields` em produção, o teste deixará de testá-lo automaticamente e continuará passando verde.

---

### Achado 13: Há asserções nos testes que passam com comportamento quebrado
- **Veredito:** `PROCEDE`
- **Severidade:** **Médio** (Ajustada de Alto para Médio; fragilidade na suíte de testes).
- **Localização:** [`GenuinoEngine.Tests.ps1:16–30, 87–99, 170–175, 177–183, 186–200`](file:///engine/tests/GenuinoEngine.Tests.ps1#L16-L200).
- **Justificativa:** Confirmam-se as asserções vazias ou tautológicas apontadas: a linha 174 busca no log uma string presente no próprio comando; as linhas 177–183 apenas executam `$true | Should -BeTrue`; as linhas 87–99 não validam `ExitCode`; as linhas 16–30 não asserem `GATE_DA_FRONTEIRA`; e as linhas 186–200 não invocam `Process.Start`.

---

### Achado 14: `runId` colide dentro do mesmo segundo
- **Veredito:** `PROCEDE`
- **Severidade:** **Médio** (Ajustada de Alto para Médio; requer execuções simultâneas ou sequenciais em menos de 1 segundo).
- **Localização:** [`Invoke-GreenLoop.ps1:120–130`](file:///engine/Invoke-GreenLoop.ps1#L120-L130).
- **Justificativa:** A formatação `yyyyMMddTHHmmssZ` possui granularidade de 1 segundo sem componente aleatório ou PID. Execuções concorrentes utilizam o mesmo `$runDir` (reutilizado via `New-Item -Force`), disputando o mesmo branch e sobrescrevendo logs.

---

### Achado 15: Falha de evidência impede cleanup; falha de cleanup é ocultada
- **Veredito:** `PROCEDE`
- **Severidade:** **Alto** (Ajustada de Crítico para Alto).
- **Localização:** [`Invoke-GreenLoop.ps1:145–153, 278–321`](file:///engine/Invoke-GreenLoop.ps1#L145-L321).
- **Justificativa:** No bloco `finally`, a chamada a `Remove-Worktree` (linha 321) está posicionada após as gravações de arquivo (linhas 283, 288, 318); se ocorrer falha de disco ou permissão ao gravar o JSON, o cleanup não é chamado. Além disso, em `Remove-Worktree`, `$script:cleanupDone = $true` é definido antes dos comandos Git, e os erros de remoção são silenciados com `Out-Null` (linhas 150, 152).

---

### Achado 16: Bloqueios sem timeout efetivo e recursos sem descarte determinístico
- **Veredito:** `PROCEDE`
- **Severidade:** **Alto** (Mantida)
- **Localização:** [`GenuinoEngine.psm1:196–214, 351–376`](file:///engine/GenuinoEngine.psm1#L196-L376).
- **Justificativa:** Em `Invoke-Gate` (linha 202), `& pwsh ... -Command` não possui nenhum mecanismo de timeout. Em `Invoke-ClosedStdinProcess`, a escrita síncrona em `StandardInput` (linha 352) ocorre antes do início da leitura assíncrona dos pipes, permitindo deadlock se o buffer do pipe encher. Ademais, o objeto `Process` não recebe `Dispose()`.

---

### Achado 17: TOCTOU entre execução do gate e geração do patch
- **Veredito:** `PROCEDE`
- **Severidade:** **Médio** (Ajustada de Alto para Médio; corrida improvável em ambiente isolado, mas teoricamente existente).
- **Localização:** [`Invoke-GreenLoop.ps1:217–256, 278–288`](file:///engine/Invoke-GreenLoop.ps1#L217-L288).
- **Justificativa:** Não há congelamento de snapshot ou commit imediato no exato momento em que o gate retorna zero (linha 256). A coleta do diff ocorre apenas no bloco `finally` (linhas 279–282); qualquer alteração no sistema de arquivos entre esses dois pontos entra no `diff.patch` sem ter sido validada pelos gates.

---

## 3. Síntese do Julgamento

Todos os **17 achados procedem tecnicamente** após validação direta contra o código-fonte. Não foram identificados falsos positivos (`NAO_PROCEDE`) nem pontos indeterminados (`AMBIGUO`). 

As divergências em relação ao revisor original limitam-se à calibração de **severidade** em 7 itens (Achados 4, 8, 10, 12, 13, 14, 15 e 17), nos quais o impacto real foi reclassificado para níveis proporcionais ao risco operacional, sem prejuízo da constatação do defeito.
