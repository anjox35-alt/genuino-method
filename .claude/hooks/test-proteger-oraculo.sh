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
#
# O segundo argumento escolhe o campo que carrega o caminho. `file_path` e o
# padrao porque e o que Write e Edit mandam; `notebook_path` existe porque o
# NotebookEdit manda outro nome, e o matcher em settings.json inclui os tres.
# O nome do campo vai por argv, nunca concatenado na fonte: o construto
# condenado no proprio hook nao volta pela porta do oraculo.
decidir() {
    campo="${2:-file_path}"
    json=$(printf '%s' "$1" | python -c '
import json, sys
campo = sys.argv[1]
print(json.dumps({
    "hook_event_name": "PreToolUse",
    "tool_name": "NotebookEdit" if campo == "notebook_path" else "Write",
    "tool_input": {campo: sys.stdin.read()},
}))
' "$campo") || return 2
    printf '%s' "$json" | sh "$hook" 2>/dev/null
}

verificar() {
    caminho="$1"
    esperado="$2"
    motivo="$3"
    campo="${4:-file_path}"
    total=$((total + 1))
    saida=$(decidir "$caminho" "$campo")
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

# Igual a verificar(), mas varia o id da missao em vez do caminho. O alvo e
# sempre o oraculo canonico, entao a resposta correta e sempre deny.
verificar_id() {
    rotulo="$1"
    id="$2"
    total=$((total + 1))
    printf '%s' "$id" > "$sentinela"
    saida=$(decidir "$raiz/mcp/tests/test_x.py")
    case "$saida" in
        *'"deny"'*) obtido="deny" ;;
        *)          obtido="allow" ;;
    esac
    if [ "$obtido" = "deny" ]; then
        printf '  ok    deny   id=%s\n' "$rotulo"
    else
        printf '  FALHA obtido=%s  id=%s\n' "$obtido" "$rotulo" >&2
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
verificar "$raiz/mcp//tests/test_x.py"  deny  "separador duplicado"
verificar "$raiz/mcp/./tests/test_x.py" deny  "segmento de ponto"
verificar "$raiz/mcp/src/../tests/t.py" deny  "segmento pai"

echo "== sob missao ativa: deve PERMITIR fora do oraculo =="
verificar "$raiz/mcp/src/genuino_mcp/server.py" allow "implementacao, nao oraculo"
verificar "$raiz/docs/limites.md"               allow "documento"
verificar "$raiz/mcp/tests/../src/a.py"         allow "o .. sai do oraculo"

echo "== sob missao ativa: NotebookEdit traz o caminho em notebook_path =="
verificar "$raiz/mcp/tests/oraculo.ipynb" deny  "notebook e oraculo" notebook_path
verificar "$raiz/docs/caderno.ipynb"      allow "notebook fora do oraculo" notebook_path

echo "== sob missao ativa: caminho relativo tambem nomeia o oraculo =="
verificar "./mcp/tests/test_x.py"         deny  "relativo com ./"
verificar "mcp/tests/test_x.py"           deny  "relativo sem ./"
verificar "mcp/src/genuino_mcp/server.py" allow "relativo fora do oraculo"

rm -f "$sentinela"

echo "== sem missao: deve PERMITIR, e o passo 1 do fluxo R7 =="
verificar "$raiz/mcp/tests/test_x.py"   allow "escrever o oraculo ANTES de delegar"
verificar "$raiz/MCP/TESTS/test_x.py"   allow "idem, em caixa alta"

echo "== id de missao nao pode derrubar o deny =="
verificar_id "aspa simples"    "missao com 'aspa'"
verificar_id "aspa dupla"      'missao com "aspa"'
verificar_id "duas linhas"     "linha1
linha2"
verificar_id "backslash final" 'missao-com-barra\'
verificar_id "chave solta"     'missao-}-{-solta'
verificar_id "vazio"           ""
rm -f "$sentinela"

echo "== deny sobrevive a python quebrado na montagem =="
# Guarda: o evento deste caso e montado por printf, nao por json.dumps --
# abaixo o python esta sabotado de proposito, entao precisa ser assim. Mas se
# $raiz contiver aspa ou barra invertida, o printf produz JSON invalido, o
# json.load do extrator falha, e o caso passaria a medir o ramo do extrator
# em vez do fallback que afirma testar. Falharia calado, medindo outra
# coisa. Aborta ruidoso em vez disso.
case "$raiz" in
    *'"'*|*'\'*)
        echo "ABORTADO: raiz do repo contem aspa ou barra invertida; o printf abaixo produziria JSON invalido." >&2
        exit 2
        ;;
esac
total=$((total + 1))
real=$(command -v python) || exit 2
sabotado=$(mktemp -d) || exit 2
# Falha SO na chamada que monta o deny, que passa o id como TERCEIRO
# argumento; a extracao do alvo usa dois e segue no python de verdade.
# Um stub que falhasse em tudo mataria a extracao la em cima, o bloco
# `case` nunca rodaria, e o teste estaria medindo a Task 2, nao esta.
cat > "$sabotado/python" <<STUB
#!/bin/sh
if [ "\$#" -ge 3 ]; then exit 1; fi
exec "$real" "\$@"
STUB
chmod +x "$sabotado/python"
printf '%s' "missao-com-python-quebrado" > "$sentinela"
evento=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$raiz/mcp/tests/test_x.py")
saida=$(printf '%s' "$evento" | PATH="$sabotado:$PATH" sh "$hook" 2>/dev/null)
rm -rf "$sabotado"
rm -f "$sentinela"
case "$saida" in
    *'"deny"'*) echo "  ok    deny   fallback literal emitido" ;;
    *)          echo "  FALHA obtido=allow  o hook abriu com python quebrado" >&2
                falhas=$((falhas + 1)) ;;
