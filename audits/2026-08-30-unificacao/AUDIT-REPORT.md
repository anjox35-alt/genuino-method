GENUINO_CANARY: GENUINO_V4_5_OPERACIONAL_CONTRACT_3_2026-08-21

# Auditoria da unificação inicial — genuino-method

Data: 2026-08-30.
Commit auditado: `3e2392ad72a8c51939f05687c704436923299c09`.
Autor do método: Luiz Gabriel Vieira Bandeira (@anjox35-alt).

## Escopo

Esta auditoria cobre **a unificação inicial**: o servidor MCP de verificação, o
conteúdo normativo migrado e selado, e o núcleo do motor em PowerShell 7.

Ela **não** cobre o método em operação de ponta a ponta. A delegação ao operário
Codex não foi exercida neste ciclo, e os adapters de superfície não foram
migrados. O que não foi medido aparece como `null` no bloco de veredito, não
como aprovação.

## Canário

O canário desta linha permanece `GENUINO_V4_5_OPERACIONAL_CONTRACT_3_2026-08-21`.

**Nenhum canário novo foi emitido, deliberadamente.** A regra do método é que o
canário avança apenas quando a semântica muda. Os doze arquivos normativos são
byte-idênticos à origem selada — o `SKILL.md` fecha em
`18e1454b89977e9f8527770773980dcdc31ad550c07ee285c4f2532effd8dcbb` nos dois
lados. Migrar sem alterar não é uma versão nova do método; carimbar uma seria
quebrar exatamente a regra que este repositório existe para fazer valer.

A linhagem de nove marcadores anteriores foi preservada intacta.

## Gates executados

### 1. Identidade byte a byte do conteúdo normativo — PASS

Doze arquivos comparados por SHA-256 contra `genuino-skill/genuino/`:
`SKILL.md`, oito referências e três contratos. Todos idênticos.

### 2. Selo de integridade — PASS

`python -m genuino_mcp.seal check ../method ../method/MANIFEST.sha256`, exit 0,
12 arquivos. O selo foi exercido nos dois sentidos: com um arquivo alterado ele
devolve exit 1 nomeando o arquivo, e volta a 0 quando o conteúdo é restaurado.

### 3. Suíte do servidor MCP — PASS

`pytest`, 47 aprovados, exit 0. `ruff check .`, exit 0.

Cada gate tem ao menos um caso que prova que ele **reprova**. Um gate visto
apenas aprovando não foi testado — foi acompanhado.

### 4. Fronteira real do servidor — PASS

`python tests/smoke_stdio.py`, exit 0. O servidor sobe como processo separado,
fala stdio e expõe oito tools. Os testes em memória provam a lógica; só o
processo real prova o empacotamento.

### 5. Núcleo do motor — PASS

`Invoke-Pester ./tests`, 18 aprovados, 0 falhas, sob PowerShell 7.6.5.

Inclui o caso que preserva a lição mais cara do motor original: diretório de
trabalho inexistente devolve `2`, nunca `1`. No motor em Bash esse defeito fez
um worktree ausente ser lido como "fronteira fechada", queimou quatro iterações
instantâneas e produziu um veredito RED sobre um ambiente quebrado.

### 6. Gate de publicação — PASS

`python -m genuino_mcp.check_tree ..`, exit 0. Varredura de segredo e de caminho
pessoal sobre a árvore inteira, incluindo `method/`.

### 7. CI multiplataforma — PASS

Três workflows, conclusão `success` observada via `gh run view`:

| Workflow | Jobs |
|---|---|
| `verify-mcp` | verify (ubuntu), verify (windows), publish gate, verify-required |
| `verify-engine` | pester (ubuntu), pester (windows), engine-required |
| `verify-method` | method integrity, method-required |

O veredito vem de `conclusion=success` lido pela API, não de leitura do YAML.

## Defeitos encontrados e corrigidos durante a auditoria

Os gates reprovaram o código deste próprio repositório quatro vezes. Cada
reprovação era legítima.

1. **`validate_skill` rejeitava o `SKILL.md` real.** O parser não entendia bloco
   escalar YAML (`description: >`) e lia cada linha de continuação como campo
   malformado. Um gate que reprova conteúdo válido acaba desligado — a pior
   falha possível. Corrigido, com teste de regressão.

2. **O manifesto do selo se auto-reportava como não selado**, porque morava
   dentro do diretório que selava. A verificação nunca passava, nem logo depois
   de ser gerada.

