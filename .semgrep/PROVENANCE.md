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

SHA256 no ato da vendorização: ver SHA256SUMS neste diretório.

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
