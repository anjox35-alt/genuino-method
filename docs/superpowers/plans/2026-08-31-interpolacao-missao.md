# Interpolação de `$missao` no hook do oráculo — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer `proteger-oraculo.sh` negar a escrita no oráculo mesmo quando não consegue montar a resposta, em vez de sair em silêncio.

**Architecture:** Duas mudanças no mesmo arquivo. A fonte Python passa a ser literal — aspas simples no `-c`, dado por `sys.argv` — de modo que nenhum conteúdo de arquivo vira código. E os dois pontos onde o hook hoje desiste em silêncio passam a emitir um `deny` literal, montado pelo shell sem interpolação nenhuma, porque com missão ativa "não consegui medir" não pode significar "pode escrever".

**Tech Stack:** POSIX `sh`, `python` (só stdlib: `json`, `sys`), Git Bash no Windows.

**Spec:** não há arquivo de spec. Esta é uma tarefa *bounded* pela classificação da skill `brainstorming`, e o desenho foi aprovado em conversa. A evidência que a fundamenta está selada em `audits/2026-08-31-hook-anti-copia/ADDENDUM-CAIXA-NOS-TRES.md`, seção 8, que registra o defeito como observado e não corrigido. O contexto abaixo carrega a medição.

## Contexto — por que isto existe

`proteger-oraculo.sh` impede que o GERENTE edite o teste de aceitação enquanto
uma missão está em curso. Sem ele, o operário passa a ser medido por uma régua
diferente da que recebeu.

Hoje o hook monta a resposta assim, em `.claude/hooks/proteger-oraculo.sh:52-65`:

```sh
missao=$(cat "$sentinela" 2>/dev/null)
python -c "
...
      'Oraculo protegido: a missao \"$missao\" esta em curso. '
...
"
```

As aspas **duplas** no `python -c` fazem o shell expandir `$missao` para dentro
da fonte Python, onde o valor cai dentro de uma string de aspas **simples**.
Um id de missão que contenha `'` ou uma quebra de linha encerra essa string e
o Python morre de `SyntaxError`.

Medido em 2026-08-31, com sentinela temporária criada e removida:

| id da missão | resultado | exit |
|---|---|---|
| `missao-normal` | deny correto | 0 |
| `missao com 'aspa'` | **quebrou**, `File "<string>", line 8` | 0 |
| duas linhas | **quebrou**, SyntaxError | 0 |
| `missao-com-barra\` | deny correto | 0 |
| `missao-}-solta` | deny correto | 0 |

O dano não é injeção — é o **exit 0 sem deny**. Com missão ativa, um id com
aspa simples faz a proteção do oráculo desaparecer sem ruído nenhum. O backslash
final não quebra: ele cai antes de um `"`, não de um `'`.

**Decisão do autor:** fechar em erro, nos dois pontos onde o hook pode desistir
sem saber. É o `nao medir nao e aprovar` do `.githooks/pre-push` aplicado aqui.
Diverge de propósito do irmão `impedir-copia.sh`, que falha aberto porque a R4
declara que aquela regra vale mesmo sem hook — a R1 não declara nada parecido
sobre a integridade do oráculo.

## Global Constraints

