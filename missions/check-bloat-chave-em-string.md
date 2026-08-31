# check-bloat-chave-em-string

OBJETIVO: fazer `_function_end` medir o fim REAL de uma funcao quando ha chave
dentro de string literal, usando o analisador que a plataforma ja fornece em vez
de uma heuristica de expressao regular.

## Estado: reaberta apos ESCALAR por teto da R5

Sete loops rodaram nesta missao em 31/08/2026. Nenhum entregou GREEN mergeado.
A R5 fixa o teto em 3 loops por missao; ele estourou no quarto e ninguem
escalou. O registro esta em `runs/check-bloat-chave-em-string/`.

A causa nao foi o operario. Foi o ESCOPO, que proibia a unica solucao correta:

> "Dependencia nova: BLOCKED. ... um parser de linguagem inteiro seria inflacao"

Essa clausula partia de uma premissa que foi MEDIDA e e falsa: a de que usar um
analisador significaria ESCREVER um. Nao significa. O PowerShell ja traz o seu.
A clausula proibia comprar a roda e obrigava a inventa-la.

Cinco refutacoes independentes -- tres rodadas de pre-auditoria, a contra-auditoria
do loop das 14:16, e uma repeticao de controle com o prompt SEM a enumeracao de
onde olhar -- apontaram todas para a mesma familia, e nenhuma foi resolvida por
regex mais esperta: crase de escape do PowerShell, template literal de JS/TS,
string multilinha, e interpolacao com aspas aninhadas. Sao os limites 15 e 17.

## A premissa que mudou, com a medicao

`[System.Management.Automation.Language.Parser]` faz parte do PowerShell. Nao e
dependencia, nao e download, nao vai ao lockfile e nao precisa de rede.

Medido contra a MESMA forma de fixture que o oraculo usa -- funcao longa com
chave de abertura e de fechamento dentro de string, e rabo de 200 linhas depois:

| | mediu |
|---|---|
| heuristica atual por regex | 267 |
| oraculo exige | 66 |
| parser da plataforma | **66**, com `parse_errors=0` |

Custo medido: 0,33 s para o `engine/Invoke-GreenLoop.ps1` inteiro. O repositorio
tem 5 arquivos PowerShell.

### O sandbox do operario alcanca o parser

Medido dentro de `codex exec --sandbox workspace-write`, num worktree real, e
nao presumido:

    parse_errors=0
    Curta 1-4
    LAST_EXIT_CODE: 0

A funcao da fixture tem 4 linhas. A heuristica atual reportaria 204.

## Comportamento esperado

- `.ps1`: o fim da funcao vem do parser da plataforma. Chave em string --
  escapada por crase, com interpolacao aninhada, ou solta -- deixa de afetar a
  contagem, porque nao ha mais contagem.
- `.ts`, `.js`, `.mjs`: a contagem de chaves permanece, e passa a reconhecer a
  crase como delimitador de string, alem de aspas simples e duplas.
- `.py`: NAO MUDA. Ja termina por indentacao, nao por chaves, e nenhum teste
  falha nela.
- Funcao genuinamente longa continua sendo reportada, e medida no fim CERTO, em
  qualquer das linguagens.

## O que a correcao NAO pode ser

- **Escrever um analisador lexico a mao.** Se o codigo passar a rastrear estado
  de aspas, profundidade de interpolacao ou continuacao entre linhas, parou de
  usar ferramenta madura e voltou a inventar a roda. Devolva a duvida ao gerente.
- **Caso especial para `StartsWith`, para uma sequencia literal, ou para uma
  extensao unica.** A regra e sobre chave em string, nao sobre o defeito que a
  revelou.
- **Quebrar quando o interpretador do PowerShell nao existe.** Ausencia dele e
  faixa `>=2`: nao foi possivel medir por aquele caminho. Caia na contagem de
  chaves atual e siga. Um gate que estoura por falta de interpretador deixa de
  ser gate.
