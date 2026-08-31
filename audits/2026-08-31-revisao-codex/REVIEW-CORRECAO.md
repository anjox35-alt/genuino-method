# Auditoria da correcao allowlist — Codex CLI

**Auditor:** Codex CLI (GPT-5), invocado como revisor independente.
**Alvo:** commit `b685fe6`, a correcao que inverteu a blocklist do ORACULO em
allowlist de WRITE_SET.
**Data:** 2026-08-31.
**Papel:** revisor. Nao escreveu codigo neste repositorio.

## Procedencia deste arquivo

O Codex CLI emite a transcricao completa da sessao: saida de `git blame
--porcelain`, paginas de documentacao do Git, e o proprio codigo auditado com
numeracao de linha. O dump original tinha 13.150 linhas (606 KB), das quais 121
eram o relatorio — impresso duas vezes, identicas.

Aqui esta a analise, uma vez. O que foi removido: transcricao de ferramenta,
que e reproduzivel a partir do commit auditado e nao e conclusao de ninguem.
Nenhuma frase de analise foi cortada ou reescrita.

O dump integral esta registrado em `attic/README.md`.

---

Conclusão: a correção fecha o `conftest.py` lateral somente quando o `WRITE_SET` é literal, positivo e estreito. Ela não fecha, em geral, a influência do operário sobre a medição.

Limite de integridade: durante a auditoria, `HEAD` avançou de `b685fe6` para `642f710` e surgiram modificações locais em dois arquivos do motor. Eu não fiz essas escritas. Portanto, todas as referências abaixo são exclusivamente a `b685fe6`; o estado atual não foi auditado.

## CONFIRMADO

### 1. Allowlist não é fronteira de integridade completa

**Crítico — código/configuração legitimamente allowlisted pode falsificar o gate.**

- Arquivos/linhas: `b685fe6:engine/Invoke-GreenLoop.ps1:261-313`; `b685fe6:engine/GenuinoEngine.psm1:251-267`.
- A verificação termina antes de o patch ser aplicado. Depois, o código allowlisted roda normalmente, sem sandbox do gate.
- Cenário concreto: `WRITE_SET: src/pkg/__init__.py`, `TEST_CMD: python -m pytest tests/`. O arquivo importado chama `os._exit(0)` durante a coleta. O processo termina com zero sem executar o oráculo; o motor aceita GREEN.
- Equivalente de configuração: `WRITE_SET: package.json` com `TEST_CMD: npm test` permite trocar o próprio script `test` por um comando que retorna zero.

Logo, o conftest externo está fechado no transporte, mas a medição continua executando entrada adversarial no mesmo domínio de confiança do runner.

**Alto — diretório ou glob allowlisted autoriza também arquivos de controle internos.**

- Arquivos/linhas: `GenuinoEngine.psm1:326-330,478-480`.
- `WRITE_SET: src/` autoriza qualquer arquivo novo em `src/`. Se o comando for `pytest src/`, `src/conftest.py` viaja legitimamente.
- Um pathspec simples como `engine/*` casa também descendentes em `engine/tests/`; isso foi reproduzido com Git 2.55.

**Alto — o campo aceita pathspecs que não são allowlists.**

- `WRITE_SET: :` significa “sem restrição de pathspec”. Reproduzi que ele seleciona todos os cinco arquivos alterados em `b685fe6`.
- `WRITE_SET: :!tests/` é exclude-only e recria uma blocklist.
- `WRITE_SET: :(attr:permitido)` é mutável: Git avalia atributos contra o working tree. Alterar `.gitattributes` pode retroativamente classificar `.gitattributes` e `tests/conftest.py` como permitidos.

O código apenas verifica `Count > 0` em `Invoke-GreenLoop.ps1:154-161`; não exige pathspec positivo, literal ou congelado.

**Arquivo externo ao repositório: não coberto.**

`Invoke-Gate` apenas fixa o diretório corrente. Se `TEST_CMD` lê um caminho absoluto, `..`, serviço ou estado externo mutável, WRITE_SET/ORACULO não o congela nem o protege. A exploração depende das permissões do host, mas a ausência de controle está confirmada.

### 2. `ls-tree` e `diff` não têm semântica equivalente

**Baixo — divergência real, porém fail-closed.**

- Arquivos/linhas: `GenuinoEngine.psm1:357-362`; `Invoke-GreenLoop.ps1:205-208`.
- Reproduzido:

  - `ls-tree ... -- engine/*.ps1`: exit 0, vazio.
  - `diff ... -- engine/*.ps1`: casa arquivos.
  - `ls-tree` rejeita `:(glob)`, `:(icase)`, `:(attr)` e `:(exclude)` com exit 128; `diff` aceita.

A função converte ambos os casos em `$false`, e o loop aborta com exit 2. Portanto não achei falso GREEN nessa direção, mas um ORACULO válido com glob é diagnosticado incorretamente como typo.

Para literal, diretório, `:/...` e `:(literal)...`, não encontrei divergência de casamento.

**Baixo/Médio — exclusão do ORACULO quebra com magia aceita.**