- `.claude/**` é kernel de governança (R1). O GERENTE implementa direto. **Nunca** delegar ao operário, nunca abrir green loop.
- Os seis arquivos de `.claude/hooks/` sao **ASCII puro**: nenhum byte fora de `0x20`-`0x7E`, mais tab. Verificar com `LC_ALL=C grep -cP '[^\x20-\x7e\t]' <arquivo>`, que conta `0` num arquivo limpo. Usar `-P`, nao BRE: a classe de BRE nao entende escape de tabulacao, entao ela acaba excluindo a letra `t` e conta `1` ate num arquivo ASCII puro. Medido.
- POSIX `sh`, não bash. Sem `[[`, sem arrays, sem `local`.
- Os **9 casos** hoje verdes em `test-proteger-oraculo.sh` devem continuar verdes. Nenhum pode ser alterado ou removido.
- A invariante de caixa fica intacta: minusculizar só a cópia de comparação, nunca `$alvo`.
- Nenhum arquivo fora do write-set: `.claude/hooks/proteger-oraculo.sh`, `.claude/hooks/test-proteger-oraculo.sh`, e o addendum em `audits/2026-08-31-hook-anti-copia/`.
- Commits no estilo da base: assunto imperativo em inglês sem prefixo, corpo com defeito/causa/conserto, parágrafo final de verificação do gerente com números medidos, trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. Sem `Claude-Session:`, que nenhum commit desta base usa e o repositório é público.
- **Sem push.** Passa pelo autor.

---

### Task 1: Deny sobrevive a qualquer id de missão

**Files:**
- Modify: `.claude/hooks/proteger-oraculo.sh:49-68` (o bloco `case`)
- Test: `.claude/hooks/test-proteger-oraculo.sh` (novos casos antes da linha `echo` final)

**Interfaces:**
- Consumes: `$sentinela` e `$normalizado`, já definidos no arquivo, sem alteração.
- Produces: nada consumido por outra task. A Task 2 mexe num bloco anterior e independente.

- [ ] **Step 1: Escrever os casos que falham**

O `verificar()` atual só varia o caminho. Estes casos variam o **id da missão**,
então precisam de um helper novo. Inserir logo depois da função `verificar()`
(que termina na linha 65) e antes da linha 67, `echo "missao-de-teste-do-oraculo" > "$sentinela"`:

```sh
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
```

E os casos, inseridos depois da ultima linha do bloco `== sem missao ... ==`,
que e `verificar "$raiz/MCP/TESTS/test_x.py"   allow "idem, em caixa alta"`.
Ancora textual de proposito: a insercao anterior deste mesmo Step ja deslocou
toda a numeracao abaixo dela. Cada `verificar_id` grava a sentinela de que
precisa, entao nao ha o que recriar antes do bloco.

```sh
echo "== id de missao nao pode derrubar o deny =="
verificar_id "aspa simples"    "missao com 'aspa'"
verificar_id "aspa dupla"      'missao com "aspa"'
verificar_id "duas linhas"     "linha1
linha2"
verificar_id "backslash final" 'missao-com-barra\'
verificar_id "chave solta"     'missao-}-{-solta'
verificar_id "vazio"           ""
rm -f "$sentinela"
```

- [ ] **Step 2: Rodar e confirmar a falha**

Run: `sh .claude/hooks/test-proteger-oraculo.sh`
Expected: FAIL, exit `1`. Os casos `aspa simples` e `duas linhas` reprovam com
`obtido=allow`. Os outros quatro passam — passar não é defeito do caso, é o
defeito ser específico. Anotar o número exato de reprovados para o recibo.

- [ ] **Step 3: Trocar a interpolação por argv, com fallback literal**

Substituir o corpo do ramo `*/mcp/tests/*)` (linhas 50-67) por:

```sh
    */mcp/tests/*)
        missao=$(cat "$sentinela" 2>/dev/null)

        # Aspas SIMPLES no `-c`: o shell nao expande nada dentro da fonte, que
        # deixa de ser um template e passa a ser codigo literal. O id entra por
        # argv, que o python le como dado.
        #
        # Antes, com aspas duplas, `$missao` era concatenado na fonte e caia
        # dentro de uma string de aspas simples. Um id contendo `'` ou uma
        # quebra de linha fechava a string e produzia SyntaxError -- e o hook
        # saia com exit 0 sem emitir deny. A protecao do oraculo sumia em
        # silencio exatamente quando havia missao em curso. Medido.
        saida=$(python -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason":
        "Oraculo protegido: a missao \"" + sys.argv[1] + "\" esta em curso. "
        "Alterar o teste de aceitacao agora mede o operario por uma regua "
        "diferente da que ele recebeu. Espere o veredito, ou encerre a missao "
        "removendo runs/.missao-ativa.",
}}))
' "$missao" 2>/dev/null)

        # So emite a saida do python se ela contiver mesmo um deny. Vazio,
        # erro, saida parcial: tudo cai no literal. Fechar por construcao, e
        # nao por confianca no exit code de um interpretador que pode nem ter
        # rodado.
        case "$saida" in
            *'"deny"'*)
                printf '%s\n' "$saida"
                ;;
            *)
                cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Oraculo protegido: ha missao em curso e o hook nao conseguiu montar a resposta detalhada. Nao medir nao e aprovar. Se a escrita for legitima, encerre a missao removendo runs/.missao-ativa."}}
