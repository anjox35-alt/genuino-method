# genuino-mcp

Servidor MCP de verificação do método Genuíno.

Não é um agregador de MCPs de terceiros. É um conjunto pequeno de gates que
respondem a uma pergunta só: **o que este código afirma é sustentável por
evidência?**

## Por que ele existe

Um modelo que não sabe a versão atual de uma biblioteca não diz "não sei" — ele
gera o código mais provável do treino. O resultado compila na cabeça dele e falha
na sua máquina.

Caso concreto que originou este servidor: o SDK Python do MCP está na **v2**, e a
API é `MCPServer`. A API `FastMCP` é a v1, legada. Um modelo gerando de memória
escreve `from mcp.server.fastmcp import FastMCP` e produz um servidor que não
roda. A tool `resolve_library_docs` existe para que a resposta venha da
documentação, não do palpite.

## Tools

| Tool | O que impede |
|---|---|
| `resolve_library_docs` | inventar API de biblioteca — exige library-id resolvido antes de consultar |
| `scan_secrets` | vazar segredo, token ou caminho pessoal para repositório público |
| `scan_security` | vulnerabilidade — delega ao semgrep local |
| `check_bloat` | inflação — mede diff, densidade e duplicação |
| `validate_skill` | SKILL.md malformada |
| `verify_publish` | publicar árvore que reprova nos gates de publicação |

Cada tool devolve um veredito explícito e nunca converte ausência de evidência em
aprovação. Quando a ferramenta subjacente não está disponível, o resultado é
`indeterminado`, não `passou`.

## Uso

```bash
uv sync
uv run genuino-mcp
```

O servidor fala stdio. Para registrá-lo em um cliente MCP, aponte o comando para
`uv run --directory <caminho>/mcp genuino-mcp`.

## Testes

```bash
uv run pytest
```

Cada tool tem ao menos um teste que prova que ela **reprova** o caso ruim. Gate
que só foi visto aprovando não foi testado.

## Licença

Apache-2.0.
