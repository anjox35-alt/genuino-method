# Checklist operacional de fontes

Carregar esta referência apenas quando uma fonte, ferramenta, documentação ou achado de
pesquisa estiver prestes a fundamentar uma decisão técnica — em especial quando algo parecer
bom demais, recém-descoberto ou sustentado só por material promocional. Os princípios gerais
de avaliação de fontes continuam no protocolo principal; aqui está o checklist enumerado.

## Dez critérios

1. A fonte é primária para a afirmação específica?
2. Existe documentação oficial que sustente o uso pretendido?
3. Existe repositório público inspecionável?
4. Há manutenção recente (commits, releases, issues respondidas)?
5. A licença é clara e compatível com o uso?
6. Há sinais de abandono (issues acumuladas, dependências quebradas, avisos de arquivamento)?
7. Há exemplos reais de uso além dos do próprio autor?
8. O ambiente alvo declarado é compatível com o ambiente real do usuário?
9. Exige cloud, API paga, credencial ou fornecedor fechado que o usuário não aprovou?
10. A documentação prova o que o material promocional promete?

## Status permitidos para o veredito da fonte

`CONFIRMADO`, `PARCIALMENTE CONFIRMADO`, `NÃO CONFIRMADO`, `CONTRADIÇÃO`, `OBSOLETO`,
`RISCO ALTO`, `DESCARTAR`. O status responde sempre à pergunta final: pode fundamentar a
decisão — sim, não ou parcialmente?

## Regras

- Output de IA não é fonte primária; segunda leitura do mesmo sistema é contra-leitura, não
  confirmação independente.
- Critério não avaliado permanece lacuna declarada; não completar o checklist por inferência.
- Reprovar em 9 (dependência não aprovada) ou em 10 (marketing sem prova) bloqueia
  `CONFIRMADO`, mesmo com os demais critérios positivos.
