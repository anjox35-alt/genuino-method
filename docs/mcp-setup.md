# Registro dos servidores MCP

O arquivo `.mcp.json` na raiz registra três servidores **lado a lado**, não
aninhados. Cada um responde uma pergunta diferente, e nenhum responde a do outro.

| Servidor | Responde | Precisa de rede | Precisa de chave |
|---|---|---|---|
| `genuino` | "isto passa nos gates?" | não | não |
| `context7` | "qual é a API atual desta biblioteca?" | sim | sim, gratuita |
| `codebase-memory` | "quem chama isto? o que quebra se eu mudar?" | não | não |

## codebase-memory

Grafo de conhecimento do código, servido por um binário nativo. Responde
consultas estruturais — chamadores, dependências, código morto, impacto de uma
mudança — sem reler os arquivos a cada pergunta.

Entra aqui por um motivo mensurável: o operário relia o mesmo código a cada
iteração do loop. Consulta estrutural custa uma fração disso.

O instalador oficial configura Gemini CLI, Antigravity, VS Code e Copilot
automaticamente, mas **não** o Claude Code — por isso o registro acima é manual.
O binário fica em `%LOCALAPPDATA%\Programs\codebase-memory-mcp` e o instalador o
adiciona ao PATH do usuário; uma sessão aberta antes da instalação não o
encontra até ser reiniciada.

Sem o binário instalado, o Claude Code tenta subir o servidor e a sessão
mostra `CONNECTION_CLOSED` para `codebase-memory` — sintoma esperado antes da
instalação, não defeito deste repositório. O registro em `.mcp.json` fica
mesmo assim: removê-lo puniria quem já instalou o binário para poupar quem
ainda não instalou, e nenhum dos outros dois servidores depende dele — a
tabela no topo já os registra lado a lado, cada um respondendo sozinho.

## Por que lado a lado, e não um dentro do outro

A ideia inicial era o `genuino` fazer passthrough do Context7. Ao verificar o
SDK, isso se mostrou inviável de forma limpa:

```
StreamableHTTPTransport.__init__(self, url: str) -> None
```

O transporte HTTP do pacote `mcp` 2.1.1 aceita apenas `url`. Não há parâmetro
para cabeçalho, e o Context7 exige `Authorization: Bearer`. Implementar o
passthrough exigiria contornar a API pública do SDK — código que quebraria na
próxima versão, para duplicar um servidor que o cliente já sabe conectar
sozinho.

Composição de MCPs acontece no cliente. É o caminho suportado, e é o mais
enxuto.

O que o `genuino` faz em vez disso é tornar a consulta **obrigatória e
rastreável**: `context7_query` devolve `INDETERMINADO` com a consulta pendente e
exige o library-id resolvido. Ele nunca devolve uma resposta que não tem.

## Chave do Context7

Gratuita, obtida em `context7.com/dashboard`. Segundo o README oficial ela é
*recomendada*, não obrigatória: sem chave o servidor responde com rate limit
menor.

Exporte no ambiente, nunca no arquivo:

```bash
$env:CONTEXT7_API_KEY = "<sua-chave>"
```

O `.mcp.json` usa `${CONTEXT7_API_KEY}`, então a chave nunca é versionada. Se a
variável não existir, o Claude Code carrega a configuração mesmo assim e avisa
em `claude mcp list` — o servidor simplesmente não autentica.

Alternativa de instalação assistida, que faz OAuth e registra sozinho:

```bash
npx ctx7 setup --claude
```

## Servidor genuino

Roda local, por stdio, sem rede. Nada do que ele analisa sai da máquina.

```bash
uv run --directory mcp genuino-mcp
```

Antes de confiar nele, rode a verificação:

```bash
uv run --directory mcp pytest
```

```bash
uv run --directory mcp python tests/smoke_stdio.py
```

O smoke sobe o servidor como processo separado e confere que
`mcp.server.MCPServer` resolve como `PASS` e `mcp.server.fastmcp.FastMCP` como
`FAIL`. A segunda é a API v1, legada — é o import que um modelo escreve de
memória, e que não funciona no SDK atual.

## Confirmação

Ao abrir o projeto, o Claude Code pergunta se você confia no `.mcp.json`. Essa
confirmação é do usuário, por desenho: um arquivo de repositório não deve poder
ligar servidores sozinho.