JSON
                ;;
        esac
        exit 0
        ;;
```

- [ ] **Step 4: Rodar e confirmar que passa**

Run: `sh .claude/hooks/test-proteger-oraculo.sh`
Expected: PASS, exit `0`, 15/15 casos.

- [ ] **Step 5: Provar o fallback com um python quebrado**

O Step 3 tem dois caminhos e o Step 4 só exercitou um. Acrescentar imediatamente antes do `echo` sozinho que precede
`if [ "$falhas" -eq 0 ]; then`. Ancora textual: as insercoes do Step 1 ja
moveram a numeracao.

```sh
echo "== deny sobrevive a python quebrado na montagem =="
total=$((total + 1))
real=$(command -v python) || exit 2
sabotado=$(mktemp -d)
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
```

O evento é montado com `printf` e não com `decidir()`, porque `decidir()` usa
python para montar o JSON e aqui o python está sabotado de propósito.

Run: `sh .claude/hooks/test-proteger-oraculo.sh`
Expected: PASS, exit `0`, 16/16.

- [ ] **Step 6: Conferir ASCII e commitar**

```bash
LC_ALL=C grep -cP '[^\x20-\x7e\t]' .claude/hooks/proteger-oraculo.sh .claude/hooks/test-proteger-oraculo.sh
git add .claude/hooks/proteger-oraculo.sh .claude/hooks/test-proteger-oraculo.sh
git commit -F - <<'MSG'
Build the oracle denial from data, never from interpolated source

proteger-oraculo.sh interpolated the mission id, read from
runs/.missao-ativa, into the source of a `python -c` written with double
quotes. The value landed inside a single-quoted Python string, so an id
holding a quote or a newline closed that string and the interpreter died
of SyntaxError. Measured: `missao com 'aspa'` and a two-line id both left
the hook at exit 0 with no denial on stdout, which means the oracle
protection vanished silently during an active mission -- the one moment it
exists for. A trailing backslash does not break it: that one lands before
a double quote, not a single one.

The source is now literal -- single quotes on -c, so the shell expands
nothing -- and the id arrives through sys.argv, which Python reads as data.
The branch also stops trusting that Python ran: it emits the interpreter's
output only when that output actually contains a denial, and falls back to
a fixed JSON string built by the shell otherwise. Closing here is by
construction rather than by exit code, because a missing interpreter has no
exit code worth reading. This diverges deliberately from impedir-copia.sh,
which fails open: R4 states its rule holds without a hook, and R1 states no
such thing about oracle integrity.