esac

echo "== interpretador genuinamente ausente: PATH sem python nenhum nega =="
total=$((total + 1))
# PATH aponta so para um diretorio quase vazio -- e nao literalmente vazio,
# porque o hook chama `git` (linha 15) antes de olhar para o sentinela, e
# `cat` (no ramo de deny) depois. Um PATH vazio de verdade derruba o `git`
# primeiro: `|| exit 0` dispara, e o caso mediria "git ausente", nao "python
# ausente" -- media a coisa errada, sem deny nenhum. Confirmado a mao antes
# deste teste existir. Por isso o diretorio recebe wrappers finos so para
# git e cat, e mais nada: python continua genuinamente ausente do PATH, e o
# `command not found` chega como 127 de verdade, nao simulado por um stub.
sh_bin=$(command -v sh) || exit 2
real_git=$(command -v git) || exit 2
real_cat=$(command -v cat) || exit 2
vazio=$(mktemp -d) || exit 2
cat > "$vazio/git" <<STUBGIT
#!/bin/sh
exec "$real_git" "\$@"
STUBGIT
cat > "$vazio/cat" <<STUBCAT
#!/bin/sh
exec "$real_cat" "\$@"
STUBCAT
chmod +x "$vazio/git" "$vazio/cat"
printf '%s' "missao-com-interpretador-ausente" > "$sentinela"
evento=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$raiz/mcp/tests/test_x.py")
saida=$(printf '%s' "$evento" | PATH="$vazio" "$sh_bin" "$hook" 2>/dev/null)
rm -rf "$vazio"
rm -f "$sentinela"
case "$saida" in
    *'"deny"'*) echo "  ok    deny   interpretador ausente (127 de verdade)" ;;
    *)          echo "  FALHA obtido=allow  interpretador ausente nao foi negado" >&2
                falhas=$((falhas + 1)) ;;
esac

