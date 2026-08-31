# Auditoria do oráculo — `nucleo-01-veredito-publicavel`

**Primeira auditoria de oráculo do método.** Até aqui, o gerente escrevia o
teste de aceitação e o próprio gerente decidia se ele bastava — o limite 1 de
`docs/limites.md`, sem mitigação.

**Auditor:** `nvidia/nemotron-3-ultra-550b-a55b`, servido pela NVIDIA, invocado
antes de a missão ser delegada ao operário.
**Data:** 2026-08-31.
**Alvo:** `mcp/tests/test_publish.py`, contra `missions/nucleo-01-veredito-publicavel.md`.

O auditor não viu implementação — ela não existia. Auditou a pergunta, não a
resposta.

---

## Rodada 1 — INSUFICIENTE

> **MUTANTE:** Implementação que só substitui `repo_root` por `<REPO>`, só recusa
> nos padrões exatos testados (`D:\`, `/home/`, `/Users/`), ignora `<TMP>` e
> `<HOME>` e não detecta outros absolutos (`/tmp`, `/var`, `E:\`, etc.) passa em
> todos os testes.
>
> **LACUNA:** Missão exige três marcadores (`<REPO>`, `<TMP>`, `<HOME>`) mas
> oráculo só testa `<REPO>`.

Ambos procedem.

O oráculo media um terço do que a missão exigia, e a recusa era verificável por
enumeração: `if x.startswith(("D:", "/home/")): raise` passaria em tudo. O teste
estaria medindo a própria lista de exemplos.

**Correções aplicadas:**

- `test_temporario_e_home_viram_marcadores` — mede os três marcadores, e afirma
  que nenhum caminho real sobreviveu.
- `test_recusa_qualquer_absoluto_nao_reconhecido` — sete formas distintas
  (`D:\`, `E:\`, UNC `\\servidor\`, `/var/`, `/opt/`, `/Users/`, `/srv/`), para
  que enumerar deixe de ser suficiente.
- A missão passou a declarar explicitamente que a recusa é sobre a **forma** do
  caminho, não sobre prefixos conhecidos.

## Rodada 2 — LACUNA remanescente

O auditor reconheceu as correções e apontou o que ainda faltava:

> `tmp_dir` e `home_dir` default para `tempfile.gettempdir()` e `Path.home()` →
> **NÃO TESTADO!** Os testes sempre passam `tmp_dir` e `home_dir` explícitos.
> Não há teste para os defaults.

Procede, e é o caso de uso normal: quem chama a função sem os argumentos —
qualquer script real — teria caminho pessoal vazando sem recusa. Todo o oráculo
media o caminho de injeção, que só os testes usam.

**Correção aplicada:** `test_os_defaults_de_tmp_e_home_sao_reais`, com
`monkeypatch` sobre `Path.home` e `tempfile.gettempdir` para não depender da
máquina de quem roda.

A resposta desta rodada foi truncada pelo `max_tokens` do chamador antes do
veredito formal. O achado veio antes do corte e é registrado como está — em
`RODADA-2.md`, com o truncamento visível.

---

## O que esta auditoria custou e o que evitou

Duas chamadas, 56s e 116s, ~11.800 tokens, custo zero no tier gratuito.

Evitou entregar ao operário um contrato que media um terço do que prometia. Na
missão anterior, um oráculo insuficiente passou despercebido e o operário
produziu um GREEN legítimo aos olhos do motor sobre um teste que não provava
nada — ver `docs/autoria.md`, caso `642f710`.

A diferença entre as duas missões não é o cuidado do gerente. É que nesta havia
alguém para discordar dele.

## Limites desta auditoria

- O prompt do auditor é escrito pelo gerente. Quem formula a pergunta limita as
  respostas — o limite 1 num degrau acima, não eliminado.
- O auditor não executou os testes. Leu a missão e o oráculo, e raciocinou sobre
  mutantes. Nenhum achado foi verificado por execução.
- Duas rodadas foram feitas, não até convergir. A terceira poderia encontrar
  mais; não foi tentada, e isso é escolha, não conclusão.
- Um modelo que erra de forma diferente ainda erra. Independência reduz modo de
  falha compartilhado; não produz verdade.

## Achado colateral, sobre o motor

Ao confirmar o RED, o `pytest` saiu com **2**, não 1: o módulo não existia, e o
`ImportError` no topo do arquivo é erro de *coleta*.

No contrato de três faixas, 2 significa "não foi possível medir", e
`Invoke-GreenLoop.ps1:240` aborta o loop nesse caso. Consequência: **qualquer
missão que crie um módulo do zero seria impossível de iniciar.**

A correção ficou no oráculo, não no motor: o import é adiado para dentro de um
helper, e o que era um erro de coleta vira N falhas de teste, cada uma com a sua
mensagem. Baseline passou a exit 1 — reprovação medida, que é o que o RED de uma
missão nova deve ser.

Mexer no motor para aceitar 2 no baseline teria sido a correção errada: apagaria
a distinção entre "o código ainda não existe" e "o ambiente está quebrado", que é
justamente o que o contrato de três faixas existe para preservar.