- **Interpolar caminho de arquivo dentro de uma string de comando.** Passe
  argumentos como lista. O caminho vem do disco e pode ser hostil.
- **Combinar o resultado do analisador com a contagem de chaves.** Nada de
  `min(parser, contagem)`, `max(...)`, "fico com o mais conservador" ou
  "confirmo um com o outro". A contagem crua e o FALLBACK para quando o
  interpretador nao existe: caminho excludente, nao segunda opiniao.
  Medido: num `.ps1` cuja chave de FECHAMENTO aparece em string antes de
  qualquer abertura, a crua devolve 2 para uma funcao de 63 linhas. Um `min`
  com ela emudece o gate exatamente no caso que esta missao existe para
  corrigir -- e passava em 100% do oraculo ate
  `test_chave_de_fechamento_em_string_nao_encerra_a_funcao_cedo` existir.
- **Chamar o analisador uma vez por FUNCAO.** `_find_long_functions` varre
  cabecalho a cabecalho e chama `_function_end` para cada candidato. Um
  subprocesso por funcao multiplica 0,33 s pelo numero de funcoes do arquivo, e
  a suite de fixtures pequenas nao mostraria isso. Analise UMA vez por ARQUIVO,
  guarde os limites de todas as funcoes, e responda as consultas seguintes a
  partir do que ja foi lido. Achado da contra-auditoria, rotulado como hipotese
  por ela e aceito como requisito pelo gerente: o custo e previsivel sem medir.

## Escopo congelado

Nao inclua `.psm1` em `suffixes`. Isso e o limite 18, e tem decisao propria:
`engine/GenuinoEngine.psm1` tem 833 linhas contra teto de 600, e incluir a
extensao sem dividir o arquivo troca um ponto cego por um gate vermelho
permanente. Fora desta missao.

## O teto de tamanho, que ja custou uma iteracao

Leia isto antes de escrever a primeira linha. Nao e teoria.

    gates.py = 598 linhas | teto = 600 | folga = 2 linhas

`check_bloat` reprova com `len(lines) > max_file_lines`, e `check_tree.main`
chama `check_bloat(root, skip_paths=("method/",))` com os `BloatThresholds`
padrao. O `GATE_DA_FRONTEIRA` roda o `check_tree` sobre a arvore inteira.

E ele NAO e apenas um passo humano antes do push. `engine/Invoke-GreenLoop.ps1`
o executa como gate `G0-fronteira` em TODA iteracao, no mesmo array do
`G5-testes`. O exit code dele reprova a iteracao e a consome.

Ja aconteceu, e esta em `runs/check-bloat-chave-em-string/20260831T174218.231Z/iter1`:

    g5-testes      exit_code: 0  status: PASS    <- oraculo verde
    g0-fronteira   exit_code: 1  status: FAIL
        mcp/src/genuino_mcp/gates.py:642 [arquivo-longo] 642 linhas (teto 600)

O operario tinha o oraculo verde e perdeu a iteracao so pelo teto. No `iter2`
ele entregou 19 adicoes contra 18 remocoes -- liquido +1 -- porque colapsou um
docstring de 14 linhas para caber. Isso e "encher o teto para caber", o
antipadrao que o cabecalho de `mcp/tests/test_bloat_strings.py` condena, e a
revisao do gerente recusa.

### Por isso o WRITE_SET tem dois caminhos, e um arquivo e novo

A integracao com o parser -- localizar o interpretador, montar os argumentos
como lista, subprocesso com timeout, tratar `OSError` e `TimeoutExpired`, ler a
saida, mapear inicio de funcao para o extent, guardar o resultado por arquivo, e
cair na contagem de chaves quando nada disso funcionar -- nao cabe em 2 linhas.

Nao ha saida por compressao: `ruff format --check` esta no `TEST_CMD` e o
`line-length` e 100. Nao ha saida por relaxar o teto: e STOP CONDITION.

