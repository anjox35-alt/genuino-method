# Auditoria de contratos entre camadas (Frontend ↔ Backend)

Carregar esta referência apenas ao auditar a coerência entre um contrato consumidor
(ex.: tipos TypeScript do frontend) e um contrato produtor (ex.: OpenAPI/JSON Schema da API,
schema Prisma do banco). Esta referência orienta AUDITORIA de contratos existentes; não
orienta criação, geração ou compilação de código.

## 1. Fixar os artefatos comparados

Antes de qualquer veredito, identificar com caminho e versão/hash: o contrato consumidor,
o contrato produtor e a direção da comparação (quem promete, quem consome). Comparar
impressões gerais de dois arquivos sem fixá-los é o mesmo erro do pacote sem sidecar.

## 2. Equivalência de tipos

| Consumidor (TS) | Produtor (OpenAPI/JSON Schema) | Produtor (Prisma) | Atenção |
| --- | --- | --- | --- |
| `string` | `type: string` | `String` | formatos (`date-time`, `uuid`) não existem no TS: verificar validação em runtime ou marcar `[LIMITE]` |
| `number` | `type: number` / `integer` | `Int`, `Float`, `Decimal` | `integer` ↔ `number` é estreitamento silencioso; `Decimal`/`BigInt` serializado como string quebra `number` |
| `boolean` | `type: boolean` | `Boolean` | — |
| `T[]` | `type: array` + `items` | `T[]` | conferir `items`, não só o invólucro |
| união literal `"a" \| "b"` | `enum: [a, b]` | `enum` | comparar VALORES um a um, não o nome do enum |
| `Date` | `type: string` + `format: date-time` | `DateTime` | JSON não tem Date: a fronteira sempre transporta string; `Date` no tipo do payload é suspeita |
| `unknown`/`any` | qualquer | qualquer | `any` no contrato consumidor anula a auditoria daquele campo: registrar `[LIMITE]` |

## 3. Nulabilidade e opcionalidade

São eixos distintos; colapsá-los é a falha mais comum.

| Situação | Consumidor | Produtor | Veredito |
| --- | --- | --- | --- |
| campo pode faltar | `campo?: T` | fora de `required` | compatível |
| campo presente mas nulo | `T \| null` | `nullable: true` / sem `@required` no Prisma (`T?`) | compatível |
| produtor permite nulo, consumidor não declara | `T` | `nullable`/`T?` | `STOP` — nulo em runtime quebra o consumidor |
| consumidor exige campo, produtor não garante | `campo: T` | fora de `required` | `STOP` |
| consumidor mais permissivo que produtor | `T \| null` | não-nulo garantido | compatível com folga; registrar como afrouxamento |

## 4. Mudanças que quebram contrato (Se → Então)

| Se a mudança no produtor for… | Então |
| --- | --- |
| remover campo que o consumidor lê | `STOP` |
| tornar obrigatório um campo de request que o consumidor não envia | `STOP` |
| estreitar tipo (`string`→`enum`, `number`→`integer`, alargar não) | `STOP` |
| adicionar valor novo a enum consumido em `switch` exaustivo | `STOP` condicional — verificar tratamento de default |
| adicionar campo opcional de resposta | compatível |
| renomear campo | `STOP` — renomear é remover + adicionar |

## 5. O que este gate não cobre

- Comportamento de runtime: serializadores customizados, interceptors, middlewares e
  transformações (`camelCase`↔`snake_case`) podem divergir do contrato declarado; contrato
  coerente não prova fronteira coerente. Testar a fronteira real quando o impacto justificar.
- Semântica de valores (unidades, moedas, fusos): tipos iguais não provam significado igual.
- Versões implantadas: comparar arquivos do repositório audita o repositório; o ambiente
  implantado exige o gate de ambientes (`SKILL.md`, "Separar ambientes e versões").

## 6. Veredito

Emitir veredito por campo apenas para divergências; agrupar os compatíveis. Todo `STOP`
nomeia campo, artefatos e a linha de cada lado. Sucesso global segue a regra geral: só com
todos os pares autorizados comparados e nenhum `STOP` aberto.
