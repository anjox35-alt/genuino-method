#!/bin/sh
# Oraculo do hook formatar-python.sh.
#
# O ramo de match executa `uv run ... ruff format "$alvo"`, que escreve em
# arquivo e paga segundos de startup do uv. Medir a decisao sem pagar isso e
# sem por seam nenhum no codigo de producao: um `uv` falso no inicio do PATH,
# que so registra os argumentos que recebeu. O que se testa continua sendo o
# construto real, byte a byte, e nao uma copia da logica dele.
#
# Uso: sh .claude/hooks/test-formatar-python.sh
# Exit 0 = todos os casos passaram. Exit 1 = ha caso reprovado. Exit 2 = ambiente.

raiz=$(git rev-parse --show-toplevel) || exit 2
hook="$raiz/.claude/hooks/formatar-python.sh"

palco=$(mktemp -d) || exit 2
trap 'rm -rf "$palco"' EXIT INT TERM

STUB_LOG="$palco/chamadas.log"
export STUB_LOG

cat > "$palco/uv" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_LOG"
STUB
chmod +x "$palco/uv"

PATH="$palco:$PATH"
export PATH

# O stub precisa mesmo executar sob o sh do Git Bash. Se nao executar, todo
# caso de "formata" reprovaria e o oraculo acusaria o hook por um defeito que
# e do proprio teste -- exatamente o falso vermelho que a R2 existe para evitar.
: > "$STUB_LOG"
uv run --project x ruff format y 2>/dev/null
if [ ! -s "$STUB_LOG" ]; then
    echo "AMBIENTE: o stub de uv nao executou; o oraculo nao pode medir." >&2
    exit 2
fi

falhas=0
total=0

# PostToolUse traz o caminho em tool_response.filePath, com tool_input.file_path
# como reserva. O json vem do python porque caminho do Windows tem backslash.
decidir() {
    campo="$2"
    json=$(printf '%s' "$1" | python -c '
import json, sys
alvo = sys.stdin.read()
campo = "'"$campo"'"
d = {"hook_event_name": "PostToolUse", "tool_name": "Write"}
if campo == "response":
    d["tool_response"] = {"filePath": alvo}
else:
    d["tool_input"] = {"file_path": alvo}
print(json.dumps(d))
') || return 2
    : > "$STUB_LOG"
    printf '%s' "$json" | sh "$hook" >/dev/null 2>&1
    [ -s "$STUB_LOG" ] && echo "formata" || echo "ignora"
}

verificar() {
    caminho="$1"
    esperado="$2"
    motivo="$3"
    campo="${4:-response}"
    total=$((total + 1))
    obtido=$(decidir "$caminho" "$campo")
    if [ "$obtido" = "$esperado" ]; then
        printf '  ok    %-8s %-34s %s\n' "$obtido" "$caminho" "$motivo"
    else
        printf '  FALHA esperado=%s obtido=%s  %-30s %s\n' "$esperado" "$obtido" "$caminho" "$motivo" >&2
        falhas=$((falhas + 1))
    fi
}

echo "== deve FORMATAR: python sob mcp/ =="
verificar "$raiz/mcp/src/genuino_mcp/a.py" formata "caminho canonico"
verificar "$raiz/MCP/src/a.py"             formata "MCP em caixa alta"
verificar "$raiz/mcp/src/a.PY"             formata "extensao em caixa alta"
verificar "$raiz/mcp/tests/A.PY"           formata "diretorio e extensao"
verificar 'D:\r\mcp\src\a.py'              formata "backslash do Windows"
verificar "$raiz/mcp/src/b.py"             formata "via tool_input" input

echo "== deve IGNORAR: nao e python sob mcp/ =="
verificar "$raiz/docs/a.md"                ignora  "markdown"
verificar "$raiz/engine/x.ps1"             ignora  "powershell"
verificar "$raiz/mcp/src/a.pyc"            ignora  "nao e .py"
verificar "$raiz/nucleo/fora.py"           ignora  "python fora de mcp/"

echo "== so python3 no PATH: continua formatando =="
total=$((total + 1))
# Em Linux e macOS de fabrica o binario chama-se `python3` e `python` nao
# existe. Sem resolver entre os dois, o extrator nao roda nesses hosts, `$alvo`
# sai vazio e o hook devolve exit 0 sem formatar nada. O silencio e o problema:
# o defeito reaparece minutos depois, no `ruff format --check` da CI, que e
# justamente o atraso de diagnostico que este hook existe para encurtar.
#
# Wrappers so para git, tr e python3, mais o $palco por causa do uv falso:
# `python` fica genuinamente ausente do PATH.
#
# O evento vai por printf, e nao pelo json.dumps do decidir(), porque este
# caso precisa mandar o hook por um PATH restrito. O caminho e so barra
# normal, entao nao ha backslash a escapar.
sh_bin=$(command -v sh) || exit 2
real_git=$(command -v git) || exit 2
real_tr=$(command -v tr) || exit 2
real_py=$(command -v python) || exit 2
so_py3=$(mktemp -d) || exit 2
cat > "$so_py3/git" <<STUBGIT3
#!/bin/sh
exec "$real_git" "\$@"
STUBGIT3
cat > "$so_py3/tr" <<STUBTR3
#!/bin/sh
exec "$real_tr" "\$@"
STUBTR3
cat > "$so_py3/python3" <<STUBPY3
#!/bin/sh
exec "$real_py" "\$@"
STUBPY3
chmod +x "$so_py3/git" "$so_py3/tr" "$so_py3/python3"
evento=$(printf '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_response":{"filePath":"%s"}}' "$raiz/mcp/src/a.py")
: > "$STUB_LOG"
printf '%s' "$evento" | PATH="$so_py3:$palco" "$sh_bin" "$hook" >/dev/null 2>&1
rm -rf "$so_py3"
if [ -s "$STUB_LOG" ]; then
    echo "  ok    formata  so com python3 no PATH"
else
    echo "  FALHA obtido=ignora  so python3 desligou a formatacao" >&2
    falhas=$((falhas + 1))
fi

echo
if [ "$falhas" -eq 0 ]; then
    echo "ORACULO VERDE: $total/$total casos."
    exit 0
fi
echo "ORACULO VERMELHO: $falhas de $total casos reprovados." >&2
exit 1
