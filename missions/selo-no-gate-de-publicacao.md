# selo-no-gate-de-publicacao

Primeira missão real do método sobre trabalho útil. As anteriores provaram o
mecanismo; esta corrige um defeito encontrado por auditoria.

OBJETIVO: fazer o gate de publicação (`genuino_mcp.check_tree`) chamar o gate de
selo (`genuino_mcp.seal`) sobre `method/`, e reportá-lo como um gate próprio no
relatório, ao lado de `scan_secrets`, `check_bloat` e `selftest_security`.

## Por que existe

Uma auditoria de premissas encontrou o seguinte: `check_tree.py` afirma, num
comentário, que `method/` "responde ao gate de selo (genuino_mcp.seal), que prova
que ninguém o alterou". O CLI nunca chama o selo. Quem roda o gate localmente e
vê `GATE DE PUBLICACAO: PASS` conclui que a integridade do conteúdo normativo
foi verificada — e não foi. A CI verifica em passo separado; o CLI, não.

Evidência que aparenta cobrir mais do que cobre é pior que evidência ausente:
ela produz confiança sem lastro.

## Comportamento esperado

- Quando `method/MANIFEST.sha256` existe e confere: gate `seal` reporta PASS.
- Quando o conteúdo de `method/` foi alterado sem regerar o selo: reporta FAIL,
  e o gate de publicação sai com 1.
- Quando `method/` existe mas não há manifesto: reporta INDETERMINADO. Selo
  ausente não é selo válido, e não pode virar PASS silencioso.
- Quando não existe `method/`: o selo não se aplica e não pode reprovar. Nem
  todo repositório tem conteúdo normativo.

O nome do gate no relatório deve conter `seal`, porque é o que os testes de
aceitação procuram.

WRITE_SET: mcp/src/genuino_mcp/
ORACULO: mcp/tests/

TEST_CMD: $env:UV_LINK_MODE='copy'; Set-Location mcp; uv run pytest tests/test_check_tree.py -q; exit $LASTEXITCODE

FRONTEIRA: o CLI `python -m genuino_mcp.check_tree` rodado por um humano na raiz do repositório
GATE_DA_FRONTEIRA: $env:UV_LINK_MODE='copy'; Set-Location mcp; $o = uv run python -m genuino_mcp.check_tree .. 2>&1 | Out-String; if ($o -notmatch 'seal') { exit 1 }; exit 0
PRE_REQUISITOS_HUMANOS: NENHUM

## STOP CONDITIONS

- Alterar qualquer arquivo em `mcp/tests/` é violação de oráculo: os testes de
  aceitação são do gerente. Adicionar testes próprios é permitido apenas fora
  desse caminho, e nunca enfraquecendo os existentes.
- Escrever fora do `WRITE_SET` reprova a iteração.
- Dependência nova: BLOCKED. `genuino_mcp.seal` já existe no mesmo pacote.

## Nota sobre UV_LINK_MODE

O `TEST_CMD` define `UV_LINK_MODE=copy` por uma razão medida, não por precaução.
Sem isso, o `uv` tenta criar hardlinks do cache para o worktree e falha com
`os error 396: A operacao de nuvem nao pode ser executada em um arquivo com
links fisicos incompativeis` -- o OneDrive interfere na operação.

O baseline registrou isso como exit 2, `INDETERMINADO`, e o motor abortou sem
delegar. Foi o comportamento correto: um erro de ambiente não é reprovação do
trabalho, e delegar ali teria queimado iterações com o operário tentando
consertar algo que não é dele.

## Nota sobre a fronteira

O `TEST_CMD` prova que os casos passam. O `GATE_DA_FRONTEIRA` prova algo
diferente e mais próximo do uso real: que a palavra `seal` aparece na saída que
um humano lê ao rodar o gate. Um teste pode passar com o selo chamado em
silêncio; a fronteira exige que ele seja *reportado*.
