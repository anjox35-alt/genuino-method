# Addendum de fechamento — o que `aad38f7` fechou, e o que esta onda consertou

Data: 2026-09-01. Autoria: ver a secao 2, que corrige o registro das rodadas
anteriores em vez de reescrever recibo nenhum.

Os quatro recibos abaixo continuam validos no que mediram. Este acrescenta o
que veio depois deles, e nao toca em nenhum.

| recibo | sha256 |
|---|---|
| `audits/2026-08-31-hook-anti-copia/AUDITORIA.md` | `b5d8e809c250f203bc1716cc92dca79bbffab244a6411c36ffa440ca48f5b082` |
| `audits/2026-08-31-hook-anti-copia/ADDENDUM-CAIXA.md` | `c8487f6b52e3b81c52f9e38ead3bc7f1ca828249f50690c83b63f12b2b0e28cb` |
| `audits/2026-08-31-hook-anti-copia/ADDENDUM-CAIXA-NOS-TRES.md` | `27784ea5670f05a2d21a6c6177a2a2b5c13c8786fdfebad0115962e6203b3a37` |
| `audits/2026-08-31-hook-anti-copia/ADDENDUM-INTERPOLACAO.md` | `5a03dc5cee78d02bc57c49efe1b81784cd52053a87159f1b8ad7153f77ee9e2d` |

Hashes recalculados sobre os bytes em disco no momento desta escrita. Os tres
primeiros conferem com os que o proprio `ADDENDUM-INTERPOLACAO.md` cita, e essa
conferencia e a evidencia de que nenhum deles foi editado desde entao.

---

## 1. As secoes 5.1 e 5.2 do ADDENDUM-INTERPOLACAO estao fechadas

Aquele recibo declara quatro limites na secao 5. Os dois primeiros foram
fechados pelo commit `aad38f7`, depois que ele foi selado:

- **5.1** — o `try/except` do extrator cobria so a chamada a `json.load`, entao
  um payload JSON valido porem nao-objeto (`null`, `42`, `[1,2]`) levantava
  `AttributeError` fora do bloco protegido e saia 1, nao o `3` desenhado. O
  try passou a cobrir tambem o acesso (`d.get`, `ti.get`). Um caso novo do
  oraculo isola o bloco do extrator a partir do proprio hook, em tempo de
  teste, e mede o codigo diretamente — nao pelo deny observavel, que ja era
  identico nos dois casos.
- **5.2** — nenhum teste dirigia `python` genuinamente ausente. Um caso novo
  restringe o PATH a wrappers finos de `git` e `cat`, mantem `python` fora
  dele, e o `command not found` chega ao hook como 127 de verdade, nao
  simulado por stub.

Numeros daquela rodada, rodados pelo gerente:

```
sh .claude/hooks/test-proteger-oraculo.sh   EXIT=0   20/20
sh .claude/hooks/test-impedir-copia.sh      EXIT=0   28/28
sh .claude/hooks/test-formatar-python.sh    EXIT=0   10/10
```

Quem abre o recibo selado sozinho, no GitHub, encontra dois limites abertos
que nao existem mais. Dentro dele nao ha conserto possivel: recibo selado nao
se reescreve, nem quando envelhece. Este addendum e a forma de corrigir.

As secoes 5.3 e 5.4 continuam valendo. O conserto I3 desta onda reduz quanto o
5.3 dispara — host sem `python` mas com `python3` deixa de contar como
ambiente quebrado —, mas nao revoga a regra: com missao aberta, um ambiente
que o hook nao consegue medir continua bloqueando toda escrita, e a saida
continua sendo remover `runs/.missao-ativa`.

## 2. Autoria — o que o registro dizia, e o que aconteceu

`ADDENDUM-INTERPOLACAO.md`, linha 3: "Autor: gerente (Claude Code), trabalho
direto". A frase e exata em `AUDITORIA.md`, que descreve uma rodada de fato
manual. Para a rodada que produziu `a178e05`, `140ba87` e `aad38f7` ela e
imprecisa — e as duas usam a MESMA frase, entao o leitor nao tem como
distinguir uma da outra.

O que aconteceu: as tasks foram DESPACHADAS a subagentes com brief escrito, e
revisadas por revisores separados. O gerente leu o diff, re-rodou os tres
oraculos por conta propria e so entao integrou.

