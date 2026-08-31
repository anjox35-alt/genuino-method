# check-bloat-chave-em-string

OBJETIVO: fazer `_function_end` parar de contar chaves que vivem dentro de
string literal, para que uma funcao curta deixe de ser reportada como longa.

## Por que existe

Este defeito nao foi imaginado: ele bloqueou um push real neste repositorio,
hoje.

`Get-AgyResultEvent`, em `engine/Invoke-Auditor.ps1`, tem 25 linhas. O gate de
publicacao reportou 312 e saiu com 1. A linha responsavel era:

```
Where-Object { $_.Trim().StartsWith('{') }
```

Ela abre duas chaves -- uma de codigo, e uma dentro de uma string -- e fecha
uma. `_function_end` conta `{` e `}` textualmente, sem distinguir string de
codigo. A profundidade nunca volta a zero, a funcao nunca "termina", e passa a
engolir todo o arquivo abaixo dela.

O comentario do proprio `_function_end` ja nomeia a licao, por outro caso:
*gate que acusa o inocente perde a autoridade de acusar o culpado.* Esta missao
fecha a mesma licao pela segunda causa.

## Comportamento esperado

- Funcao curta com chave dentro de aspas: **nao** e reportada como longa, e nao
  engole o codigo abaixo dela.
- Funcao genuinamente longa que tambem contem chave em string: **continua**
  sendo reportada. Esta e a metade que importa mais.

A segunda regra existe porque a correcao mais barata e errada: desistir de
contar quando ha aspas na linha. Isso passa no primeiro caso e deixa o gate mudo
em quase todo arquivo real, porque quase todo arquivo real tem string.

## O que a correcao NAO pode ser

Um caso especial para `StartsWith`, para PowerShell, ou para a sequencia exata
que apareceu no defeito. O oraculo usa `Where-Object` porque foi o caso medido,
mas a regra e sobre chave em string literal, em qualquer das linguagens que o
gate mede.

WRITE_SET: mcp/src/genuino_mcp/gates.py
ORACULO: mcp/tests/

TEST_CMD: $env:UV_LINK_MODE='copy'; Set-Location mcp; uv run pytest tests/test_gates.py -q; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; uv run ruff check .; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; uv run ruff format --check .; exit $LASTEXITCODE

FRONTEIRA: um humano roda o gate de publicacao sobre a arvore inteira, antes de um push, e le o relatorio
GATE_DA_FRONTEIRA: $env:UV_LINK_MODE='copy'; Set-Location mcp; uv run python -m genuino_mcp.check_tree ..; exit $LASTEXITCODE
PRE_REQUISITOS_HUMANOS: NENHUM

## STOP CONDITIONS

- Alterar qualquer arquivo em `mcp/tests/` e violacao de oraculo: os testes de
  aceitacao sao do gerente. Adicionar teste proprio e permitido apenas fora
  desse caminho, e nunca enfraquecendo os existentes.
- Escrever fora de `mcp/src/genuino_mcp/gates.py` reprova a iteracao.
- Dependencia nova: BLOCKED. `re` ja esta importado no modulo, e um parser de
  linguagem inteiro seria inflacao -- a funcao e heuristica declarada, nao
  analisador sintatico.
- Relaxar os tetos de `BloatThresholds` para fazer o teste passar e violacao de
  escopo: a missao e sobre a contagem, nao sobre o limite.

## Nota sobre os testes que ja existem

`test_funcao_longa_nao_engole_o_codigo_abaixo` e
`test_funcao_longa_ainda_e_detectada_com_chaves` cobrem o mesmo par por outra
causa. Os quatro precisam passar juntos. Uma correcao que faca um deles reprovar
trocou um defeito por outro.
