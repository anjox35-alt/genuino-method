#!/bin/sh
# PostToolUse: formata o arquivo Python que acabou de ser escrito.
#
# `ruff format --check` e gate na CI. Sem este hook, a reprovacao aparece
# minutos depois, no push -- ja aconteceu duas vezes nesta base, uma delas em
# arquivo entregue por um operario que nao tinha como saber.
#
# UV_LINK_MODE=copy nao e precaucao: o `uv` tenta hardlink do cache para o
# worktree e o OneDrive recusa com `os error 396`.

raiz=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# `python` nao existe de fabrica em Linux e macOS recentes: la o binario se
# chama `python3`. Sem resolver entre os dois, `$alvo` sai vazio nesses hosts
# e o hook nao formata nada -- calado. A reprovacao aparece minutos depois no
# `ruff format --check` da CI, que e o atraso de diagnostico que este hook
# existe para encurtar.
py=""
for candidato in python python3; do
    if command -v "$candidato" >/dev/null 2>&1; then
        py=$candidato
        break
    fi
done

# Aspas SIMPLES no `-c`: o shell nao expande nada dentro da fonte, que deixa
# de ser template e passa a ser codigo literal. Hoje nao ha `$` algum ali
# dentro, entao a troca nao corrige defeito vivo -- fecha o construto que ja
# falhou uma vez nesta base, no `proteger-oraculo.sh`, onde um id de missao
# com aspa virava SyntaxError e o hook saia sem decidir. Fechar o construto
# custa uma linha; descobrir de novo, pelo defeito, custou uma auditoria.
alvo=$("${py:-python}" -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("")
    sys.exit(0)
tr = d.get("tool_response") or {}
ti = d.get("tool_input") or {}
print(tr.get("filePath") or ti.get("file_path") or "")
' 2>/dev/null)

[ -n "$alvo" ] || exit 0

# Um backslash solto entre aspas simples faz o GNU tr avisar "unescaped
# backslash at end of string". `\134` e o mesmo caractere em octal, sem
# ambiguidade de escape.
# `\` e o mesmo caractere em octal, sem ambiguidade de escape.
#
# E minusculas porque o NTFS nao distingue caixa: `MCP/src/a.PY` E
# `mcp/src/a.py`, o mesmo arquivo. Sem isso o `case` abaixo deixa de formatar
# um arquivo que o `ruff format --check` da CI vai reprovar minutos depois, no
# push -- que e o atraso de diagnostico que este hook existe para encurtar.
#
# Minusculiza so a copia de comparacao. `$alvo` original e o que vai para o
# ruff: num filesystem que distingue caixa, o minusculizado nao existe.
normalizado=$(printf '%s' "$alvo" | tr '\134' '/' | tr 'A-Z' 'a-z')

case "$normalizado" in
    */mcp/*.py)
        UV_LINK_MODE=copy uv run --project "$raiz/mcp" ruff format "$alvo" >/dev/null 2>&1
        ;;
esac
exit 0