- A R2 esta satisfeita: quem escreveu o codigo nao foi quem atestou que ele
  funciona, e o exit code lido do disco foi o do gerente, nao o relato de
  ninguem.
- A R1 nao foi violada: nenhum operario Codex, nenhum green loop, nenhum
  worktree. O kernel de governanca (`.claude/**`) nunca saiu da mao do
  gerente; os subagentes rodaram sob a autoridade dele, na mesma arvore, com
  write set escrito.

O plano tem culpa e o gerente assume: a linha 3 dele manda usar
subagent-driven-development e a linha 57 diz "O GERENTE implementa direto". O
executor teve de escolher, escolheu o despacho, e a frase de autoria do recibo
ficou herdada da rodada anterior. Num repositorio cujo produto e recibo
literalmente verdadeiro, essa e a frase que um cetico abriria primeiro.

## 3. Esta onda — RED e GREEN, achado por achado

Todo RED foi medido ANTES do conserto correspondente, com o caso novo ja no
oraculo. Exit code lido do shell, nao relatado por modelo.

| achado | RED | GREEN |
|---|---|---|
| I1 + I4 — normalizacao dentro do extrator | `test-proteger-oraculo.sh` EXIT=1, 5 de 25 reprovados | EXIT=0, 25/25 |
| I3 — interpretador em `proteger-oraculo.sh` | EXIT=1, 1 de 27 | EXIT=0, 27/27 |
| I3 — interpretador em `impedir-copia.sh` | `test-impedir-copia.sh` EXIT=1, 1 de 29 | EXIT=0, 29/29 |
| I3 — interpretador em `formatar-python.sh` | `test-formatar-python.sh` EXIT=1, 1 de 11 | EXIT=0, 11/11 |
| M1 — `notebook_path` | `test-proteger-oraculo.sh` EXIT=1, 1 de 29 | EXIT=0, 29/29 |
| regressao do proprio I4, achada na auto-revisao | EXIT=1, 2 de 32 | EXIT=0, 32/32 |

**I1 e I4, uma edicao so.** A normalizacao vivia num pipeline de dois `tr`
cujo exit code o shell descartava: faltando um dos binarios, a forma de
comparacao saia vazia, o `case` nao casava, e o hook LIBERAVA a escrita com
missao em curso — o mesmo ALLOW silencioso que o extrator fecha vinte linhas
acima. A secao 2 do `ADDENDUM-INTERPOLACAO.md` afirma fechamento "por
construcao"; aquela afirmacao nao cobria este comando. A normalizacao passou
para dentro do extrator, que ja vive sob o contrato de exit 3, e o hook nao
chama `tr` nenhum — ha um caso de oraculo que roda o hook com o PATH sem `tr`
e exige deny. Junto veio o I4: `posixpath.normpath` colapsa `//`, `.` e `..`
como o filesystem colapsa, entao `mcp//tests/x.py`, `mcp/./tests/x.py` e
`mcp/src/../tests/x.py` deixam de passar, e `mcp/tests/../src/x.py` deixa de
ser tratado como oraculo. `posixpath` explicito, e nao `os.path`, que no
Windows reintroduz a barra invertida.

**Regressao do proprio conserto.** O `normpath` remove o `./` inicial, entao
`./mcp/tests/x.py` chegava ao `case` como `mcp/tests/x.py`, sem a barra que o
padrao `*/mcp/tests/*` exige: um caminho que o hook negava ANTES da
normalizacao passaria a ser liberado depois dela. Achado relendo o proprio
diff, medido com casos novos, fechado com um segundo padrao no `case`. Fica
registrado porque conserto que abre buraco novo e o defeito que esta base
existe para expor, inclusive quando quem abriu foi o gerente.

**I3 nos tres hooks.** `python` nao existe de fabrica em Linux e macOS
recentes; la o binario chama-se `python3`. Em `proteger-oraculo.sh` isso
significava 127 e, com qualquer sentinela presente, deny em TODA escrita da
sessao. Nos outros dois significava o oposto: o hook nao rodava e ninguem
avisava — a R4 virava texto de novo, e o `ruff format` da CI voltava a ser o
primeiro a reclamar. Aplicado nos tres, com a mesma forma:

