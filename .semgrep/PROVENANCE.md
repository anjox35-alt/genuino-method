# Procedência do ruleset semgrep vendorizado

Por que existe: `semgrep --config auto` baixava ~1074 regras do servidor a
cada execução do gate G4 e, com `--metrics=auto`, enviava telemetria
justamente por o config vir do servidor. Um gate cujo conteúdo chega da rede
em tempo de execução não é reprodutível nem auditável: a mesma árvore podia
passar hoje e reprovar amanhã sem que uma linha de código mudasse. Mesma
classe do defeito A1 (binários), agora em regras de análise.

FONTE: registry oficial do Semgrep, https://semgrep.dev/c/p/<pack>
BAIXADO EM: 2026-08-23
SEMGREP: 1.174.0

| arquivo | pack de origem | regras |
|---|---|---|
| security-audit.yaml| p/r2c-security-audit  | 225 |
| secrets.yaml       | p/secrets             | 52  |

425 regras no total, 336 ids únicos (packs se sobrepõem; semgrep deduplica).

SHA256 no ato da vendorização: ver `SHA256SUMS` neste diretório.

Os dois hashes conferidos em 2026-08-31 contra os arquivos trazidos:

```
d87e8a69a68b1df2531cf9accd1dfaee6f0e42e7b06b8eba854b0184ddc3c3c0  security-audit.yaml
139b35ad3442bc83d1f0864db82fa4fdc7e1f1ee4b5ac872bfbeb604c82c6518  secrets.yaml
```

São idênticos aos registrados na vendorização original, o que prova que a cópia
entre repositórios foi byte a byte. O `SHA256SUMS` deste diretório lista apenas
os dois arquivos efetivamente trazidos — o do repositório de origem inclui
`javascript.yaml` e `typescript.yaml`, que ficaram de fora.

## Licença das regras

As regras trazidas declaram, em seus próprios metadados, **Semgrep Rules
License v1.0** (`semgrep.dev/legal/rules-license`). Não são Apache-2.0.

Este repositório é Apache-2.0; `.semgrep/rules/` não é. São artefatos de
terceiros redistribuídos sob a licença do autor original, e a licença viaja
com os arquivos: cada regra carrega o campo `license` no próprio YAML.

Quem for reutilizar `.semgrep/rules/` fora deste repositório responde à licença
do Semgrep, não à deste projeto.

## Atualizar

Trocar regra é mudança de gate: refaça o download do registry, revise o diff
do YAML, rode `bash scripts/g4-selftest.sh` e só então commite. Não atualize
em massa sem ler o que mudou — regra nova pode reprovar código legítimo, e
regra removida abre buraco silencioso.

---

## Adaptação para genuino-method

Copiado de `genuino-workspace/.semgrep` em 2026-08-31, mantendo a procedência
original acima.

Apenas `security-audit.yaml` (225 regras) e `secrets.yaml` (52) foram trazidos.
Os packs `p/typescript` e `p/javascript` ficaram de fora: este repositório é
Python e PowerShell, e regras que não casam com nenhum arquivo só aumentam o
tempo do gate sem aumentar a cobertura.

O `security-audit` cobre Python; o `secrets` é baseado em regex e vale para
qualquer linguagem — inclusive PowerShell, que o semgrep não analisa
sintaticamente.

**Limite:** nenhum ruleset cobre PowerShell de forma estrutural. Para os
arquivos `.ps1` deste repositório, a análise é apenas por regex de segredo.
Isso é uma lacuna real, não uma escolha.
