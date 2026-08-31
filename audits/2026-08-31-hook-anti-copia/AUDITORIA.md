# Auditoria — hook anti-copias da R4

Data: 2026-08-31. Autor: gerente (Claude Code), trabalho direto.

Nao houve green loop. A R1 poe `.claude/**` no kernel de governanca, que nunca
e delegado ao operario: o vigiado nao redige o regulamento da vigilancia.

---

## 1. O achado

A R4 proibe `*_v2*`, `*_copy*`, `*_final*`, `*_new*`, `*_backup*`, `*_old*` e
`* (1)*`, e diz textualmente que "a regra vale mesmo se o hook falhar" —
pressupondo um hook. Ele nao existia.

```
$ grep -rniE "_v2|_copy|_final|_backup|_old|copia" \
    mcp/src engine .github/workflows .claude .githooks
mcp/src/genuino_mcp/seal.py:3: [comentario sobre conteudo copiado]
```

Unico acerto, e era comentario. Nem hook, nem gate na CI, nem check_tree.
A R4 era cumprida so por disciplina — a mesma condicao que o comentario do
`.githooks/pre-push` ja registra nesta base como tendo falhado uma vez.

## 2. RED (R7, passo 1)

Oraculo escrito primeiro, em `.claude/hooks/test-impedir-copia.sh`, 19 casos.

```
$ sh .claude/hooks/test-impedir-copia.sh
ORACULO VERMELHO: 11 de 19 casos reprovados.
EXIT=1
```

**Limite honesto do RED.** So os 11 casos de `deny` reprovaram. Os 8 de `allow`
passaram vacuamente, porque um hook inexistente libera tudo. Pela R7, teste que
nasce passando nao prova nada — esses 8 nao provaram nada naquele momento.
Existem para o risco inverso, o de bloqueio excessivo, e so ganham poder
discriminante depois da implementacao.

## 3. DECISAO — por que o padrao e ancorado no fim do nome

Os globs da R4 tem `*` dos dois lados. Aplicados ao pe da letra, `*_final*`
reprova `test_finalize.py`, `*_copy*` reprova `test_copyright.py` e `*_new*`
reprova `parser_newline.md`. Um gate que reprova esses tres e desligado pelo
operador na primeira semana — e a R4 volta a ser texto, que e o estado que este
hook existe para encerrar.

Regra implementada: o padrao so conta quando termina o nome ou vem antes de um
ponto — `(_v2|_copy|_final|_new|_backup|_old|\s\(\d+\))(\.|$)`. E a forma como
copia de fato se chama: `server_v2.py`, `relatorio_final.md`, `notas (1).md`,
`archive_old.tar.gz`, `Makefile_old`.

**Segunda decisao:** `\(\d+\)` em vez do literal `(1)` da R4. O Windows gera
`(2)`, `(3)` e adiante; bloquear so `(1)` deixaria o buraco aberto na segunda
copia. Ampliacao deliberada e reversivel.

**Terceira decisao:** arquivo que ja existe no disco passa. Editar um legado mal
nomeado nao e criar copia, e bloquear isso deixaria o proprio legado sem
conserto.

**Quarta decisao:** falha aberto. Se o json nao parseia ou o python some, o hook
libera. Um hook protetor que fecha em erro de ambiente trava a sessao inteira, e
a propria R4 declara que a regra nao depende deste mecanismo para valer. E o
unico ponto onde este hook diverge da doutrina "nao medir nao e aprovar" do
`pre-push`, e diverge porque o custo do erro e assimetrico: push bloqueado se
recupera, sessao travada nao.

## 4. GREEN

```
$ sh .claude/hooks/test-impedir-copia.sh
ORACULO VERDE: 19/19 casos.
EXIT=0
```

## 5. Prova ponta a ponta, na sessao viva

Nao basta o script decidir certo isolado; o Claude Code precisa obedecer.
Duas escritas reais pela ferramenta `Write`, em arquivos descartaveis do
scratchpad:

| alvo | resultado |
|---|---|
| `prova_final.md` | **negado**, com a razao da R4 devolvida ao modelo |
| `prova-nome-normal.md` | criado normalmente |

**Refutacao de um item da documentacao.** A skill `plugin-dev:hook-development`
afirma que hooks carregam so no inicio da sessao e que alterar a configuracao
exige reiniciar o Claude Code. Nesta sessao isso nao se sustentou: o hook foi
registrado no `settings.json` e passou a bloquear sem nenhum reinicio.
Observacao de um caso, nesta versao, neste host — nao generalizada.

## 6. Limites conhecidos

- `server_v2_corrigido.py` passa. O sufixo esta no meio do nome, e fechar isso
  reabre o falso positivo em `_finalize`, `_copyright`, `_newline`. A fronteira
  escolhida esta registrada em caso no oraculo, para quem quiser move-la.
- O hook so ve `Write`, `Edit` e `NotebookEdit`. Copia feita por `Bash`
  (`cp`, `git mv`) passa livre. Fechar isso e outro matcher, outro escopo.
- Falha aberto, como declarado em 3.

## 7. Nao verificado

- Comportamento em shell nao-Windows. Todos os casos rodaram em Git Bash neste
  host.
- Interacao com o hook `proteger-oraculo.sh` quando ambos negam a mesma escrita.
  Os dois rodam em paralelo no mesmo matcher e nao foram exercitados juntos.
- Se o hook dispara para o operario dentro do worktree do green loop.

## 8. Write set

```
.claude/hooks/impedir-copia.sh        (novo)
.claude/hooks/test-impedir-copia.sh   (novo, oraculo)
.claude/settings.json                 (+6 linhas, um bloco em PreToolUse)
audits/2026-08-31-hook-anti-copia/    (este registro)
```

Nenhum arquivo fora disso. Nada commitado, nada empurrado.