```sh
py=""
for candidato in python python3; do
    if command -v "$candidato" >/dev/null 2>&1; then
        py=$candidato
        break
    fi
done
```

e `"${py:-python}" -c ...` na chamada. Resolver amplia onde o hook consegue
MEDIR, nunca onde ele libera: sem nenhum dos dois, o fallback e `python`, que
sai 127 e cai no deny de sempre. Num host que ja tem `python` — este — a
tabela de decisao dos tres hooks e identica a de antes, e os 72 casos verdes
sao a evidencia disso.

**M1.** O matcher em `.claude/settings.json` inclui `NotebookEdit`, que nao
manda `file_path` e sim `notebook_path`. O extrator lia dois campos; o irmao
`impedir-copia.sh` ja lia os tres. Um notebook sob `mcp/tests/` durante missao
dava alvo vazio, e o hook liberava.

**Minors sem RED, por nao mudarem comportamento medido.** M2: o `python -c` de
`formatar-python.sh` passou de aspas duplas para simples — nao ha `$` dentro
da fonte, entao nao era defeito vivo, mas e o construto que ja falhou uma vez
nesta base. M4: os tres `mktemp` sem checagem em `test-proteger-oraculo.sh`
ganharam `|| exit 2`, na forma que `test-formatar-python.sh` ja usava; sem
isso, um `mktemp` falho poria o diretorio corrente na frente do PATH. M8:
`docs/limites.md` dizia "47 casos" e agora diz 72, e a mesma celula deixou de
atribuir a `proteger-oraculo.sh` um `tr` que ele nao usa mais. `.gitignore`
ganhou `.agents/` e `.codex/`, que sao ajuste de host e nao o metodo.

## 4. I2 — limite declarado, nao consertado

Primeira linha util de `proteger-oraculo.sh`:

```sh
raiz=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
```

Se o `git` falhar ou nao existir, o hook LIBERA antes de conseguir procurar a
sentinela. E falha aberta, no hook cuja doutrina e fechar.

**Decisao do gerente: declarar, nao consertar.** Cair para
`$CLAUDE_PROJECT_DIR` alargaria de novo o raio que esta rodada acabou de
calibrar, e sem repositorio nao se sabe sequer se ha missao — negar ali seria
negar no escuro. O limite fica declarado aqui, que e o unico lugar onde
declara-lo nao custa comportamento.

## 5. Teto do harness, acima do script

`.claude/settings.json` poe `"timeout": 20` nos dois hooks de `PreToolUse`. Um
hook que estoure esse tempo nao produz deny: a garantia de fechamento e
limitada pelo Claude Code, nao pelo script.

Classificado com honestidade: o `timeout: 20` e FATO, esta no arquivo e
qualquer um le. O que o harness faz com um hook que estoura o tempo e NAO
VERIFICADO por este repositorio — nenhum oraculo daqui mede o comportamento do
Claude Code, e nenhum poderia sem dirigir o proprio harness. Fica dito porque
quem confia na protecao precisa saber que o ultimo degrau dela nao esta neste
diretorio.

## 6. Numeros finais e write set

```
sh .claude/hooks/test-proteger-oraculo.sh   EXIT=0   32/32
sh .claude/hooks/test-impedir-copia.sh      EXIT=0   29/29
sh .claude/hooks/test-formatar-python.sh    EXIT=0   11/11
```

72 casos. Nenhuma sentinela sobreviveu a nenhuma rodada: `git status --short`
foi conferido depois de cada uma.

```
.claude/hooks/proteger-oraculo.sh        M  I1, I3, I4, M1 e a regressao do I4
.claude/hooks/impedir-copia.sh           M  I3
.claude/hooks/formatar-python.sh         M  I3 e M2
.claude/hooks/test-proteger-oraculo.sh   M  20 -> 32 casos, e M4
.claude/hooks/test-impedir-copia.sh      M  28 -> 29 casos
.claude/hooks/test-formatar-python.sh    M  10 -> 11 casos
docs/limites.md                          M  M8
.gitignore                               M  .agents/ e .codex/
audits/2026-08-31-hook-anti-copia/ADDENDUM-FECHAMENTO.md  +  este recibo
```

Nada em `mcp/`, `engine/`, `.github/` ou `method/`. Nenhum recibo selado
tocado. Commitado nesta rodada; push nao acontece.