Entao a missao autoriza um MODULO NOVO. A R4 permite arquivo novo para "modulo
genuinamente novo", e analise de extensao de bloco por linguagem e exatamente
isso: nao e uma copia de `gates.py`, e uma responsabilidade que nunca existiu.

Precedente do proprio gerente: quando `test_gates.py` bateu no mesmo teto de
600, ele DIVIDIU em `test_bloat_strings.py` em vez de encher. O remedio e o
mesmo; o que muda e que agora ele esta declarado no write-set em vez de proibido.

`gates.py` deve receber o MINIMO: o import e a chamada. O corpo vive no modulo
novo. Se `gates.py` passar de 600 linhas, o `G0-fronteira` reprova a iteracao, e
a culpa e do desenho, nao do teto.

WRITE_SET: mcp/src/genuino_mcp/gates.py, mcp/src/genuino_mcp/blocks.py
ORACULO: mcp/tests/

TEST_CMD: $env:UV_CACHE_DIR="$env:TEMP/genuino-uv-cache"; $env:UV_LINK_MODE='copy'; Set-Location mcp; uv run --offline python -m pytest tests/ -q --basetemp="$env:TEMP/genuino-pytest-$PID"; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; uv run --offline python -m ruff check .; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; uv run --offline python -m ruff format --check .; exit $LASTEXITCODE

FRONTEIRA: o gate de publicacao roda sobre a arvore inteira. ATENCAO: o motor o executa como G0-fronteira em TODA iteracao, no mesmo array do G5-testes, e o exit code dele reprova a iteracao e a consome. Nao e revisao humana posterior.
GATE_DA_FRONTEIRA: $env:UV_CACHE_DIR="$env:TEMP/genuino-uv-cache"; $env:UV_LINK_MODE='copy'; Set-Location mcp; uv run --offline python -m genuino_mcp.check_tree ..; exit $LASTEXITCODE
PRE_REQUISITOS_HUMANOS: cache do uv aquecido em TEMP/genuino-uv-cache, e o interpretador do PowerShell 7 no PATH. O operario roda sem rede e nao alcanca o cache global; o motor nao verifica nenhum dos dois, e por isso este campo existe.

## Nota sobre o ambiente do operario

Medido, e nao previsto. O `--sandbox workspace-write` permite escrever no
worktree e em TEMP, NEGA o cache global do uv (`os error 5`), e desabilita a
rede (`SSL connection could not be established`). Nao e ACL do host: e o sandbox
cumprindo o desenho.

O cache em `TEMP/genuino-uv-cache` foi aquecido pelo gerente, que tem rede.

### Por que `python -m` e nao o executavel

O Controle de Aplicativo do Windows bloqueia o `pytest.exe` RECEM-CRIADO no
`.venv` do worktree, com `os error 4551`. `python -m pytest` nao spawna o shim
gerado. Isso nao contorna o controle de seguranca: usa um caminho que ele ja
autoriza.

### Por que `--basetemp` fora do repo e unico por processo

`tmp_path` escreve em `%TEMP%/pytest-of-<usuario>`, criado pelo gerente; o
operario nao escreve em diretorio preexistente com outro dono (`WinError 5`).
E basetemp DENTRO do worktree torna o oraculo insatisfazivel: `iter_text_files`
lista com `git ls-files --others --exclude-standard`, entao fixtures num
diretorio ignorado ficam invisiveis para `check_bloat`, e seis testes que exigem
FAIL recebem PASS.

## STOP CONDITIONS

- Alterar qualquer arquivo em `mcp/tests/` e violacao de oraculo. Adicionar
  teste proprio e permitido fora desse caminho, nunca enfraquecendo os
  existentes.
- Escrever fora de `mcp/src/genuino_mcp/gates.py` e
  `mcp/src/genuino_mcp/blocks.py` reprova a iteracao. Vale para cache e
  diretorio temporario criados no worktree: o motor roda `git add -A` antes de
  comparar.