echo "== so python3 no PATH: mede o alvo em vez de negar tudo =="
# Em Linux e macOS de fabrica o binario chama-se `python3` e `python` nao
# existe. Sem resolver entre os dois, o hook cai em 127 nesses hosts e --
# com qualquer sentinela presente -- nega TODA escrita da sessao, nao so as
# de mcp/tests/. O repositorio e publico e a R7 manda o recem-chegado abrir
# missao antes de mexer, entao esse host e o caso comum, nao o exotico.
#
# Wrappers so para git, cat e python3: `python` fica genuinamente ausente do
# PATH, como no host que este caso representa.
sh_bin=$(command -v sh) || exit 2
real_git=$(command -v git) || exit 2
real_cat=$(command -v cat) || exit 2
real_py=$(command -v python) || exit 2
so_py3=$(mktemp -d) || exit 2
cat > "$so_py3/git" <<STUBGIT3
#!/bin/sh
exec "$real_git" "\$@"
STUBGIT3
cat > "$so_py3/cat" <<STUBCAT3
#!/bin/sh
exec "$real_cat" "\$@"
STUBCAT3
cat > "$so_py3/python3" <<STUBPY3
#!/bin/sh
exec "$real_py" "\$@"
STUBPY3
chmod +x "$so_py3/git" "$so_py3/cat" "$so_py3/python3"
printf '%s' "missao-so-com-python3" > "$sentinela"

# Fora do oraculo a escrita e legitima: negar aqui e o dano que a resolucao
# do interpretador existe para impedir.
total=$((total + 1))
evento=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$raiz/mcp/src/genuino_mcp/server.py")
saida=$(printf '%s' "$evento" | PATH="$so_py3" "$sh_bin" "$hook" 2>/dev/null)
case "$saida" in
    *'"deny"'*) echo "  FALHA obtido=deny   so python3 negou escrita fora do oraculo" >&2
                falhas=$((falhas + 1)) ;;
    *)          echo "  ok    allow  fora do oraculo, so com python3 no PATH" ;;
esac

# E o fechamento nao pode ter sido trocado por permissividade: dentro do
# oraculo, o mesmo host continua negando.
total=$((total + 1))
evento=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$raiz/mcp/tests/test_x.py")
saida=$(printf '%s' "$evento" | PATH="$so_py3" "$sh_bin" "$hook" 2>/dev/null)
case "$saida" in
    *'"deny"'*) echo "  ok    deny   dentro do oraculo, so com python3 no PATH" ;;
    *)          echo "  FALHA obtido=allow  so python3 nao protegeu o oraculo" >&2
                falhas=$((falhas + 1)) ;;
esac
rm -rf "$so_py3"
rm -f "$sentinela"

echo "== normalizacao sem tr no PATH: nao pode falhar em silencio =="
total=$((total + 1))
# A normalizacao vivia num pipeline de dois `tr`, cujo exit code o shell
# descartava. Faltando o binario, a forma de comparacao saia vazia, o `case`
# nao casava, e o hook liberava a escrita COM missao em curso -- o mesmo modo
# de falha que o extrator fecha vinte linhas acima, reaberto logo abaixo por
# um comando externo sem guarda. Com a normalizacao dentro do extrator o hook
# nao chama `tr` nenhum, e este caso prende essa propriedade, nao so o deny.
#
# PATH so com git, cat e python, pelo mesmo motivo do caso anterior: `tr`
# fica genuinamente ausente, e o `command not found` e real, nao simulado.
sh_bin=$(command -v sh) || exit 2
real_git=$(command -v git) || exit 2
real_cat=$(command -v cat) || exit 2
real_py=$(command -v python) || exit 2
sem_tr=$(mktemp -d) || exit 2
cat > "$sem_tr/git" <<STUBGIT2
#!/bin/sh
exec "$real_git" "\$@"
STUBGIT2
cat > "$sem_tr/cat" <<STUBCAT2
#!/bin/sh
exec "$real_cat" "\$@"
STUBCAT2
cat > "$sem_tr/python" <<STUBPY
#!/bin/sh
exec "$real_py" "\$@"
STUBPY
chmod +x "$sem_tr/git" "$sem_tr/cat" "$sem_tr/python"
printf '%s' "missao-sem-tr" > "$sentinela"
evento=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$raiz/mcp/tests/test_x.py")
saida=$(printf '%s' "$evento" | PATH="$sem_tr" "$sh_bin" "$hook" 2>/dev/null)
rm -rf "$sem_tr"
rm -f "$sentinela"
case "$saida" in
    *'"deny"'*) echo "  ok    deny   normalizacao nao depende de tr" ;;
    *)          echo "  FALHA obtido=allow  tr ausente derrubou a normalizacao" >&2
                falhas=$((falhas + 1)) ;;