- Arquivo/linhas: `GenuinoEngine.psm1:460-462,479-480`.
- O validador aceita `:/engine/GenuinoEngine.psm1`, mas a exclusão vira `:(exclude):/engine/GenuinoEngine.psm1`.
- Reproduzi que essa forma não exclui o arquivo do patch.

`Get-OracleViolation` normalmente reprova antes, então não é bypass autônomo; é a defesa redundante prometida que não existe para esses pathspecs.

### 3. `Get-PathOutsideWriteSet` não é correto para todos os nomes/operações

**Médio — rename de fora para dentro escapa.**

- Arquivo/linhas: `GenuinoEngine.psm1:385-408`.
- Cenário: `fora/config.ps1` é renomeado para `src/config.ps1`, com `WRITE_SET: src/`.
- O diff completo detecta rename e `--name-only` mostra apenas o destino pós-imagem.
- O diff filtrado também mostra `src/config.ps1`.
- A subtração conclui falsamente que nada fora foi tocado.

A deleção externa não viaja no patch, mas a violação deixa de ser registrada e o estado medido difere do estado do operário.

**Médio — a subtração textual tem colisões.**

- `.Trim()` em `:393` e `:407`.
- `-notcontains` em `:408` é case-insensitive.

Em filesystem case-sensitive, um `src/foo` permitido pode mascarar `SRC/FOO` externo. Nomes `foo`, ` foo` e `foo ` também podem colidir após `Trim()`.

Casos sem defeito encontrado:

- deleção simples: detectada;
- mudança somente de modo: detectada quando `core.fileMode` a considera mudança;
- espaço interno e acento: as duas chamadas geram a mesma representação;
- nomes C-quoted pelo Git: a comparação permanece igual.

### 4. Consumo da iteração

Não encontrei defeito em `$script:state.consumed = $iteration` (`Invoke-GreenLoop.ps1:280-290`).

O operário terminou, os dois diffs foram executados e a violação foi determinada. Isso é reprovação medida, portanto exit 1 e uma iteração consumida são coerentes. Sentinela, falha do operador e gate indeterminado abortam antes do consumo.

Se a política desejada fosse permitir nova tentativa após violação, o ponto a mudar seria o `Stop-Loop` terminal, não a contagem.

### 5. Os oito testes novos não provam o caminho real

**Alto — todos passam com o enforcement do orquestrador quebrado.**

`Invoke-Loop` sempre acrescenta `-DryRun` em `InvokeGreenLoop.Tests.ps1:48-53`; o script sai em `Invoke-GreenLoop.ps1:233-236`, antes do ramo corrigido em `:240-330`. Os quatro últimos testes chamam helpers diretamente.

| Teste | O que prova | O que deixa passar |
|---|---|---|
| `:239` typo do ORACULO | Rejeição de literal inexistente | Não cobre glob/semântica Git |
| `:258` ORACULO real | Aceitação de literal real | Pode ignorar o commit informado |
| `:274` WRITE_SET NENHUM | Guard específico funciona | Não prova uso posterior da allowlist |
| `:291` WRITE_SET ausente | Exit/texto final | Individualmente passa se o campo sair de `RequiredMissionFields`, pois o guard vazio ainda reprova |
| `:327` conftest externo | Contém os dois nomes externos | Um helper que retorna **todos** os arquivos passa; falta negar `src/app.txt` |
| `:333` oráculo adulterado | Helper encontra o arquivo | Não prova que a violação reprova |
| `:338` patch filtrado | Melhor teste: mata a blocklist antiga no helper | A chamada real do orquestrador pode usar diff não filtrado |
| `:347` real versus typo | Dois pathspecs literais | Não cobre glob, magia nem equivalência com `diff` |

Mutantes que removam `Invoke-GreenLoop.ps1:270-290`, eliminem a sentinela, removam o consumo ou revertam apenas a geração real do patch passam os oito. Além disso, o fixture é `conftest.txt`, e nenhum `TEST_CMD` o lê: prova transporte Git, não o bypass ponta a ponta.

Não executei Pester porque os testes criam repositórios e arquivos temporários, contrariando sua proibição de escrita.

## HIPÓTESES condicionais

- **Symlink — Alto:** o código não rejeita modo `120000` nem canonicaliza o alvo. Em host com symlinks reais, um link allowlisted pode apontar para conteúdo ignorado/externo ao patch. Neste checkout, `core.symlinks=false`; não reproduzi.
- **Submódulo — Médio:** o alvo não contém gitlink. Em outro repositório, o detector trata o submódulo como um único caminho e `git apply` sem `--index` não materializa necessariamente o commit registrado no patch. Não há prova de equivalência entre conteúdo medido e gitlink arquivado.

Em suma: a inversão para allowlist corrige o exploit lateral específico sob um envelope estreito, mas ainda não sustenta a afirmação geral de que o operário não pode influenciar a medição.

Higiene de segurança: analisei somente código versionado, o relatório anterior e documentação Git local. Um metadado pessoal apareceu em saída de blame e foi omitido. Pode enviar para IA: parcialmente, com esse metadado redigido. Pode copiar para o projeto: não — nenhuma cópia ou escrita foi feita.