- Apagar docstring, comentario ou codigo vivo de `gates.py` com o proposito de
  caber no teto de 600 linhas e violacao de escopo. O teto se resolve pondo
  codigo em `blocks.py`, nao esvaziando o antigo. O loop anterior ja pagou por
  esse atalho, e a revisao do gerente recusa.
- Dependencia nova de pacote: BLOCKED. O parser do PowerShell NAO e dependencia
  nova -- e um executavel que ja existe no host e no runner da CI.
- Relaxar os tetos de `BloatThresholds` para fazer o teste passar e violacao de
  escopo. A missao e sobre a medicao, nao sobre o limite.
- Incluir `.psm1` em `suffixes` e violacao de escopo. Ver "Escopo congelado".

## Oraculo: os seis que falham hoje

Medido sobre `0199897` mais tres lacunas que o gerente fechou antes de delegar.
`pytest tests/` sai com 1:

    FAILED tests/test_bloat_strings.py::test_aspa_escapada_por_crase_nao_expoe_a_chave
    FAILED tests/test_bloat_strings.py::test_template_literal_nao_expoe_a_chave
    FAILED tests/test_bloat_strings.py::test_funcao_longa_em_ts_e_medida_no_fim_exato
    FAILED tests/test_bloat_strings.py::test_chave_de_fechamento_em_string_nao_encerra_a_funcao_cedo
    FAILED tests/test_gates.py::test_chave_dentro_de_string_nao_desbalanceia_a_contagem
    FAILED tests/test_gates.py::test_funcao_longa_com_string_e_medida_no_fim_exato

Quatro sao `.ps1` e dois sao `.ts`. Os seis precisam passar juntos, e os que
hoje passam precisam continuar passando.

### As tres lacunas fechadas antes de delegar

Duas auditorias independentes refutaram a delegacao das versoes anteriores desta
missao. As tres refutacoes foram confirmadas por medicao do gerente antes de
virarem teste:

- **Nao havia teste de VERDADEIRO POSITIVO para JS/TS.** Dos quatro asserts que
  exigiam deteccao, tres eram `.ps1` e um era `.py`. O unico teste de
  TypeScript exigia que uma funcao CURTA nao fosse reportada. Uma implementacao
  que simplesmente parasse de contar chaves em `.ts`, `.js` e `.mjs` passava no
  oraculo inteiro e deixava o gate cego para as tres.
  Fechado por `test_funcao_longa_em_ts_e_medida_no_fim_exato`.
- **O caminho de degradacao nao era exercitado.** A missao exige cair na
  contagem de chaves quando o analisador nao existe, e nenhum teste media isso:
  uma implementacao que levantasse excecao fatal passava.
  Fechado por `test_sem_o_analisador_o_gate_degrada_e_nao_quebra`, que passa
  hoje e existe como guarda, nao como acusacao.
- **A contagem crua nunca subestimava em nenhuma fixture.** Nas sete anteriores
  ela ou estourava ate o EOF ou acertava -- 205/4, 205/4, 205/4, 267/66, 65/65,
  3/3, 62/62. Isso deixava vivo um `min(parser, contagem)`, indistinguivel do
  parser puro em 100% do oraculo, que emudece o gate quando uma chave de
  FECHAMENTO em string aparece antes de qualquer abertura. Medido: crua = 2
  para uma funcao de 63 linhas.
  Fechado por `test_chave_de_fechamento_em_string_nao_encerra_a_funcao_cedo`.

Os dois guardas que matam a correcao-por-cegueira sao
`test_a_correcao_nao_cega_o_gate_nas_novas_aspas`, do lado do PowerShell, e o
segundo assert de `test_funcao_longa_em_ts_e_medida_no_fim_exato`, do lado do
JS/TS. Uma correcao que faca qualquer um deles reprovar trocou um defeito por
outro.

`ruff check` e `ruff format --check` estavam limpos na arvore antes desta
delegacao. Se o gate reprovar por lint, e regressao do operario, nao heranca do
gerente. Isso e o limite 16, e foi verificado para nao se repetir.