3. **`check_bloat` cresceu para 91 linhas** ao ganhar o próprio parâmetro de
   isenção, e reprovou a si mesma. Dividida em duas funções.

4. **O contrato de exit code do script de backup estava quebrado.** Com
   `$ErrorActionPreference = 'Stop'`, todo `Write-Error` vira exceção terminante
   e o `exit` seguinte nunca roda. É o mesmo defeito que `set -e` causava no
   motor em Bash. Encontrado pelo selftest do próprio script.

## Isenções concedidas, e por quê

**`method/` é isento de `check_bloat`, e apenas dele.** O conteúdo é importado
byte a byte de origem selada e governado pelo manifesto de hash. Refatorar para
satisfazer métrica de estilo quebraria o selo, e reescrever artefato selado é o
que o próprio método classifica como violação grave. Medir estilo ali produziria
achado sobre o qual ninguém pode agir.

A varredura de segredos continua cobrindo `method/` por inteiro. Selado ou não,
nada com formato de credencial entra em repositório público.

**Fixtures de teste com formato de segredo exigem o marcador `genuino:fixture`
na própria linha ou na anterior.** A alternativa — isentar o diretório de testes
inteiro — abriria ponto cego permanente: um segredo real vazado para dentro de
`tests/` passaria sem ser visto. Existe teste provando que o marcador isenta
apenas a linha declarada.

## Limites desta auditoria

- A delegação ao operário Codex **não foi exercida**. `codex exec` não existe em
  runner do GitHub e o loop completo não foi rodado localmente neste ciclo.
- **`semgrep` não foi executado** sobre esta árvore. O gate existe e devolve
  `INDETERMINADO` na ausência da ferramenta, o que é o comportamento correto,
  mas nenhuma varredura de segurança foi feita aqui.
- Nenhuma **release assinada** foi produzida. Não há atestação de proveniência.
- Os workflows dos oito repositórios de origem **nunca foram observados
  executando** no GitHub. A leitura daqueles repositórios foi estática.
- `scan_secrets` cobre apenas os padrões declarados em `SECRET_RULES`. Ausência
  de achado não prova ausência de segredo.
- Cinco dos oito repositórios de origem tiveram apenas decisões de projeto
  aproveitadas, não conteúdo. O conjunto ainda não substitui aqueles
  repositórios.

## Veredito

`PASS` para o escopo declarado na abertura, e somente para ele.

A unificação inicial é verificável: identidade byte a byte comprovada por hash,
selo funcionando nos dois sentidos, 65 testes automatizados entre Python e
PowerShell, e CI verde observada por API em dois sistemas operacionais.

O método em operação de ponta a ponta permanece **não verificado**.

```json
{
  "genuino_verdict": {
    "version": "0.1.0",
    "canary": "GENUINO_V4_5_OPERACIONAL_CONTRACT_3_2026-08-21",
    "status": "PASS",
    "gates": {
      "method_byte_identical_12_of_12": true,
      "seal_check": true,
      "seal_rejects_tampering": true,
      "mcp_suite": true,
      "mcp_stdio_boundary": true,
      "engine_core_suite": true,
      "publication_gate": true,
      "ci_cross_os": true,
      "codex_delegation_e2e": null,
      "semgrep_scan": null,
      "signed_release": null,
      "adapters_migrated": null
    },
    "hashes": {
      "method/skill/SKILL.md": "18e1454b89977e9f8527770773980dcdc31ad550c07ee285c4f2532effd8dcbb",
      "method/contracts/operational-contract-51.json": "8f145ac97110cc4915471e58522cd31a2b5fc142a293612996f1b41a18f07da4",
      "method/MANIFEST.sha256": "fec8f0c1b6806e48780379d03d5224654e3b69837f00d7002cdad45ef1b5c3bc",
      "commit": "3e2392ad72a8c51939f05687c704436923299c09"
    },
    "limits": [
      "A delegacao ao operario Codex nao foi exercida neste ciclo.",
      "semgrep nao foi executado sobre esta arvore.",
      "Nenhuma release assinada; sem atestacao de proveniencia.",
      "Os workflows dos oito repositorios de origem nunca foram observados executando.",
      "scan_secrets cobre apenas os padroes declarados em SECRET_RULES.",
      "Cinco dos oito repositorios de origem contribuiram decisoes, nao conteudo."
    ]
  }
}
```