Manager verification, not a model's report: the oracle went from 15 cases
with 2 failing at exit 1 to 16 passing at exit 0, the added case driving a
`python` stub that exits 1 to prove the literal fallback is reached rather
than assumed. The nine pre-existing cases were not touched and stay green.
No sentinel left on disk.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
```

---

### Task 2: Não descobrir o alvo também é negar

**Files:**
- Modify: `.claude/hooks/proteger-oraculo.sh:21-32` (extração do alvo)
- Test: `.claude/hooks/test-proteger-oraculo.sh`

**Interfaces:**
- Consumes: nada da Task 1. Bloco anterior e independente.
- Produces: `$alvo` com o mesmo contrato de hoje — string vazia significa "o evento não carrega caminho", e não mais "não consegui ler".

**Por que é uma task separada:** a Task 1 fecha o ponto onde o hook já sabe que
o alvo é o oráculo. Esta fecha o ponto onde ele não sabe nada, e o raio é bem
maior — com `python` ausente, **nenhum** `Write` ou `Edit` passa enquanto houver
missão aberta, não só os de `mcp/tests/`. Um revisor pode aceitar a Task 1 e
recusar esta.

- [ ] **Step 1: Escrever o caso que falha**

Acrescentar imediatamente antes do `echo` sozinho que precede
`if [ "$falhas" -eq 0 ]; then`. Ancora textual: a Task 1 ja moveu a
numeracao.

```sh
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
```

- [ ] **Step 2: Rodar e confirmar a falha**

Run: `sh .claude/hooks/test-proteger-oraculo.sh`
Expected: FAIL, exit `1`, 1 de 17 reprovado — o caso novo. Hoje o `except`
imprime string vazia e sai com 0, e o `[ -n "$alvo" ] || exit 0` libera.

- [ ] **Step 3: Separar "não medi" de "medi e não há alvo"**

Substituir as linhas 21-32 por:

```sh
# Duas saidas diferentes, de proposito. Exit != 0 significa que o evento nao
# pode ser lido -- nao medi. Exit 0 com saida vazia significa que o evento foi
# lido e simplesmente nao carrega caminho, como num Bash -- medi, e nao ha
# alvo. Colapsar as duas fazia "nao consegui" virar "pode escrever".
alvo=$(python -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(3)
ti = d.get("tool_input") or {}
print(ti.get("file_path") or ti.get("path") or "")
' 2>/dev/null)
codigo=$?

if [ "$codigo" -ne 0 ]; then
    # Ha missao ativa e o hook nao conseguiu nem descobrir o alvo. Interpretador
    # ausente cai aqui tambem, com 127. Nao medir nao e aprovar.
    cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Oraculo protegido: ha missao em curso e o hook nao conseguiu ler o evento para descobrir o alvo da escrita. Nao medir nao e aprovar. Se a escrita for legitima, encerre a missao removendo runs/.missao-ativa."}}
JSON
    exit 0
fi

[ -n "$alvo" ] || exit 0
```

- [ ] **Step 4: Rodar e confirmar que passa**

Run: `sh .claude/hooks/test-proteger-oraculo.sh`
Expected: PASS, exit `0`, 17/17.

- [ ] **Step 5: Confirmar que os outros dois hooks não regrediram**

O bloco de extração é quase idêntico nos três hooks. Esta task muda só um.

```bash
sh .claude/hooks/test-impedir-copia.sh    # 28/28, exit 0
sh .claude/hooks/test-formatar-python.sh  # 10/10, exit 0
git status --short                        # nenhuma sentinela sobrando
```

- [ ] **Step 6: Commitar**

```bash
LC_ALL=C grep -cP '[^\x20-\x7e\t]' .claude/hooks/proteger-oraculo.sh .claude/hooks/test-proteger-oraculo.sh
git add .claude/hooks/proteger-oraculo.sh .claude/hooks/test-proteger-oraculo.sh
git commit -F - <<'MSG'
Deny the oracle when the event cannot be read at all

The path extractor caught every exception, printed an empty string and
exited 0, so the caller could not tell "the event carries no path" from "I
could not read the event". The `[ -n "$alvo" ] || exit 0` that follows read
both as the former and allowed the write. With a mission open, a malformed
event or a missing interpreter therefore removed the oracle protection
without saying so.

It now exits 3 on an unreadable event and keeps exit 0 with empty output for
an event that genuinely carries no path, such as a Bash call. A non-zero
code -- 127 included, which is what a missing interpreter produces -- emits a
fixed denial built by the shell. The blast radius is deliberately wider than
Task 1's: while a mission is open, an environment this broken blocks every
write, not only those under mcp/tests/. That is loud, and the reason string
names the way out. The alternative measured worse: silence.

Manager verification, not a model's report: the oracle went from 17 cases
with 1 failing at exit 1 to 17 passing at exit 0. The sibling hooks were
re-run unchanged, 28/28 and 10/10, because all three share the shape of this
extractor and only one was touched. No sentinel left on disk.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
```

---

### Task 3: Recibo

**Files:**
- Create: `audits/2026-08-31-hook-anti-copia/ADDENDUM-INTERPOLACAO.md`

**Interfaces:**
- Consumes: os números medidos nas Tasks 1 e 2.
- Produces: nada.

- [ ] **Step 1: Colher os hashes dos três recibos anteriores**

```bash
sha256sum audits/2026-08-31-hook-anti-copia/AUDITORIA.md \
          audits/2026-08-31-hook-anti-copia/ADDENDUM-CAIXA.md \
          audits/2026-08-31-hook-anti-copia/ADDENDUM-CAIXA-NOS-TRES.md
```

- [ ] **Step 2: Escrever o addendum**

Recibo selado nunca é reescrito. `ADDENDUM-CAIXA-NOS-TRES.md` diz na seção 8
que a interpolação foi observada e não corrigida — era verdade quando foi
escrito. Este addendum registra o que veio depois, citando caminho e `sha256`
dos três.

Conteúdo obrigatório: a tabela de medição do defeito reproduzida do Contexto
acima; a decisão de fechar nos dois pontos e por que diverge do
`impedir-copia.sh`; RED e GREEN de cada task com os exit codes; o raio maior da
Task 2 declarado sem eufemismo; e o limite que continua aberto — a premissa de
filesystem insensível a caixa, já declarada no addendum anterior, não muda aqui.

- [ ] **Step 3: Verificar que os anteriores continuam intactos**

```bash
sha256sum -c <<'SUM'
<os três hashes do Step 1, colados>
SUM
```
Expected: três linhas `OK`.

- [ ] **Step 4: Commitar**

```bash
git add audits/2026-08-31-hook-anti-copia/ADDENDUM-INTERPOLACAO.md
git commit -m "Record what the interpolation fix measured

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Verificação de ponta a ponta

Os oráculos provam que o script decide certo isolado. Só a ferramenta real prova
que o Claude Code obedece.

- [ ] Criar `runs/.missao-ativa` com o id `missao com 'aspa'` — o exato que
  quebrava.
- [ ] Tentar `Write` em `mcp/tests/test_x.py`. Esperado: **negado**, com a razão
  citando a missão. Antes deste plano: criava o arquivo em silêncio.
- [ ] Tentar `Write` em `mcp/src/genuino_mcp/server.py`. Esperado: **permitido**
  — fechar não pode virar bloqueio geral.
- [ ] `rm runs/.missao-ativa`, e confirmar com `git status --short` que nada sobrou.
- [ ] Tentar `Write` em `mcp/tests/test_x.py` de novo. Esperado: **permitido** —
  é o passo 1 do fluxo R7, escrever o oráculo antes de delegar.

## Fora de escopo

- O comentário truncado sobre `\134` em `proteger-oraculo.sh:38` e em
  `formatar-python.sh`. Cosmético, o autor já optou por deixar. Não tocar,
  mesmo editando o arquivo ao redor.
- Unificar os três hooks em `decidir.py`. É a alternativa recusada durante o
  conserto de caixa, e agora tem rede — os três têm oráculo. Continua sendo
  outra decisão, com outro GO.
- Levar os oráculos de hook para a CI. Declarado como limite em
  `ADDENDUM-CAIXA-NOS-TRES.md` seção 7, com a complicação de filesystem que a
  matriz ubuntu impõe.
