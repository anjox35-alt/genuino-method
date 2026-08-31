# attic — obsoletos preservados

Nada é apagado neste repositório. O que perde função é movido para cá, com
motivo e origem registrados.

A regra existe porque apagar destrói a informação de *por que* algo existia.
Um arquivo no `attic/` responde três perguntas que um `git rm` não responde
sem arqueologia: de onde veio, o que fazia, e por que parou de valer.

## O que NÃO entra aqui

Material dos oito repositórios de origem que foi deliberadamente **não migrado**
não vira entrada do `attic/`. Ele continua nos repositórios de origem, que
seguem existindo. Registrar aqui uma cópia seria duplicar sem consumidor.

O que foi deixado para trás está listado em `docs/procedencia.md`, com o motivo.

## Formato de uma entrada

Cada item movido ganha uma linha na tabela abaixo e mantém o caminho original
dentro de `attic/`, para que a origem seja legível sem consultar o histórico.

| Caminho no attic | Origem | Movido em | Por quê |
|---|---|---|---|
| *(não arquivado — ver nota)* | `audits/2026-08-31-revisao-codex/REVIEW-CORRECAO.md`, dump integral de 13.150 linhas | 2026-08-31 | Transcrição de sessão do Codex CLI: `git blame --porcelain`, documentação do Git colada e o código auditado com numeração. 121 linhas eram relatório, impressas duas vezes. A análise ficou no arquivo; o resto **não foi copiado para cá**. |
| *(não arquivado — ver nota)* | `audits/2026-08-31-revisao-codex/AUDITORIA-PREMISSAS-GEMINI.ndjson`, 71 linhas de protocolo | 2026-08-31 | Transporte bruto da CLI do Gemini: 1 `init`, 69 `step_update`, 1 `result`. O relatório inteiro já está no `.md` de mesmo nome, cujo texto foi reencodado de cp850 para UTF-8 (a CLI gravou mojibake). O `.ndjson` não continha nenhuma conclusão ausente do `.md`. |

### Por que esse item não tem cópia no attic

O dump continha 143 ocorrências de caminho absoluto da máquina de
desenvolvimento e o e-mail do autor repetido em milhares de linhas de saída de
`blame`. Arquivá-lo em `attic/` o publicaria — o `attic/` está no repositório.

Guardar é o padrão desta pasta, e ele cede quando guardar significa publicar
dado pessoal. O conteúdo descartado é reproduzível: são saídas determinísticas
de `git blame`, `git show` e da documentação do Git, sobre o commit `b685fe6`.

Este é o único formato de exceção previsto: **reproduzível a partir de um commit
nomeado, e impróprio para repositório público.** Se um item futuro falhar em
qualquer das duas condições, ele é arquivado.

## Quando esvaziar

Nunca por rotina. Um item sai do `attic/` apenas quando volta a ter função, e
nesse caso volta para a árvore ativa — não é excluído.
