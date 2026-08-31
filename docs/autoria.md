# Autoria e proveniência das contribuições

Quem contribuiu com o quê, quais ferramentas foram usadas, e de onde veio cada
achado.

Este arquivo existe porque faltava. Os 14 primeiros commits deste repositório
creditam `Co-Authored-By: Claude Opus 5` e mais ninguém — inclusive os que
contêm código escrito pelo Codex e correções que só existem porque um auditor
externo as apontou.

Um método chamado GENUINO que não declara quem fez o quê contradiz o próprio
nome. Esta é a correção.

---

## Autor

**Luiz Gabriel Vieira Bandeira** ([@anjox35-alt](https://github.com/anjox35-alt))
— autor do método, dono das decisões, único que altera `CLAUDE.md`.

O método é dele. Nenhum modelo, nem a Anthropic, nem a OpenAI, nem o Google, é
proprietário do que está aqui.

## Modelos que participaram

| Papel | Ferramenta | Versão | O que fez |
|---|---|---|---|
| Gerente | Claude Opus 5, via Claude Code | `claude-opus-5` | Missões, oráculos, kernel (`engine/`, `.github/`), revisão, merge |
| Operário | Codex CLI (GPT-5) | `codex-cli 0.151.0` | Implementação em worktree isolado; revisão independente do motor |
| Auditor | Gemini, via `gemini-cli` | `0.57.0` | Auditoria de premissas; confirmação dos achados do Codex |

**O auditor mudou em 2026-08-31.** O `gemini-cli` deixou de funcionar: o Google
encerrou o *Gemini Code Assist for individuals* para esse cliente
(`IneligibleTierError: UNSUPPORTED_CLIENT`) e direciona para o Antigravity, que é
aplicação Electron sem CLI headless — não invocável a partir do motor.

O papel foi para o **Nemotron 3 Ultra**, servido pela NVIDIA e chamado por
`opencode run`:

| Papel | Ferramenta | Versão / modelo | Por quê |
|---|---|---|---|
| Auditor | OpenCode + NVIDIA NIM | `opencode 1.18.25`, `nvidia/nemotron-3-ultra-550b-a55b` | Headless, `--format json`, tier gratuito, e família de modelo distinta de Claude e de GPT |

A configuração está versionada em `opencode.json`, sem segredo: a chave entra
por `{env:NVIDIA_API_KEY}`, que o autor define na própria máquina.

**Teste de aceitação do papel.** Antes de adotar o auditor, ele recebeu o
oráculo tautológico do commit `642f710` — o mesmo que passou despercebido pelo
gerente. Devolveu `INSUFICIENTE` e nomeou a causa exata: numa árvore sem
`.semgrep/rules`, `selftest_security` devolve 2 e mascara o resultado do selo,
de modo que a asserção `!= 0` passa sem que o selo tenha sido consultado.

Um auditor que não encontra nada não é auditor. Este encontrou, no primeiro
caso, o defeito que custou uma sessão.

## Contribuição por commit

`C` = Claude escreveu · `X` = Codex escreveu ou apontou · `G` = Gemini apontou ou
confirmou · `CI` = defeito revelado pela integração contínua

| Commit | C | X | G | CI | Origem do trabalho |
|---|:-:|:-:|:-:|:-:|---|
| `a73093e` | ● | | | | Unificação dos 8 repositórios de origem |
| `207f09a` | ● | | | | Motor do green loop e suíte Pester |
| `3e2392a` | ● | | | | Método normativo, selo de integridade |
| `3d3e9b4` | ● | | | | Separação worktree de trabalho / de medição |
| `cba55e2` | ● | | | | Registro do codebase-memory, três papéis |
| `b3f1583` | ● | | | | O gate de segurança não rodava de fato |
| `0e47cc4` | ● | | | | semgrep na CI |
| `01aafa8` | ● | | | ● | `$env:TEMP` não existe em Linux; a matriz pegou |
| `b685fe6` | ● | ● | ● | | Inversão blocklist→allowlist. O bypass via `conftest.py` foi encontrado pelo subagente `agent-skills:security-auditor`; os 17 achados subsequentes vieram do Codex e foram confirmados pelo Gemini |
| `642f710` | | ● | | | **A implementação de `_check_seal` é do Codex**, produzida pelo green loop em worktree isolado. Claude escreveu o oráculo — e o escreveu fraco, ver abaixo |
| `438f2d7` | ● | | | | Gate de formatação |
| `373b167` | ● | ● | ● | | Fecha 3 dos achados do Codex, declara 4 |
| `c96a844` | ● | | | | Limite: evidência não versionada |
| `79a5f52` | ● | | | ● | Teste condicional que se pulava em todo SO; só a CI mostrou |

### O caso `642f710`, em detalhe

É o único commit cuja implementação **não é minha**, e foi creditado a mim.

O Codex recebeu a missão `missions/selo-no-gate-de-publicacao.md`, trabalhou 8
minutos em worktree isolado sob `--sandbox workspace-write`, e produziu
`_check_seal` em `mcp/src/genuino_mcp/check_tree.py`. Mapeou exit codes
inesperados para `INDETERMINADO` em vez de `PASS`, respeitando o contrato de
três faixas sem que a missão mandasse.

O oráculo contra o qual ele trabalhou foi escrito por mim e estava **insuficiente**:
a asserção era `!= 0`, que passa numa árvore sem `.semgrep/rules` porque o gate
já sai com 2 sem consultar o selo uma única vez. O GREEN foi legítimo aos olhos
do motor e não provava o que dizia provar.

O defeito é do oráculo, portanto meu. O trabalho é do Codex, portanto dele.

## Skills e ferramentas invocadas

**Subagentes Claude** (mesmo modelo, prompt e contexto distintos — não são
terceira parte independente):

| Skill | Onde foi usada |
|---|---|
| `agent-skills:security-auditor` | Encontrou o bypass do `conftest.py` que originou `b685fe6` |
| `agent-skills:code-reviewer` | Revisão do motor após a inversão para allowlist |

**MCP:**

| Servidor | Uso |
|---|---|
| `context7` | Documentação de biblioteca antes de codar (regra R3). O SDK `mcp` do Python está na v2 e a API é `MCPServer`; gerar `FastMCP` de memória produz código que não roda |
| `genuino` | Os próprios gates deste repositório |
| `codebase-memory` | Consulta ao grafo do código |

**Cadeia de verificação:**

| Ferramenta | Versão | Papel |
|---|---|---|
| Pester | 6.1.0 | Testes do motor PowerShell |
| pytest | via `uv` | Testes do servidor MCP |
| ruff | via `uv` | Lint e formatação, ambos com gate na CI |
| semgrep (regras) | ruleset de 1.174.0 | Análise de segurança — regras vendorizadas, ver `.semgrep/PROVENANCE.md` |
| GitHub Actions | `ubuntu-latest`, `windows-latest` | Matriz que revelou 2 defeitos que a máquina local não mostrava |

**Licenças de terceiros:** `.semgrep/rules/` está sob **Semgrep Rules License
v1.0**, não Apache-2.0. Detalhes em `.semgrep/PROVENANCE.md`.

## Repositórios de origem

Oito, todos somente-leitura, listados com o que veio de cada um em
`docs/procedencia.md`: `genuino`, `genuino-skill`, `genuino-workspace`,
`genuino-engineering-system`, `genuino-hook-ledger`,
`genuino-portable-instruction-system`, `guca`, `orchestrate-production-code-v4`.

## Formato daqui em diante

Todo commit que incorpore trabalho ou achado de outro modelo carrega:

```
Co-Authored-By: <modelo> <endereço>

Genuino-Origem: <auditoria|missão|CI|próprio>
Genuino-Achado: <id ou caminho do relatório>
Genuino-Skills: <skills e MCP invocados>
```

Um achado corrigido e um achado esquecido não podem ter a mesma aparência no
histórico. Hoje têm.

## O que este arquivo não resolve

O histórico dos 14 primeiros commits **não é reescrito**. Eles estão assinados
por SSH e publicados; reescrevê-los quebraria as assinaturas e trocaria um
registro incorreto por um registro falsificado.

A correção é aditiva: o erro fica visível, e esta tabela diz o que ele era.

Os identificadores de achado (`Genuino-Achado`) ainda não existem — os 17
achados do Codex estão numerados no relatório, mas os commits que os fecharam
não citam o número nem o hash do relatório. Rastreabilidade por prosa não é
rastreabilidade.
