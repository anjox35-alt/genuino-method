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
  sendo reportada, e medida no fim CERTO.

A segunda regra existe porque a correcao mais barata e errada: desistir de
contar quando ha aspas na linha. Isso passa no primeiro caso e deixa o gate mudo
em quase todo arquivo real, porque quase todo arquivo real tem string.

## O que a correcao NAO pode ser

Um caso especial para `StartsWith`, para PowerShell, ou para a sequencia exata
que apareceu no defeito. O oraculo usa `Where-Object` porque foi o caso medido,
mas a regra e sobre chave em string literal, em qualquer das linguagens que o
gate mede.

Tres rodadas de contra-auditoria independente derrubaram versoes anteriores do
oraculo antes de ele virar contrato. O registro esta em
`audits/2026-08-31-oraculo-check-bloat/AUDITORIA.md`.

WRITE_SET: mcp/src/genuino_mcp/gates.py
ORACULO: mcp/tests/

TEST_CMD: $env:UV_CACHE_DIR="$env:TEMP/genuino-uv-cache"; $env:UV_LINK_MODE='copy'; Set-Location mcp; uv run --offline python -m pytest tests/test_gates.py -q --basetemp="$env:TEMP/genuino-pytest-$PID"; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; uv run --offline python -m ruff check .; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; uv run --offline python -m ruff format --check .; exit $LASTEXITCODE

FRONTEIRA: um humano roda o gate de publicacao sobre a arvore inteira, antes de um push, e le o relatorio
GATE_DA_FRONTEIRA: $env:UV_CACHE_DIR="$env:TEMP/genuino-uv-cache"; $env:UV_LINK_MODE='copy'; Set-Location mcp; uv run --offline python -m genuino_mcp.check_tree ..; exit $LASTEXITCODE
PRE_REQUISITOS_HUMANOS: cache do uv aquecido em TEMP/genuino-uv-cache. O operario roda sem rede e nao alcanca o cache global; o motor nao verifica isso, e por isso este campo existe.

## Nota sobre o ambiente do operario

A primeira tentativa desta missao abortou com `ESCALAR` e exit 2, sem consumir
iteracao. O operario diagnosticou o defeito corretamente e entao parou, porque o
`TEST_CMD` que o gerente escreveu nao rodava no sandbox dele:

```
error: Failed to initialize cache at AppData/Local/uv/cache
  Caused by: ... sdists-v9/.git : Acesso negado. (os error 5)
```

Sondagem posterior mediu as fronteiras reais do `--sandbox workspace-write`:

| Alvo | Resultado medido |
|---|---|
| escrever no worktree | permitido |
| escrever em TEMP | permitido |
| escrever no cache global do uv | **negado** |
| rede | **desabilitada** -- `SSL connection could not be established` |

Nao era ACL do host: era o sandbox cumprindo o desenho. Liberar a permissao do
cache global nao resolveria, e o operario nao tinha como distinguir os dois
casos de dentro da caixa -- ele ofereceu as duas leituras, o que estava certo.

O cache em `TEMP/genuino-uv-cache` foi aquecido pelo gerente, que tem rede.
Verificado: 77 MB, e um projeto limpo criou o venv inteiro com
`uv sync --offline` apontando so para ele, exit 0.

### Por que `python -m` e nao o executavel

O Controle de Aplicativo do Windows bloqueia o `pytest.exe` RECEM-CRIADO no
`.venv` do worktree, com `os error 4551`. Medido: numa execucao o shim foi
bloqueado; numa seguinte, com o venv ja existente, ele passou. Bloqueio
intermitente e pior que bloqueio constante, porque produz `exit 2` sem padrao.

`python -m pytest` nao spawna o shim gerado, e o interpretador passa nos dois
casos. Isso nao contorna o controle de seguranca: usa um caminho que ele ja
autoriza. O operario recusou explicitamente contornar, e estava certo.

### Por que `--basetemp` fora do repo e unico por processo

O `tmp_path` do pytest escreve em `%TEMP%/pytest-of-<usuario>`, que o gerente ja
criou nas proprias execucoes. O operario escreve em TEMP, mas nao dentro de um
diretorio preexistente com outro dono: `PermissionError [WinError 5]`.

A primeira tentativa apontou o basetemp para `.pytest-tmp/` DENTRO do worktree,
ignorado pelo git. Isso tornou o oraculo INSATISFAZIVEL: `iter_text_files` lista
arquivos com `git ls-files --others --exclude-standard`, entao com as fixtures
num diretorio ignorado dentro do repositorio `scan_secrets` e `check_bloat`
deixam de enxerga-las, e seis testes que exigem `FAIL` recebem `PASS`.

Medido nos dois lados: basetemp dentro do repo da exit 1 por esse motivo, fora
do repo da exit 0. O operario gastou duas iteracoes contra esse contrato
impossivel e entregou o patch certo nas duas. O defeito era do gerente.

Um caminho unico por processo evita a colisao de ACL, porque cada execucao cria
o seu em vez de reusar um diretorio preexistente com outro dono.

## STOP CONDITIONS

- Alterar qualquer arquivo em `mcp/tests/` e violacao de oraculo: os testes de
  aceitacao sao do gerente. Adicionar teste proprio e permitido apenas fora
  desse caminho, e nunca enfraquecendo os existentes.
- Escrever fora de `mcp/src/genuino_mcp/gates.py` reprova a iteracao. Isso vale
  inclusive para arquivo de cache ou diretorio temporario criado no worktree: o
  motor roda `git add -A` antes de comparar, e o que nao estiver no `.gitignore`
  aparece como violacao nomeada.
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
