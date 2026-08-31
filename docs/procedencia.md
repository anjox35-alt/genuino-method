# Procedência e higiene

De onde veio cada peça deste repositório, e o que ficou de fora — com o motivo.

Este documento existe porque "unifiquei os repositórios" é uma alegação vaga.
O que segue é a lista do que entrou, do que não entrou, e a evidência de cada
decisão.

## Repositórios de origem

Oito repositórios privados de [@anjox35-alt](https://github.com/anjox35-alt),
lidos em 2026-08-30.

| Repositório | Entrou | Não entrou |
|---|---|---|
| `genuino-skill` | `SKILL.md` v4.5.0, 8 referências, contratos dos 51 gates | 6 ZIPs binários versionados; 9 validadores históricos; 2 arquivos com conflito Git commitado |
| `genuino` | — (ver nota sobre licença) | plugin completo; licença proprietária relicenciada |
| `genuino-workspace` | decisões do `green-loop.sh`, portadas para PowerShell | 668 arquivos de log; 8 cópias divergentes de skills; scripts de bootstrap com defeito declarado |
| `genuino-engineering-system` | padrão de workflow, agregador por variável de ambiente | — |
| `genuino-hook-ledger` | ideia do gate de publicação | hooks do Codex, fora do escopo desta fase |
| `guca` | validador de `SKILL.md`, portado para Python | `.tmp/` inteiro, 1605 arquivos |
| `orchestrate-production-code-v4` | política de fonte com library-id obrigatório | 4 referências órfãs; caminhos absolutos do host |
| `genuino-portable-instruction-system` | — | 3 auditorias históricas |

## Defeitos que impediram cópia direta

Cada um foi confirmado por leitura do arquivo, não presumido.

**1. Workflow com conflito Git commitado.**
`genuino-skill/.github/workflows/operational-contract.yml` tem marcadores de
conflito nas linhas 21, 25 e 29. O YAML não parseia e o workflow nunca rodou no
GitHub. O conflito era entre dois pins de `actions/checkout`. Não foi copiado; o
CI deste repositório foi escrito do zero.

**2. README com instruções contraditórias.**
`genuino-skill/README.md` tem dois blocos de conflito commitados. Um manda usar
a release publicada, o outro diz que a versão corrente está em branch sem tag.
Quem seguisse aquele README não conseguiria determinar qual pacote instalar.

**3. 1605 arquivos de lixo versionados.**
`guca/.tmp/` representa 95% dos arquivos daquele repositório e entrou num único
commit cuja mensagem é uma vírgula. São 10 cópias de um candidato, incluindo
`dist/` gerado e 9 ZIPs. O `.gitignore` do próprio repositório proíbe
exatamente esses caminhos — a regra foi contornada pela pasta `.tmp/`.

**4. Caminhos absolutos do host em artefatos.**
`orchestrate-production-code-v4` preserva caminhos como `C:\Users\<nome>\...` em
artefatos de processo. Num repositório público isso identifica a pessoa. O gate
`scan_secrets` reprova, corretamente.

**5. Núcleo do contrato divergente entre dois repositórios.**
Dos 7 arquivos compartilhados entre `genuino` e `genuino-skill`, apenas 1 é
byte-idêntico. O `CHANGELOG.md` do `genuino` afirmava convergência que não
aconteceu. Adotado como canônico o de `genuino-skill`, que é o mais recente.

## Licença

`genuino` estava sob licença proprietária; `genuino-skill` sob Apache-2.0. Um
repositório público único não comporta as duas.

Decisão do autor em 2026-08-30: **Apache-2.0 para todo o conjunto**. Ele detém
os direitos de todo o material e pode relicenciar. O registro está em
[NOTICE](../NOTICE).

## O que foi escrito do zero

**O servidor MCP.** Nenhum dos oito repositórios continha implementação de
servidor MCP — nem stdio, nem HTTP, nem Python, nem TypeScript. O que existia
era *governança sobre* MCP: registros de servidores de terceiros, políticas de
ativação, schemas de validação. Coisa diferente, e útil, mas não um servidor.

**O CI.** Os workflows aproveitam o padrão do `genuino-engineering-system`, que
era o melhor do conjunto — concurrency com cancel-in-progress, actions pinadas
por SHA, `persist-credentials: false`, e agregador lendo variável de ambiente em
vez de interpolar no shell. Mas foram escritos novos, não copiados.

## O que ficou fora do escopo por decisão

- **Java e .NET.** Nenhum dos dois está instalado na máquina do autor. Manter um
  job de CI para uma stack que não pode ser validada localmente produziria
  ciclos de push-vermelho-corrige às cegas.
- **Docker.** O cliente está presente, o daemon não respondeu. Nenhum componente
  precisa dele.
- **n8n.** Nenhum consumidor concreto no conjunto.

## Limite

Nenhum workflow dos oito repositórios de origem foi observado executando no
GitHub — a leitura foi estática, sobre o YAML. Afirmações sobre o estado de CI
daqueles repositórios seriam não verificadas, e por isso não constam aqui.
