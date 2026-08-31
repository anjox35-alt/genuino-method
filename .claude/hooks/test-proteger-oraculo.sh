#!/bin/sh
# Oraculo do hook proteger-oraculo.sh.
#
# O hook so decide com `runs/.missao-ativa` presente, entao este teste cria a
# sentinela. Duas salvaguardas, porque uma sentinela esquecida no disco bloqueia
# escrita em mcp/tests/ ate alguem descobrir por que:
#
#   1. aborta se ja existir uma -- nunca sobrescreve missao real;
#   2. trap remove em EXIT, INT e TERM, inclusive se um caso falhar no meio.
#
# Uso: sh .claude/hooks/test-proteger-oraculo.sh
# Exit 0 = todos os casos passaram. Exit 1 = ha caso reprovado. Exit 2 = ambiente.

raiz=$(git rev-parse --show-toplevel) || exit 2
hook="$raiz/.claude/hooks/proteger-oraculo.sh"
sentinela="$raiz/runs/.missao-ativa"

if [ -f "$sentinela" ]; then
    echo "ABORTADO: ja existe missao ativa em $sentinela." >&2
    echo "  Este teste criaria e removeria a sentinela, destruindo o estado real." >&2
    exit 2
fi

trap 'rm -f "$sentinela"' EXIT INT TERM

falhas=0
total=0

# JSON montado pelo python, nao por printf: um caminho do Windows carrega
# backslash, que em JSON precisa vir escapado. Escapar a mao aqui seria
# reimplementar json.dumps com um sed.
# O json e montado numa variavel antes de alimentar o hook, e nao encanado
# direto. O hook faz `exit 0` sem ler stdin quando nao ha missao ativa, e um
# produtor python encanado nele morre com OSError 22 no Windows ao dar flush
# num pipe ja fechado. Ruido do harness, nao do construto -- mas ruido num
# oraculo se le como defeito, e um oraculo que grita sozinho perde autoridade.
decidir() {
    json=$(printf '%s' "$1" | python -c '
import json, sys
print(json.dumps({
    "hook_event_name": "PreToolUse",
    "tool_name": "Write",
    "tool_input": {"file_path": sys.stdin.read()},
}))
') || return 2
    printf '%s' "$json" | sh "$hook" 2>/dev/null
}

verificar() {
    caminho="$1"
    esperado="$2"
    motivo="$3"
    total=$((total + 1))
    saida=$(decidir "$caminho")
    case "$saida" in
        *'"deny"'*) obtido="deny" ;;
        *)          obtido="allow" ;;
    esac
    if [ "$obtido" = "$esperado" ]; then
        printf '  ok    %-6s %-32s %s\n' "$obtido" "$caminho" "$motivo"
    else
        printf '  FALHA esperado=%s obtido=%s  %-28s %s\n' "$esperado" "$obtido" "$caminho" "$motivo" >&2
        falhas=$((falhas + 1))
    fi
}

echo "missao-de-teste-do-oraculo" > "$sentinela"

echo "== sob missao ativa: deve BLOQUEAR o oraculo =="
verificar "$raiz/mcp/tests/test_x.py"   deny  "caminho canonico"
verificar "$raiz/mcp/Tests/test_x.py"   deny  "Tests capitalizado"
verificar "$raiz/MCP/TESTS/test_x.py"   deny  "MCP/TESTS caixa alta"
verificar "$raiz/mcp/tests/Test_X.PY"   deny  "arquivo em caixa alta"
verificar 'D:\r\mcp\tests\t.py'         deny  "backslash do Windows"

echo "== sob missao ativa: deve PERMITIR fora do oraculo =="
verificar "$raiz/mcp/src/genuino_mcp/server.py" allow "implementacao, nao oraculo"
verificar "$raiz/docs/limites.md"               allow "documento"

rm -f "$sentinela"

echo "== sem missao: deve PERMITIR, e o passo 1 do fluxo R7 =="
verificar "$raiz/mcp/tests/test_x.py"   allow "escrever o oraculo ANTES de delegar"
verificar "$raiz/MCP/TESTS/test_x.py"   allow "idem, em caixa alta"

echo
if [ "$falhas" -eq 0 ]; then
    echo "ORACULO VERDE: $total/$total casos."
    exit 0
fi
echo "ORACULO VERMELHO: $falhas de $total casos reprovados." >&2
exit 1