esac

echo "== evento ilegivel com missao ativa nao pode abrir =="
total=$((total + 1))
printf '%s' "missao-com-evento-quebrado" > "$sentinela"
saida=$(printf '%s' 'isto nao e json' | sh "$hook" 2>/dev/null)
rm -f "$sentinela"
case "$saida" in
    *'"deny"'*) echo "  ok    deny   evento ilegivel nega" ;;
    *)          echo "  FALHA obtido=allow  nao medir virou aprovar" >&2
                falhas=$((falhas + 1)) ;;
esac

echo "== payload json valido porem nao-objeto, com missao ativa: nega =="
total=$((total + 1))
printf '%s' "missao-com-payload-nao-objeto" > "$sentinela"
saida=$(printf '%s' 'null' | sh "$hook" 2>/dev/null)
rm -f "$sentinela"
case "$saida" in
    *'"deny"'*) echo "  ok    deny   payload null (json valido, nao-objeto)" ;;
    *)          echo "  FALHA obtido=allow  payload nao-objeto nao foi negado" >&2
                falhas=$((falhas + 1)) ;;
esac

echo "== extrator isolado: payload nao-objeto deve sair com 3, nao com 1 =="
total=$((total + 1))
# O hook sempre sai 0 e colapsa o 3 desenhado com qualquer outro codigo != 0
# no mesmo deny observavel, de proposito (ver comentario no hook). Por isso o
# unico jeito de medir QUAL codigo o extrator de fato produz e isolar o bloco
# python dele e rodar por conta propria. Extraido do hook em tempo de teste,
# nunca copiado a mao, para nunca divergir do que o hook de fato roda.
# O `.*` no lugar do nome do interpretador nao e folga: o hook resolve entre
# `python` e `python3` antes de chamar, entao prender o literal aqui faria
# este caso deixar de achar o bloco e reprovar por defeito do proprio teste.
inicio=$(grep -n "^normalizado=\$(.* -c '$" "$hook" | head -1 | cut -d: -f1)
fim=$(grep -n "^' 2>/dev/null)$" "$hook" | head -1 | cut -d: -f1)
if [ -n "$inicio" ] && [ -n "$fim" ]; then
    extrator=$(mktemp) || exit 2
    sed -n "$((inicio + 1)),$((fim - 1))p" "$hook" > "$extrator"
    printf 'null' | python "$extrator" >/dev/null 2>&1
    codigo_extrator=$?
    rm -f "$extrator"
else
    codigo_extrator="(bloco do extrator nao encontrado no hook)"
fi
if [ "$codigo_extrator" = "3" ]; then
    echo "  ok    exit=3 payload null (json valido, nao-objeto)"
else
    echo "  FALHA exit=$codigo_extrator esperado=3  extrator nao cobre payload nao-objeto" >&2
    falhas=$((falhas + 1))
fi

echo
if [ "$falhas" -eq 0 ]; then
    echo "ORACULO VERDE: $total/$total casos."
    exit 0
fi
echo "ORACULO VERMELHO: $falhas de $total casos reprovados." >&2
exit 1
