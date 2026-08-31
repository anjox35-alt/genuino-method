# genuino-method

Um método de engenharia com IA, e as ferramentas que o tornam executável.

O problema que ele ataca é específico: **quando um modelo não sabe, ele não diz
que não sabe — ele gera o texto mais provável.** O resultado compila na cabeça
dele e falha na sua máquina. Este repositório existe para tornar essa falha
detectável antes do commit, não depois do deploy.

Autor: Luiz Gabriel Vieira Bandeira ([@anjox35-alt](https://github.com/anjox35-alt)).

## O caso que originou tudo

O SDK Python do Model Context Protocol está na **v2**, e a API é `MCPServer`.
A API `FastMCP` é da v1, legada.

Peça a qualquer modelo um servidor MCP em Python e há uma boa chance de receber
`from mcp.server.fastmcp import FastMCP` — a resposta mais provável do treino, e
um servidor que não sobe. Nenhum aviso, nenhuma hesitação.

Este repositório responde isso em milissegundos, offline:

```
mcp.server.MCPServer        -> PASS
mcp.server.fastmcp.FastMCP  -> FAIL
```

## Componentes

| Pasta | O que é | Estado |
|---|---|---|
| `mcp/` | Servidor MCP com os gates de verificação | funcional, 82 testes |
| `engine/` | Motor do green loop em PowerShell 7 | funcional, 73 testes, GREEN de ponta a ponta |
| `method/` | Skill v4.5.0, contratos e referências | migrado, selado por SHA-256 |
| `missions/` | Missões executáveis pelo loop | 3 (smoke, selo, núcleo-01) |
| `audits/` | Relatórios de auditoria e revisão | 2 |
| `attic/` | Obsoletos preservados, com motivo registrado | vazio |

## Os três papéis

O método separa quem escreve de quem mede, e de quem audita quem mede.

| Papel | Quem | Sandbox | Escreve |
|---|---|---|---|
| Gerente | Claude Code | árvore principal | testes de aceitação, kernel, merge |
| Operário | Codex | worktree descartável, sem rede | implementação do produto |
| Revisor | Codex ou Gemini | somente leitura | nada |

A separação está no sandbox, não na promessa. Detalhes e limitações em
[docs/papeis.md](docs/papeis.md).

**O operário escreve num worktree; os gates rodam em outro.** O patch é gerado
excluindo os caminhos declarados como `ORACULO` e aplicado num worktree limpo do
commit-base congelado. Adulterar o teste de aceitação não compra nada — e fica
registrado como violação nomeada.

Esse desenho não foi projetado assim desde o início: ele veio de uma revisão
adversarial que encontrou 17 defeitos na primeira versão, todos confirmados por
um segundo modelo de forma independente. Os relatórios estão em
[audits/2026-08-31-revisao-codex/](audits/2026-08-31-revisao-codex/).

## Os gates

Cada um ataca uma forma concreta de erro. Nenhum deles converte ausência de
evidência em aprovação.

| Tool | O que impede |
|---|---|
| `verify_python_symbol` | inventar API — confirma o símbolo no ambiente instalado agora |
| `verify_node_package` | confundir faixa declarada com versão resolvida |
| `context7_query` | responder sobre lib de terceiro sem library-id resolvido |
| `scan_secrets` | vazar segredo ou caminho pessoal para repositório público |
| `scan_security` | vulnerabilidade, via semgrep local com regras vendorizadas |
| `selftest_security` | ruleset esvaziado ou corrompido devolvendo PASS em silencio |
| `check_bloat` | inflação: arquivo longo, função longa, bloco duplicado |
| `validate_skill` | SKILL.md malformada |
| `verify_publish` | publicar árvore que reprova em qualquer gate acima |

## O contrato de três faixas

Herdado do motor original e preservado em todo o conjunto:

```
0    passou
1    reprovação medida
>=2  não foi possível medir -- é falha de ambiente, não do código
```

Colapsar `1` e `2` é o erro que faz um pipeline gastar tentativas com problema de
ambiente e declarar reprovação onde não houve medição. No servidor MCP a mesma
distinção aparece como `PASS`, `FAIL` e `INDETERMINADO`.

**`INDETERMINADO` nunca deve ser lido como `PASS`.** Se o semgrep não está
instalado, o veredito não é "seguro" — é "não medido".

## Uso

```bash
uv sync --directory mcp
```

```bash
uv run --directory mcp pytest
```

```bash
uv run --directory mcp python tests/smoke_stdio.py
```

Gate de publicação sobre a árvore inteira, antes de qualquer push:

```bash
uv run --directory mcp python -m genuino_mcp.check_tree ..
```

Para registrar o servidor no seu cliente MCP, veja [docs/mcp-setup.md](docs/mcp-setup.md).

## Requisitos

- Python 3.10 ou superior (o SDK `mcp` exige)
- PowerShell 7, para o motor
- semgrep, opcional — sem ele o gate de segurança devolve `INDETERMINADO`

Java e .NET estão fora de escopo por decisão do autor.

## Limites declarados

- A etapa de delegação ao operário chama `codex exec`, que não existe em runner
  do GitHub. Ela é local e fica **fora** do veredito da CI, marcada como tal.
  Um CI que fingisse rodar o loop completo estaria mentindo.
- `scan_secrets` cobre apenas os padrões declarados em `SECRET_RULES`. Ausência
  de achado não prova ausência de segredo.
- `check_bloat` mede tamanho e repetição. Não julga corretude nem necessidade.
- `validate_skill` valida forma, não conteúdo.

## Licença

Apache-2.0. Veja [LICENSE](LICENSE) e [NOTICE](NOTICE) — o NOTICE registra a
procedência de cada componente e a relicenciamento do material que vinha de um
repositório proprietário do mesmo autor.
