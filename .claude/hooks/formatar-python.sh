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

alvo=$(python -c "
import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    print('')
    sys.exit(0)
tr = d.get('tool_response') or {}
ti = d.get('tool_input') or {}
print(tr.get('filePath') or ti.get('file_path') or '')
" 2>/dev/null)

[ -n "$alvo" ] || exit 0

# Um backslash solto entre aspas simples faz o GNU tr avisar "unescaped
# backslash at end of string". `\134` e o mesmo caractere em octal, sem
# ambiguidade de escape.
# `\` e o mesmo caractere em octal, sem ambiguidade de escape.
normalizado=$(printf '%s' "$alvo" | tr '\134' '/')

case "$normalizado" in
    */mcp/*.py)
        UV_LINK_MODE=copy uv run --project "$raiz/mcp" ruff format "$alvo" >/dev/null 2>&1
        ;;
esac
exit 0
