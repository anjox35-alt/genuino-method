# Contrato operacional dos 51 gates

Este documento é uma regra de execução do Genuíno para entregas técnicas. Ele não pede uma auditoria depois da implementação: obriga uma decisão antes da geração de código, infraestrutura, integração, arquitetura, modelo de IA ou aprovação de deploy.

## Resultado obrigatório por entrega

Cada um dos 51 IDs abaixo deve constar no recibo de decisão com um único estado:

- `APLICAR`: o gatilho ocorre; registrar fonte primária/oficial e evidência concreta no projeto.
- `NAO_APLICA`: o gatilho não ocorre; registrar por que ele não ocorre neste sistema.
- `BLOQUEADO`: falta dado material; parar a decisão dependente e pedir esse dado.
- `EXCECAO_AUTORIZADA`: há desvio deliberado; registrar risco, controle compensatório, autoridade e validade.

Não usar `NAO_APLICA` para pular análise. Não aplicar uma tecnologia só porque consta aqui. A classificação é obrigatória; a implementação depende do gatilho, da evidência e do risco.

O recibo corrente declara `schema_version: 1.1.0`. `project_evidence` e `primary_sources`
são arrays não-vazios de textos não-vazios; campos de topo e de decisão seguem allowlists
fechadas, com `evidence_manifest` como única extensão de topo prevista. Toda
`EXCECAO_AUTORIZADA` usa `expires_at` futuro em RFC 3339 com offset; formato inválido ou prazo já
vencido produz `STOP`. O validador estrutural continua sem afirmar a verdade da evidência.

## Fontes na execução

As fontes abaixo são pontos de partida primários/oficiais. Antes de basear uma decisão em uma delas, conferir a versão vigente, o escopo e a aderência ao ambiente real. A fonte não substitui a evidência do projeto.

# I. Design e padrões de arquitetura

## ARQ-P01 — Failover

**Gatilho.** Há requisito explícito de continuidade quando uma instância, zona ou rota falhar.

**Decisão requerida.** ADOTAR somente se houver fluxo crítico com SLO, RTO e RPO aprovados; destino redundante com capacidade testada; health check representativo; política explícita de promoção/failback; e ensaio de falha que meça detecção, TTL/cache, reconexão e integridade de dados. NÃO aprovar “failover instantâneo por DNS” sem evidência de cliente a cliente.

**Evidência mínima.** Plano de saúde, promoção, retorno seguro e RTO/RPO compatíveis.

**Bloqueio.** Não aprovar continuidade alegada sem teste de falha ou topologia equivalente.

**Fontes primárias/oficiais para consultar na entrega.**
- [AWS Route 53 - DNS failover e health checks](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover.html) — documentacao-oficial-ou-projeto-primario
- [AWS Route 53 - TTL de registros de failover](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-values-failover.html) — documentacao-oficial-ou-projeto-primario
- [Azure - testes de confiabilidade e definição de failover](https://learn.microsoft.com/en-us/azure/well-architected/reliability/reliability-test) — documentacao-oficial-ou-projeto-primario

## ARQ-P02 — Hexagonal Architecture / Ports and Adapters

**Gatilho.** Há lógica de negócio com framework, banco, UI ou mensageria que pode substituir ou evoluir.

**Decisão requerida.** ADOTAR quando o núcleo possui regras relevantes, precisa de testes sem infraestrutura ou há pelo menos duas implementações/uma substituição plausível numa fronteira. Exigir mapa de dependências apontando para dentro e teste do caso de uso sem rede/banco. NÃO ADOTAR abstrações especulativas para CRUD trivial sem pressão de mudança.

**Evidência mínima.** Portas do domínio, adaptadores de entrada/saída e teste do núcleo sem infraestrutura.

**Bloqueio.** Bloquear acoplamento de regra de negócio diretamente a framework ou persistência sem decisão registrada.

**Fontes primárias/oficiais para consultar na entrega.**
- [Alistair Cockburn - artigo original de Hexagonal Architecture](https://alistair.cockburn.us/hexagonal-architecture) — autor-ou-publicacao-primaria
- [AWS Prescriptive Guidance - Hexagonal Architecture](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/hexagonal-architecture.html) — documentacao-oficial-ou-projeto-primario

## ARQ-P03 — BFF - Backend for Frontend

**Gatilho.** Existem experiências de cliente materialmente diferentes e o backend comum causa over-fetching, acoplamento ou release acoplado.

**Decisão requerida.** ADOTAR somente quando dois tipos de cliente têm contratos, cadências ou restrições mensuravelmente diferentes e existe ownership por experiência. Exigir matriz cliente×necessidade e proibir persistência/regra de negócio exclusiva no BFF sem decisão registrada. NÃO ADOTAR apenas para renomear um gateway ou criar uma camada pass-through.

**Evidência mínima.** Contrato por cliente, limite de responsabilidade e prova de que BFF não duplica domínio.

**Bloqueio.** Não criar BFF apenas por moda; exigir benefício mensurável por canal.

**Fontes primárias/oficiais para consultar na entrega.**
- [Azure Architecture Center - Backends for Frontends](https://learn.microsoft.com/en-us/azure/architecture/patterns/backends-for-frontends) — documentacao-oficial-ou-projeto-primario
- [Chris Richardson - API Gateway e variação BFF](https://microservices.io/patterns/apigateway.html) — fonte-de-apoio-a-confirmar-na-execucao

## ARQ-P04 — API Gateway

**Gatilho.** Clientes externos precisam acessar múltiplos serviços ou políticas transversais.

**Decisão requerida.** ADOTAR quando há múltiplos backends/consumidores e pelo menos duas políticas transversais justificadas. Exigir implantação redundante, orçamento de latência, teste de carga/falha, versionamento de políticas e bloqueio de acesso público direto aos backends quando aplicável. NÃO ADOTAR como salto extra sem necessidade mensurável.

**Evidência mínima.** Contrato de borda, autenticação/autorização, limites, roteamento e observabilidade.

**Bloqueio.** Bloquear exposição direta de microsserviços públicos sem decisão de fronteira.

**Fontes primárias/oficiais para consultar na entrega.**
- [Azure Architecture Center - API gateways](https://learn.microsoft.com/en-us/azure/architecture/microservices/design/gateway) — documentacao-oficial-ou-projeto-primario
- [Azure API Management - conceitos do gateway](https://learn.microsoft.com/en-us/azure/api-management/api-management-key-concepts) — documentacao-oficial-ou-projeto-primario
- [Amazon API Gateway - documentação](https://docs.aws.amazon.com/apigateway/latest/developerguide/welcome.html) — documentacao-oficial-ou-projeto-primario

## ARQ-P05 — Transactional Outbox

**Gatilho.** Uma transação local precisa publicar evento para outro sistema sem perder consistência.

**Decisão requerida.** ADOTAR quando uma operação precisa alterar estado local e notificar outro sistema sem 2PC. Exigir message_id, chave de ordenação, consumidor idempotente/inbox ou deduplicação, política de retry/DLQ, métrica de idade da outbox e teste de crash após publish. REPROVAR qualquer desenho que prometa ausência de duplicatas apenas por usar outbox.

**Evidência mínima.** Tabela/outbox transacional, relay, idempotência do consumidor e estratégia de retry/DLQ.

**Bloqueio.** Bloquear dual-write direto quando a perda ou duplicação de evento for material.

**Fontes primárias/oficiais para consultar na entrega.**
- [Chris Richardson - Transactional Outbox](https://microservices.io/patterns/data/transactional-outbox.html) — fonte-de-apoio-a-confirmar-na-execucao
- [AWS Prescriptive Guidance - Transactional Outbox](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html) — documentacao-oficial-ou-projeto-primario
- [AWS Builders’ Library - APIs idempotentes](https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-APIs/) — documentacao-oficial-ou-projeto-primario

## ARQ-P06 — Blue-Green Deployment

**Gatilho.** O release exige rollback rápido e tráfego pode alternar entre versões compatíveis.

**Decisão requerida.** ADOTAR quando o custo do segundo ambiente cabe no orçamento e a troca é automatizável. Exigir artefato imutável, paridade comprovada, smoke/health checks, plano de sessão/job, migração de banco backward/forward compatible e teste de rollback com dados reais mascarados. REPROVAR se “rollback” depende de restaurar banco não ensaiado.

**Evidência mínima.** Compatibilidade de schema, health checks, plano de troca, rollback e custo de dois ambientes.

**Bloqueio.** Bloquear troca de tráfego sem compatibilidade demonstrada de banco e contratos.

**Fontes primárias/oficiais para consultar na entrega.**
- [Martin Fowler - Blue Green Deployment](https://martinfowler.com/bliki/BlueGreenDeployment.html) — autor-ou-publicacao-primaria
- [Martin Fowler - Continuous Integration e blue-green](https://martinfowler.com/articles/continuousIntegration.html) — autor-ou-publicacao-primaria

## ARQ-P07 — Sidecar

**Gatilho.** Há preocupação transversal por réplica que deve acompanhar o ciclo do workload.

**Decisão requerida.** ADOTAR quando a capacidade deve acompanhar cada instância, precisa de proximidade/namespace compartilhado e não pertence à regra de negócio. Exigir orçamento de recursos, probes, ordem de startup/shutdown, compatibilidade de versões, telemetria separada e teste de falha do auxiliar. NÃO ADOTAR por conveniência de empacotamento apenas.

**Evidência mínima.** Relação de lifecycle, custo por réplica, recursos e interface local do sidecar.

**Bloqueio.** Não usar sidecar para serviço compartilhado ou dependência que precisa escalar independentemente.

**Fontes primárias/oficiais para consultar na entrega.**
- [Kubernetes - Sidecar Containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/) — documentacao-oficial-ou-projeto-primario
- [Azure Architecture Center - Sidecar Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/sidecar) — documentacao-oficial-ou-projeto-primario

## ARQ-P08 — Aggregator

**Gatilho.** Uma resposta do cliente exige dados de várias fontes e há benefício em coordenar no servidor.

**Decisão requerida.** ADOTAR quando uma jornada comprovadamente exige dados de várias fontes e a composição no cliente viola metas de round trips/complexidade. Exigir limite de fan-out, chamadas paralelas, timeout por dependência, política de parcialidade, cache quando seguro e teste de carga/degradação. NÃO ADOTAR para encadear lógica transacional distribuída.

**Evidência mínima.** Contratos de fontes, paralelismo limitado, timeout parcial, fallback e payload combinado.

**Bloqueio.** Bloquear agregador que amplie indiscriminadamente falhas ou cause N+1 remoto.

**Fontes primárias/oficiais para consultar na entrega.**
- [Azure - Gateway Aggregation Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/gateway-aggregation) — documentacao-oficial-ou-projeto-primario
- [AWS - API Composition](https://docs.aws.amazon.com/prescriptive-guidance/latest/modernization-data-persistence/api-composition.html) — documentacao-oficial-ou-projeto-primario
- [AWS - Scatter-Gather](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/scatter-gather.html) — documentacao-oficial-ou-projeto-primario

## ARQ-P09 — Bulkhead

**Gatilho.** Falha ou saturação de uma dependência pode derrubar fluxos independentes.

**Decisão requerida.** ADOTAR quando análise de falhas identifica recurso compartilhado capaz de derrubar fluxos/tenants independentes. Exigir unidade de isolamento, orçamento por compartimento, política de overflow, limites de fila, métrica de saturação e teste que prove continuidade fora do compartimento falho. REPROVAR se o teste revela dependência crítica comum sem proteção.

**Evidência mínima.** Pools/filas/limites separados, orçamento por dependência e comportamento degradado.

**Bloqueio.** Não aceitar isolamento nominal sem limite real de recurso.

**Fontes primárias/oficiais para consultar na entrega.**
- [Azure Architecture Center - Bulkhead Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/bulkhead) — documentacao-oficial-ou-projeto-primario
- [AWS Well-Architected - arquitetura baseada em células e consistent hashing](https://docs.aws.amazon.com/wellarchitected/latest/reducing-scope-of-impact-with-cell-based-architecture/consistent-hashing.html) — documentacao-oficial-ou-projeto-primario

## ARQ-P10 — Consistent Hashing

**Gatilho.** Chaves precisam ser distribuídas entre nós e a mudança de nós deve remapear só parte das chaves.

**Decisão requerida.** ADOTAR somente com necessidade mensurada de distribuir chaves e mudar membros com churn limitado. Exigir teste de uniformidade, hot keys, percentual remapeado, replicação/falha e compatibilidade do cliente. Se Redis Cluster, documentar os 16.384 slots, resharding e hash tags; não rotular o mecanismo como consistent hashing.

**Evidência mínima.** Função/hash ring, estratégia de virtual nodes, rebalanceamento e medição de distribuição.

**Bloqueio.** Não usar consistent hashing para problema sem particionamento ou sem medição de skew.

**Fontes primárias/oficiais para consultar na entrega.**
- [AWS Well-Architected - Consistent hashing](https://docs.aws.amazon.com/wellarchitected/latest/reducing-scope-of-impact-with-cell-based-architecture/consistent-hashing.html) — documentacao-oficial-ou-projeto-primario
- [Redis - escala e hash slots](https://redis.io/docs/latest/operate/oss_and_stack/management/scaling/) — fonte-de-apoio-a-confirmar-na-execucao
- [Redis - Cluster specification](https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/) — fonte-de-apoio-a-confirmar-na-execucao

## ARQ-P11 — Soft Delete

**Gatilho.** Registros precisam de retenção, recuperação ou trilha, mas também estão sujeitos a exclusão legal.

**Decisão requerida.** ADOTAR somente com caso explícito de recuperação/auditoria e base legal/prazo aprovados. Exigir escopo de dados, filtro central, autorização de restore, deleted_at, purge testado, propagação a derivados e evidência de atendimento a solicitações do titular. REPROVAR “soft delete permanente” como resposta única à LGPD/GDPR.

**Evidência mínima.** Campos de deleção, filtros padrão, prazo de retenção, purge/anonimização e base legal.

**Bloqueio.** Bloquear soft delete usado para ignorar direito de eliminação ou retenção indefinida.

**Fontes primárias/oficiais para consultar na entrega.**
- [Brasil - Lei 13.709/2018, LGPD, arts. 15-16](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/L13709compilado.htm) — norma-ou-organizacao-autoritativa
- [União Europeia - GDPR, arts. 5 e 17](https://eur-lex.europa.eu/eli/reg/2016/679/oj/eng) — norma-ou-organizacao-autoritativa
- [Microsoft Purview - retenção e exclusão permanente](https://learn.microsoft.com/en-us/purview/retention) — documentacao-oficial-ou-projeto-primario

## ARQ-P12 — Distributed Cache

**Gatilho.** Leituras repetidas justificam reduzir carga/latência com dados potencialmente defasados.

**Decisão requerida.** ADOTAR após perfil mostrar leitura repetida e benchmark demonstrar benefício no p50/p95/p99 e custo. Exigir hit ratio alvo, modelo de consistência, TTL/invalidação, proteção contra stampede, fallback com limite, teste de nó/cluster e versionamento de payload. REPROVAR estimativa de multiplicador sem medição do workload.

**Evidência mínima.** Chave, TTL/invalidação, consistência esperada, fallback e métricas hit/miss.

**Bloqueio.** Não usar cache sem dono de invalidação e sem limite de dados sensíveis.

**Fontes primárias/oficiais para consultar na entrega.**
- [Azure - Cache-Aside Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/cache-aside) — documentacao-oficial-ou-projeto-primario
- [AWS Builders’ Library - Caching challenges and strategies](https://aws.amazon.com/builders-library/caching-challenges-and-strategies/) — documentacao-oficial-ou-projeto-primario

## ARQ-P13 — Anti-Corruption Layer

**Gatilho.** Sistema externo/legado tem modelo, protocolo ou semântica incompatível com o domínio interno.

**Decisão requerida.** ADOTAR quando dois bounded contexts têm diferenças semânticas concretas e alterar um deles é inviável ou indesejado. Exigir tabela de mapeamento, testes de contrato em ambas as direções, tratamento de perdas/erros, ownership e critério de aposentadoria ou permanência. NÃO ADOTAR wrapper pass-through sem tradução real.

**Evidência mínima.** Mapeamento explícito, tradução de erros, teste de contrato e isolamento do modelo externo.

**Bloqueio.** Bloquear vazamento de modelo legado para o núcleo sem justificativa.

**Fontes primárias/oficiais para consultar na entrega.**
- [Azure - Anti-Corruption Layer Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/anti-corruption-layer) — documentacao-oficial-ou-projeto-primario
- [AWS - Anti-corruption layer](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/acl.html) — documentacao-oficial-ou-projeto-primario
- [Martin Fowler - Legacy Mimic e citação do padrão de Eric Evans](https://martinfowler.com/articles/patterns-legacy-displacement/legacy-mimic.html) — autor-ou-publicacao-primaria

# II. Segurança cibernética

## SEC-P01 — Zero Trust

**Gatilho.** Há recurso empresarial, dado sensível ou acesso remoto/interno sujeito a risco de confiança implícita.

**Decisão requerida.** A organização DEVE adotar princípios Zero Trust quando acessos cruzam limites de confiança, ambientes híbridos ou dados relevantes; DEVE começar por recursos e fluxos priorizados por risco, medir decisões e manter revogação; NÃO DEVE declarar “Zero Trust implementado” com base na compra de um produto ou em MFA isolado.

**Evidência mínima.** Decisão de política por acesso, identidade, contexto, dispositivo e enforcement próximo ao recurso.

**Bloqueio.** Bloquear autorização baseada apenas em localização de rede quando o risco exigir ZTA.

**Fontes primárias/oficiais para consultar na entrega.**
- [NIST SP 800-207](https://csrc.nist.gov/pubs/sp/800/207/final) — norma-ou-organizacao-autoritativa
- [NIST SP 1800-35 (final, 2025)](https://csrc.nist.gov/pubs/sp/1800/35/final) — norma-ou-organizacao-autoritativa
- [CISA Zero Trust Maturity Model v2.0](https://www.cisa.gov/zero-trust-maturity-model) — norma-ou-organizacao-autoritativa

## SEC-P02 — mTLS (TLS mútuo)

**Gatilho.** Há comunicação serviço-a-serviço, B2B ou dispositivo com identidade verificável em ambos os lados.

**Decisão requerida.** mTLS DEVE ser considerado para comunicação máquina-a-máquina de alto impacto ou entre domínios sem confiança implícita; a implantação DEVE validar nome/identidade, cadeia, finalidade e posse da chave, automatizar ciclo de vida e aplicar autorização após autenticar; NÃO DEVE tratar “handshake concluído” como autorização de negócio.

**Evidência mínima.** PKI, autenticação mútua, rotação/revogação, validação de cadeia e autorização separada.

**Bloqueio.** Bloquear mTLS alegado sem identidade de workload e ciclo de certificado.

**Fontes primárias/oficiais para consultar na entrega.**
- [RFC 8446 - TLS 1.3](https://www.rfc-editor.org/info/rfc8446/) — norma-ou-organizacao-autoritativa
- [RFC 9325 - uso seguro de TLS/DTLS](https://www.rfc-editor.org/info/rfc9325/) — norma-ou-organizacao-autoritativa
- [RFC 8705 - mTLS no OAuth 2.0](https://www.rfc-editor.org/info/rfc8705/) — norma-ou-organizacao-autoritativa

## SEC-P03 — WAF (Web Application Firewall)

**Gatilho.** Há aplicação HTTP/HTTPS exposta a tráfego não confiável.

**Decisão requerida.** Aplicações web expostas DEVERIAM usar WAF quando o risco e a superfície justificarem defesa adicional; regras DEVEM ser testadas, versionadas, monitoradas e associadas a correção na origem; o WAF NÃO DEVE ser aceito como substituto de validação de entrada, autorização, testes de segurança ou correção de vulnerabilidades.

**Evidência mínima.** Regra WAF, modo de bloqueio, logs, falsos positivos e controles corretivos no app.

**Bloqueio.** Bloquear conclusão de que WAF corrige vulnerabilidade de código ou autorização.

**Fontes primárias/oficiais para consultar na entrega.**
- [OWASP WSTG - Map Application Architecture/WAF](https://owasp.org/www-project-web-security-testing-guide/latest/4-Web_Application_Security_Testing/01-Information_Gathering/10-Map_Application_Architecture) — fonte-de-apoio-a-confirmar-na-execucao
- [OWASP Session Management Cheat Sheet - limites do WAF](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html) — fonte-de-apoio-a-confirmar-na-execucao
- [OWASP Top 10:2025](https://owasp.org/Top10/2025/) — fonte-de-apoio-a-confirmar-na-execucao

## SEC-P04 — Defense in Depth (defesa em profundidade)

**Gatilho.** O sistema processa ativos com impacto material e depende de controles múltiplos.

**Decisão requerida.** Sistemas com impacto relevante DEVEM mapear pelo menos prevenção, detecção, resposta e recuperação nos caminhos de ataque prioritários; cada camada DEVE ter objetivo, proprietário e teste; a arquitetura NÃO DEVE assumir que quantidade de controles ou diversidade de fornecedores garante independência ou contenção.

**Evidência mínima.** Camadas independentes de prevenção, detecção, resposta e recuperação, com donos e testes.

**Bloqueio.** Bloquear desenho que trate um único controle como proteção total.

**Fontes primárias/oficiais para consultar na entrega.**
- [NIST CSRC Glossary - defense-in-depth](https://csrc.nist.gov/glossary/term/defense_in_depth) — norma-ou-organizacao-autoritativa
- [NIST - Measuring and Improving Defense-in-Depth](https://www.nist.gov/publications/measuring-and-improving-effectiveness-defense-depth-postures) — norma-ou-organizacao-autoritativa
- [NIST NCCoE - risco mitigado, não eliminado](https://www.nccoe.nist.gov/manufacturing/responding-and-recovering-cyber-attack) — fonte-de-apoio-a-confirmar-na-execucao

## SEC-P05 — Secrets Management

**Gatilho.** Há segredo de aplicação, credencial, chave, token ou URI sensível.

**Decisão requerida.** Segredos não públicos DEVEM ter proprietário, escopo, validade, armazenamento protegido, trilha e revogação; segredos de workloads DEVERIAM ser dinâmicos ou de curta duração quando suportado; NÃO DEVEM ser embutidos em código, artefatos ou logs; rotação DEVE ser testada ponta a ponta e acionada por comprometimento, não tratada como ritual isolado.

**Evidência mínima.** Cofre, identidade de workload, menor privilégio, rotação, revogação e mascaramento em logs.

**Bloqueio.** Bloquear segredos em código, imagem, repositório ou variável estática não governada.

**Fontes primárias/oficiais para consultar na entrega.**
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html) — fonte-de-apoio-a-confirmar-na-execucao
- [NIST SP 800-57 Part 1 Rev. 5](https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final) — norma-ou-organizacao-autoritativa
- [NIST SP 800-53 Rev. 5 (inclui Release 5.2.0)](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final) — norma-ou-organizacao-autoritativa

## SEC-P06 — Tokenization e Data Masking

**Gatilho.** O fluxo recebe, processa ou persiste PII, PAN ou outro dado sensível que não é necessário em claro.

**Decisão requerida.** Dados sensíveis DEVEM ser minimizados antes de escolher técnica; tokenização DEVE ter domínio, vault/chaves e destokenização segregados; masking DEVE ser definido por finalidade e teste de utilidade/reidentificação; nenhum dos dois DEVE ser anunciado como anonimização, criptografia ou exclusão automática de escopo sem avaliação formal aplicável.

**Evidência mínima.** Classificação de dados, tokenização/masking, vault segregado e prova de minimização de persistência.

**Bloqueio.** Bloquear persistência em claro sem necessidade, base legal e controle compensatório.

**Fontes primárias/oficiais para consultar na entrega.**
- [PCI SSC - publicação das PCI DSS Tokenization Guidelines](https://www.pcisecuritystandards.org/about_us/press_releases/pci-security-standards-council-releases-pci-dss-tokenization-guidelines/) — norma-ou-organizacao-autoritativa
- [PCI SSC Document Library - padrões vigentes](https://www.pcisecuritystandards.org/document_library/) — norma-ou-organizacao-autoritativa
- [NIST SP 800-188 - De-Identifying Government Datasets](https://csrc.nist.gov/pubs/sp/800/188/final) — norma-ou-organizacao-autoritativa

## SEC-P07 — OAuth 2.0 e OpenID Connect (OIDC)

**Gatilho.** Há identidade de usuário final ou cliente OAuth/OIDC acessando recurso protegido.

**Decisão requerida.** Para novos clientes, DEVE-SE usar Authorization Code com PKCE e seguir o RFC 9700; fluxos implícito e Resource Owner Password Credentials NÃO DEVEM ser usados; APIs DEVEM validar token, emissor, audiência, escopo e autorização; autenticação DEVE usar OIDC ou protocolo próprio, nunca inferir identidade de um access token genérico.

**Evidência mínima.** Fluxo apropriado, PKCE quando aplicável, emissor/audiência/assinatura/expiração e scopes mínimos.

**Bloqueio.** Bloquear uso de token sem validação completa ou fluxo OAuth obsoleto/inseguro.

**Fontes primárias/oficiais para consultar na entrega.**
- [RFC 6749 - OAuth 2.0](https://www.rfc-editor.org/info/rfc6749/) — norma-ou-organizacao-autoritativa
- [RFC 9700 / BCP 240 - OAuth 2.0 Security BCP](https://www.rfc-editor.org/info/rfc9700/) — norma-ou-organizacao-autoritativa
- [OpenID Connect Core 1.0, errata set 2](https://openid.net/specs/openid-connect-core-1_0.html) — norma-ou-organizacao-autoritativa

## SEC-P08 — RBAC e ABAC

**Gatilho.** Uma decisão de acesso depende de papel, atributo, recurso, ação ou contexto.

**Decisão requerida.** Use RBAC quando permissões forem estáveis e alinhadas a funções; use ABAC quando a decisão depender materialmente de contexto ou atributos; modelos DEVEM negar por padrão, definir precedência, proteger fontes de atributo e recertificar acessos; a escolha NÃO DEVE ser feita pela promessa abstrata de “mais granular”.

**Evidência mínima.** Política versionada, atributos confiáveis, default deny, teste de decisão e registro de acesso.

**Bloqueio.** Bloquear autorização apenas no frontend ou baseada em atributo não verificado.

**Fontes primárias/oficiais para consultar na entrega.**
- [NIST RBAC Project](https://csrc.nist.gov/projects/role-based-access-control) — norma-ou-organizacao-autoritativa
- [NIST SP 800-162 - ABAC](https://csrc.nist.gov/pubs/sp/800/162/upd2/final) — norma-ou-organizacao-autoritativa
- [NIST SP 800-205 - atributos para controle de acesso](https://csrc.nist.gov/pubs/sp/800/205/final) — norma-ou-organizacao-autoritativa

## SEC-P09 — Microsegmentation

**Gatilho.** Workloads internos podem se comunicar em rede e a movimentação lateral é risco material.

**Decisão requerida.** Ambientes com workloads de sensibilidades distintas ou alto risco lateral DEVEM considerar microsegmentação; a política DEVE derivar de fluxos necessários, negar o restante, cobrir ingress/egress/administração e ser validada continuamente; a equipe NÃO DEVE equiparar criação de VLANs à contenção comprovada.

**Evidência mínima.** Política allow-list por fluxo, identidade/segmento, default deny e teste de conectividade proibida.

**Bloqueio.** Bloquear rede plana quando dependências não precisam de conectividade ampla.

**Fontes primárias/oficiais para consultar na entrega.**
- [NIST SP 1800-35 (final)](https://csrc.nist.gov/pubs/sp/1800/35/final) — norma-ou-organizacao-autoritativa
- [NIST ZTA Project Overview - políticas de microsegmentação](https://pages.nist.gov/zero-trust-architecture/VolumeA/ProjectOverview.html) — norma-ou-organizacao-autoritativa
- [NIST SP 800-215](https://csrc.nist.gov/pubs/sp/800/215/final) — norma-ou-organizacao-autoritativa

## SEC-P10 — Rate Limiting e Throttling

**Gatilho.** Há endpoint público, login, operação custosa ou risco de abuso/DoS.

**Decisão requerida.** Endpoints autenticados e anônimos DEVEM ter limites proporcionais ao risco e custo, preferencialmente por múltiplas dimensões; operações caras DEVEM ter quotas, limites de concorrência/payload e timeouts; 429 DEVERIA comunicar tratamento seguro; rate limiting NÃO DEVE ser apresentado como defesa DDoS completa.

**Evidência mínima.** Chave de limitação, algoritmo, limites, resposta 429/desafio, exceções e telemetria.

**Bloqueio.** Bloquear limite somente por IP quando NAT, identidade ou ataque distribuído invalidarem esse critério.

**Fontes primárias/oficiais para consultar na entrega.**
- [OWASP API Security 2023 - Unrestricted Resource Consumption](https://owasp.org/API-Security/editions/2023/en/0xa4-unrestricted-resource-consumption/) — fonte-de-apoio-a-confirmar-na-execucao
- [OWASP Denial of Service Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Denial_of_Service_Cheat_Sheet.html) — fonte-de-apoio-a-confirmar-na-execucao
- [RFC 6585 - HTTP 429](https://www.rfc-editor.org/info/rfc6585/) — norma-ou-organizacao-autoritativa

## SEC-P11 — Auditoria centralizada e SIEM

**Gatilho.** Há eventos de segurança, acesso, administração ou dados que precisam de detecção/investigação.

**Decisão requerida.** Sistemas relevantes DEVEM registrar eventos de segurança definidos por casos de uso, encaminhá-los a armazenamento central protegido, sincronizar tempo, restringir acesso e testar detecções; a priorização DEVE considerar criticidade da fonte; segredos NÃO DEVEM ser registrados; “logs no SIEM” NÃO DEVE ser aceito como prova de detecção ou resposta eficaz.

**Evidência mínima.** Esquema estruturado, correlação, retenção, acesso restrito, mascaramento e teste de entrega ao destino.

**Bloqueio.** Bloquear logs que incluam segredo/PII sem minimização ou que não sobrevivam ao workload.

**Fontes primárias/oficiais para consultar na entrega.**
- [CISA - Guidance for SIEM and SOAR Implementation (2025)](https://www.cisa.gov/resources-tools/resources/guidance-siem-and-soar-implementation) — norma-ou-organizacao-autoritativa
- [CISA - Best Practices for Event Logging and Threat Detection](https://www.cisa.gov/resources-tools/resources/best-practices-event-logging-and-threat-detection) — norma-ou-organizacao-autoritativa
- [NIST SP 800-92](https://csrc.nist.gov/pubs/sp/800/92/final) — norma-ou-organizacao-autoritativa

## SEC-P12 — JIT e PAM

**Gatilho.** Uma pessoa precisa de privilégio administrativo, especialmente em produção.

**Decisão requerida.** Acesso administrativo a ativos críticos DEVE usar identidade individual, MFA resistente ao risco, menor escopo e duração possível, aprovação proporcional e auditoria; JIT/JEA DEVERIAM substituir privilégios permanentes quando operacionalmente viável; break-glass DEVE ser testado e revisado; PAM/JIT NÃO DEVE ser descrito como eliminação de abuso privilegiado.

**Evidência mínima.** Solicitação contextual, aprovação, duração, menor privilégio, trilha e revogação automática.

**Bloqueio.** Bloquear privilégio elevado permanente quando uma elevação temporária é viável.

**Fontes primárias/oficiais para consultar na entrega.**
- [CISA/NSA - IAM Recommended Best Practices for Administrators](https://www.cisa.gov/sites/default/files/2023-12/ESF%20IDENTITY%20AND%20ACCESS%20MANAGEMENT%20RECOMMENDED%20BEST%20PRACTICES%20FOR%20ADMINISTRATORS%20PP-23-0248_508C.pdf) — norma-ou-organizacao-autoritativa
- [CISA - just-in-time e just-enough access](https://www.cisa.gov/news-events/cybersecurity-advisories/aa24-038a) — norma-ou-organizacao-autoritativa
- [NIST SP 800-53 Rev. 5 (inclui Release 5.2.0)](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final) — norma-ou-organizacao-autoritativa

# III. Arquitetura moderna

## ARC-G01 — Microservices

**Gatilho.** Capacidades de negócio precisam de implantação e escala independentes e a equipe suporta o custo distribuído.

**Decisão requerida.** ADOTAR somente se houver capacidade de negócio com cadência/escala/ownership independente e organização pronta para CI/CD, observabilidade, segurança e operação 24×7. Exigir prova de deploy e rollback independente, contrato versionado, propriedade de dados e SLO. NÃO ADOTAR se um monólito modular atende sem o prêmio da distribuição.

**Evidência mínima.** Fronteiras de serviço, ownership, contratos, observabilidade, dados e operação por serviço.

**Bloqueio.** Não decompor em microsserviços sem autonomia real e prontidão operacional.

**Fontes primárias/oficiais para consultar na entrega.**
- [Martin Fowler e James Lewis - Microservices](https://martinfowler.com/articles/microservices.html) — autor-ou-publicacao-primaria
- [Azure - Microservices architecture style](https://learn.microsoft.com/en-us/azure/architecture/guide/architecture-styles/microservices) — documentacao-oficial-ou-projeto-primario
- [Azure - Microservices Assessment and Readiness](https://learn.microsoft.com/en-us/azure/architecture/guide/technology-choices/microservices-assessment) — documentacao-oficial-ou-projeto-primario

## ARC-G02 — Containerization

**Gatilho.** O software precisa de ambiente reproduzível e empacotamento consistente.

**Decisão requerida.** ADOTAR quando a unidade empacotada reduz drift ou padroniza deploy. Exigir build determinístico, imagem mínima/não-root, SBOM/scan/assinatura, limites de recursos, externalização de estado e teste no runtime alvo. Avaliar Kubernetes separadamente, apenas se scheduling, autoscaling e operação de múltiplos workloads justificarem seu plano de controle.

**Evidência mínima.** Imagem declarativa, dependências fixadas, execução não privilegiada, scan e configuração externa.

**Bloqueio.** Bloquear imagem com segredo, tag mutável sem pin ou processo manual não reproduzível.

**Fontes primárias/oficiais para consultar na entrega.**
- [Kubernetes - Containers](https://kubernetes.io/docs/concepts/containers/) — documentacao-oficial-ou-projeto-primario
- [Kubernetes - documentação e definição de orquestrador](https://kubernetes.io/docs/home/) — documentacao-oficial-ou-projeto-primario
- [Docker - visão geral](https://docs.docker.com/get-started/docker-overview/) — documentacao-oficial-ou-projeto-primario

## ARC-G03 — Serverless

**Gatilho.** O workload é orientado a evento e o custo/escala gerenciada supera os limites de runtime e lock-in.

**Decisão requerida.** ADOTAR quando perfil de carga é variável/event-driven ou velocidade operacional supera necessidade de controle. Exigir teste de latência fria/quente, quotas/concurrency, modelo de custo em p50 e pico, retries/idempotência, limites do runtime, plano de observabilidade e estratégia de saída proporcional. NÃO ADOTAR apenas pelo rótulo moderno.

**Evidência mínima.** Gatilho, idempotência, timeout, concorrência, observabilidade e plano de saída.

**Bloqueio.** Não escolher serverless quando limites de execução/dados contradizem o fluxo.

**Fontes primárias/oficiais para consultar na entrega.**
- [AWS - What is Serverless Computing?](https://aws.amazon.com/what-is/serverless-computing/) — documentacao-oficial-ou-projeto-primario
- [AWS - Serverless](https://aws.amazon.com/serverless/) — documentacao-oficial-ou-projeto-primario
- [CNCF Security Whitepaper - FaaS](https://tag-security.cncf.io/community/resources/security-whitepaper/v2/cloud-native-security-whitepaper/) — fonte-de-apoio-a-confirmar-na-execucao

## ARC-G04 — Event-Driven Architecture

**Gatilho.** Produtores e consumidores devem desacoplar no tempo ou absorver picos.

**Decisão requerida.** ADOTAR quando produtores e consumidores precisam de desacoplamento temporal, fan-out ou absorção de picos. Exigir schema versionado, dono, event_id, chave de ordem, semântica de entrega, idempotência, retry/DLQ, tracing e replay testado. NÃO ADOTAR para fluxo simples que exige resposta síncrona imediata e transação única.

**Evidência mínima.** Contrato de evento, versionamento, idempotência, ordenação, retry/DLQ e observabilidade.

**Bloqueio.** Bloquear EDA sem dono do schema ou estratégia para evento duplicado/fora de ordem.

**Fontes primárias/oficiais para consultar na entrega.**
- [AWS Well-Architected - Event-driven architectures](https://docs.aws.amazon.com/wellarchitected/latest/serverless-applications-lens/event-driven-architectures.html) — documentacao-oficial-ou-projeto-primario
- [AWS Serverless - transitioning to EDA](https://docs.aws.amazon.com/serverless/latest/devguide/serverless-transition.html) — documentacao-oficial-ou-projeto-primario
- [AWS - Choreography](https://docs.aws.amazon.com/prescriptive-guidance/latest/modernization-integrating-microservices/choreography.html) — documentacao-oficial-ou-projeto-primario

## ARC-G05 — API Gateway + API-First

**Gatilho.** Uma API será consumida por mais de um cliente/equipe ou precisa ser governada antes do runtime.

**Decisão requerida.** ADOTAR API-first para contratos consumidos por outra equipe/organização: exigir spec revisada, compatibilidade, exemplos e conformance test no CI. ADOTAR gateway apenas com políticas/roteamento comuns mensuráveis: exigir HA e orçamento de latência. Registrar as duas decisões separadamente; REPROVAR “gateway instalado = API-first”.

**Evidência mínima.** Especificação versionada, compatibilidade, testes de contrato, políticas do gateway e documentação.

**Bloqueio.** Bloquear API-first declarada sem contrato verificável e compatibilidade de mudança.

**Fontes primárias/oficiais para consultar na entrega.**
- [OpenAPI Specification 3.2.0](https://spec.openapis.org/oas/v3.2.0.html) — norma-ou-organizacao-autoritativa
- [OpenAPI Initiative - Design-first best practices](https://learn.openapis.org/best-practices.html) — fonte-de-apoio-a-confirmar-na-execucao
- [Azure - API gateways](https://learn.microsoft.com/en-us/azure/architecture/microservices/design/gateway) — documentacao-oficial-ou-projeto-primario

## ARC-G06 — Service Mesh

**Gatilho.** Muitos serviços exigem políticas de tráfego, identidade e telemetria consistentes.

**Decisão requerida.** ADOTAR quando quantidade/heterogeneidade de serviços torna inviável implementar requisitos L7 uniformemente em bibliotecas/plataforma. Exigir matriz de capacidades, benchmark de latência/recursos, ownership do control plane, política de retries/timeouts única, rotação de identidade e teste de pane/degradação. NÃO ADOTAR sem equipe operadora e casos concretos.

**Evidência mínima.** Separação control/data plane, custo, mTLS, políticas, observabilidade e plano de incidentes.

**Bloqueio.** Não adicionar service mesh quando a complexidade exceder a necessidade observada.

**Fontes primárias/oficiais para consultar na entrega.**
- [CNCF Glossary - Service Mesh](https://glossary.cncf.io/service-mesh/) — documentacao-oficial-ou-projeto-primario
- [CNCF - definição original de service mesh](https://www.cncf.io/blog/2017/04/26/service-mesh-critical-component-cloud-native-stack/) — documentacao-oficial-ou-projeto-primario
- [Google Cloud Service Mesh - visão geral](https://cloud.google.com/products/service-mesh) — documentacao-oficial-ou-projeto-primario

## ARC-G07 — Modular Monolith

**Gatilho.** O produto ainda não justifica a complexidade distribuída, mas requer fronteiras internas fortes.

**Decisão requerida.** ADOTAR como padrão inicial quando autonomia de deploy/escala por capacidade não foi comprovada. Exigir mapa de módulos/bounded contexts, API interna, regras automatizadas de dependência, ownership e testes arquiteturais. Extrair serviço apenas quando métricas de cadência, escala, isolamento ou organização superarem o custo distribuído.

**Evidência mínima.** Módulos com dependências permitidas, testes de fronteira, ownership e caminho de extração.

**Bloqueio.** Bloquear monólito modular que permite acesso transversal irrestrito entre módulos.

**Fontes primárias/oficiais para consultar na entrega.**
- [Martin Fowler - Monolith First](https://martinfowler.com/bliki/MonolithFirst.html) — autor-ou-publicacao-primaria
- [Martin Fowler - Microservice Premium](https://martinfowler.com/bliki/MicroservicePremium.html) — autor-ou-publicacao-primaria
- [Microsoft .NET - arquiteturas web monolíticas](https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/common-web-application-architectures) — documentacao-oficial-ou-projeto-primario

## ARC-G08 — Sidecar

**Gatilho.** Um componente auxiliar precisa rodar 1:1 com o processo principal.

**Decisão requerida.** ADOTAR se a função precisa de localidade, escala 1:1 e lifecycle acoplado; comparar quantitativamente sidecar, daemon e serviço central. Exigir recursos, segurança, probes, version skew e failure test. NÃO ADOTAR se a função pode ser compartilhada com menor custo ou é lógica de domínio.

**Evidência mínima.** Lifecycle, limites de recurso, comunicação local, segurança e custo por réplica.

**Bloqueio.** Não duplicar sidecar quando um daemon ou serviço compartilhado atende melhor.

**Fontes primárias/oficiais para consultar na entrega.**
- [Kubernetes - Sidecar Containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/) — documentacao-oficial-ou-projeto-primario
- [Kubernetes - Pods com múltiplos containers](https://kubernetes.io/docs/concepts/workloads/pods/) — documentacao-oficial-ou-projeto-primario
- [Azure - Sidecar Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/sidecar) — documentacao-oficial-ou-projeto-primario

## ARC-G09 — Ambassador

**Gatilho.** Chamadas de saída para terceiros precisam de rede, credencial, retry ou telemetria padronizados.

**Decisão requerida.** ADOTAR quando clientes não suportam requisitos de conectividade ou quando padronização multilíngue supera o custo do proxy. Exigir contrato local, ownership, budget de latência, segurança de credenciais, coordenação de timeout/retry e teste de indisponibilidade. NÃO ADOTAR como wrapper pass-through sem capacidade transversal demonstrada.

**Evidência mínima.** Proxy/ambassador, autenticação, limites, retry idempotente, timeout e observabilidade.

**Bloqueio.** Bloquear retries cegos para operação não idempotente ou serviço externo indisponível.

**Fontes primárias/oficiais para consultar na entrega.**
- [Azure Architecture Center - Ambassador Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/ambassador) — documentacao-oficial-ou-projeto-primario
- [Azure - catálogo oficial de Cloud Design Patterns](https://learn.microsoft.com/en-us/azure/architecture/patterns/) — documentacao-oficial-ou-projeto-primario

## ARC-G10 — Database per Service

**Gatilho.** Serviços independentes precisam controlar evolução e disponibilidade de seus próprios dados.

**Decisão requerida.** ADOTAR somente para serviços com autonomia real de deploy e ownership de domínio. Exigir credencial que bloqueie acesso cruzado, migração independente, estratégia de transação/consulta cross-service, eventos versionados, reconciliação e backup/restore testados. NÃO declarar conformidade se equipes consultam tabelas umas das outras ou coordenam toda migração.

**Evidência mínima.** Owner do dado, API/evento de integração, consistência, migração e read model quando necessário.

**Bloqueio.** Bloquear acesso direto de um serviço ao banco de outro sem contrato explícito.

**Fontes primárias/oficiais para consultar na entrega.**
- [Chris Richardson - Database per Service](https://microservices.io/patterns/data/database-per-service.html) — fonte-de-apoio-a-confirmar-na-execucao
- [Martin Fowler e James Lewis - decentralized data management](https://martinfowler.com/articles/microservices.html) — autor-ou-publicacao-primaria
- [AWS - API Composition para consultas distribuídas](https://docs.aws.amazon.com/prescriptive-guidance/latest/modernization-data-persistence/api-composition.html) — documentacao-oficial-ou-projeto-primario

## ARC-G11 — Immutable Infrastructure

**Gatilho.** A infraestrutura é reproduzível por código e mudanças manuais prejudicam rastreabilidade.

**Decisão requerida.** ADOTAR quando instâncias podem ser substituídas e o pipeline atende ao tempo de correção. Exigir artefato endereçável/assinado, build reproduzível, estado externalizado, patch SLA, rollout/rollback testado e proibição auditada de mudança manual. EXCEÇÕES devem ser temporárias, registradas e reconciliadas por rebuild.

**Evidência mínima.** Definição versionada, artefato imutável, promoção, rollback e detecção de drift.

**Bloqueio.** Bloquear alteração manual em produção sem exceção aprovada e registro de reconciliação.

**Fontes primárias/oficiais para consultar na entrega.**
- [Kief Morris/Martin Fowler - Immutable Server](https://martinfowler.com/bliki/ImmutableServer.html) — autor-ou-publicacao-primaria
- [CNCF - Cloud Native Technology](https://glossary.cncf.io/cloud-native-tech/) — documentacao-oficial-ou-projeto-primario

## ARC-G12 — Resilience / Fault Tolerance

**Gatilho.** Uma dependência ou falha transitória pode degradar o serviço.

**Decisão requerida.** ADOTAR controles por fluxo crítico, não universalmente: exigir SLO/error budget, FMEA, RTO/RPO, timeout e retry budget únicos, idempotência, degradação, redundância sem ponto comum óbvio, runbook e teste regular com critérios pass/fail. REPROVAR alegação de tolerância sem experimento que injete a falha declarada.

**Evidência mínima.** Timeout, retry com backoff/jitter, circuit breaker, bulkhead, fallback e teste de falha.

**Bloqueio.** Bloquear retry sem timeout/orçamento ou ação de recuperação observável.

**Fontes primárias/oficiais para consultar na entrega.**
- [Azure Well-Architected - Reliability principles](https://learn.microsoft.com/en-us/azure/well-architected/reliability/principles) — documentacao-oficial-ou-projeto-primario
- [Azure - Reliability testing](https://learn.microsoft.com/en-us/azure/well-architected/reliability/reliability-test) — documentacao-oficial-ou-projeto-primario
- [AWS Builders’ Library - Timeouts, retries and backoff with jitter](https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/) — documentacao-oficial-ou-projeto-primario

## ARC-G13 — Portability / Hybrid Cloud / lock-in trade-offs

**Gatilho.** Há requisito de executar em mais de um ambiente/fornecedor ou risco de lock-in material.

**Decisão requerida.** ADOTAR portabilidade/híbrido somente com driver explícito - regulação, latência, continuidade, aquisição ou poder de negociação - e cenários priorizados. Exigir inventário de dependências proprietárias, RTO/custo de saída, formato/export de dados, teste periódico no segundo ambiente e TCO de skills/egress/operação. ACEITAR lock-in deliberado quando benefício e saída estão documentados.

**Evidência mínima.** Interfaces portáveis, inventário de serviços proprietários, custo de saída e decisão de trade-off.

**Bloqueio.** Não alegar portabilidade sem testar ou documentar dependências não portáveis.

**Fontes primárias/oficiais para consultar na entrega.**
- [CNCF Glossary - Portability](https://glossary.cncf.io/portability/) — documentacao-oficial-ou-projeto-primario
- [Google Cloud - trade-off entre benefícios de fornecedor único e lock-in](https://cloud.google.com/blog/topics/hybrid-cloud/a-cios-guide-to-the-cloud-hybrid-and-human-solutions-to-avoid-trade-offs) — documentacao-oficial-ou-projeto-primario
- [Google Cloud Architecture Center - Hybrid and multicloud patterns](https://cloud.google.com/architecture/hybrid-multicloud-patterns-and-practices) — documentacao-oficial-ou-projeto-primario

# IV. Engenharia de IA aplicada

## IA-G01 — Seleção e adequação do modelo

**Gatilho.** Um sistema de IA precisa selecionar modelo para um caso de uso e risco definidos.

**Decisão requerida.** Avance somente se um candidato alcançar limiares pré-registrados em um conjunto representativo, incluindo casos adversariais, e permanecer dentro dos tetos de custo e latência com margem. Registre modelo/versão/configuração e plano de rollback. Redimensione ou pare se a decisão depender apenas de leaderboard ou média sem análise por fatia.

**Evidência mínima.** Tarefas representativas, qualidade, custo, latência, privacidade, segurança e versão/model card.

**Bloqueio.** Bloquear seleção por benchmark genérico sem eval no caso de uso.

**Fontes primárias/oficiais para consultar na entrega.**
- [NIST AI 600-1 - MS-2.3 e avaliação em condições de implantação](https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.600-1.pdf) — norma-ou-organizacao-autoritativa
- [OpenAI API - Evaluation best practices](https://developers.openai.com/api/docs/guides/evaluation-best-practices) — documentacao-oficial-ou-projeto-primario
- [OpenAI API - Model selection](https://developers.openai.com/api/docs/guides/model-selection) — documentacao-oficial-ou-projeto-primario

## IA-G02 — Mixture of Experts (MoE)

**Gatilho.** A escolha/uso de um modelo MoE afeta custo, latência, roteamento ou capacidade.

**Decisão requerida.** Considere MoE apenas quando você treina/hospeda o modelo e a capacidade adicional supera, em teste de carga real, a complexidade de roteamento e comunicação. Em consumo de API, trate MoE como detalhe de implementação e selecione pelo resultado observado. Não avance com base em “trilhões de parâmetros” sem parâmetros ativos, throughput, qualidade e memória medidos.

**Evidência mínima.** Arquitetura/model card, limites de inferência, benchmark representativo e plano de fallback.

**Bloqueio.** Bloquear alegação de eficiência/qualidade de MoE sem evidência do modelo e do workload.

**Fontes primárias/oficiais para consultar na entrega.**
- [Switch Transformers - artigo original, JMLR](https://jmlr.org/papers/volume23/21-0998/21-0998.pdf) — autor-ou-publicacao-primaria
- [Google Research - GShard](https://research.google/pubs/gshard-scaling-giant-models-with-conditional-computation-and-automatic-sharding/) — documentacao-oficial-ou-projeto-primario

## IA-G03 — Engenharia sistemática de prompts

**Gatilho.** A saída do modelo depende de instruções, contexto e formato controlados.

**Decisão requerida.** Avance quando a versão do prompt superar o baseline com intervalo/volume suficiente, sem regressão nas fatias críticas e com testes de injeção. Pare se o comportamento essencial depender de segredo no prompt, de instrução ambígua ou de exposição de chain-of-thought; mova controles determinísticos para código/política.

**Evidência mínima.** Prompt versionado, entradas delimitadas, contrato de saída, testes adversariais e controles contra injeção.

**Bloqueio.** Bloquear prompt monolítico sem versionamento ou mistura de instrução confiável e dado não confiável.

**Fontes primárias/oficiais para consultar na entrega.**
- [OpenAI API - Prompt engineering](https://developers.openai.com/api/docs/guides/prompt-engineering) — documentacao-oficial-ou-projeto-primario
- [OpenAI API - Reasoning best practices](https://developers.openai.com/api/docs/guides/reasoning-best-practices) — documentacao-oficial-ou-projeto-primario
- [OWASP - LLM01:2025 Prompt Injection](https://genai.owasp.org/llmrisk/llm01-prompt-injection/) — fonte-de-apoio-a-confirmar-na-execucao

## IA-G04 — Retrieval-Augmented Generation (RAG)

**Gatilho.** O modelo precisa responder com conhecimento externo, privado ou mutável.

**Decisão requerida.** Use RAG quando respostas dependem de corpus mutável, privado ou citável e o ganho sobre o baseline é comprovado. Exija ACL antes da recuperação, proveniência por trecho, teste de suficiência/conflito, resposta “não sei” e métricas retrieval→generation. Não aprove alegação de eliminação de alucinação nem uso de RAG sem avaliação ponta a ponta.

**Evidência mínima.** Corpus autorizado, recuperação com citação/proveniência, avaliação de grounding e fallback para insuficiência.

**Bloqueio.** Bloquear RAG que não mede recuperação, contexto suficiente ou risco de resposta não ancorada.

**Fontes primárias/oficiais para consultar na entrega.**
- [Lewis et al. - Retrieval-Augmented Generation, artigo original](https://arxiv.org/abs/2005.11401) — autor-ou-publicacao-primaria
- [Google Research - sufficient context e alucinações em RAG](https://research.google/blog/deeper-insights-into-retrieval-augmented-generation-the-role-of-sufficient-context/) — documentacao-oficial-ou-projeto-primario
- [Google Research - RAG ainda pode alucinar](https://research.google/blog/making-llms-more-accurate-by-using-all-of-their-layers/) — documentacao-oficial-ou-projeto-primario

## IA-G05 — Chunking semântico

**Gatilho.** Documentos serão indexados para recuperação semântica.

**Decisão requerida.** Escolha a estratégia por experimento, comparando pelo menos baseline fixo/recursivo, estrutura/layout e semântico em consultas representativas; meça recall@k, MRR/nDCG, completude da evidência, qualidade final, tokens e custo. Aprove semantic chunking somente se estiver na fronteira qualidade-custo; reavalie por tipo documental.

**Evidência mínima.** Estratégia de chunk, metadados, sobreposição quando necessária, avaliação de recuperação e custo.

**Bloqueio.** Bloquear chunking por tamanho arbitrário sem teste de recuperação no corpus real.

**Fontes primárias/oficiais para consultar na entrega.**
- [Microsoft Learn - semantic chunking com Document Layout](https://learn.microsoft.com/en-us/azure/search/search-how-to-semantic-chunking) — documentacao-oficial-ou-projeto-primario
- [Zhou et al. 2026 - Beyond Chunk-Then-Embed](https://arxiv.org/abs/2602.16974) — autor-ou-publicacao-primaria
- [Microsoft Learn - chunking de documentos e alternativas](https://learn.microsoft.com/en-us/azure/search/vector-search-how-to-chunk-documents) — documentacao-oficial-ou-projeto-primario

## IA-G06 — Orquestração agêntica

**Gatilho.** O sistema usa agentes/múltiplas etapas para decidir ou agir.

**Decisão requerida.** Use agente apenas quando houver decisão condicional não coberta com segurança por workflow determinístico e ganho mensurado sobre ele. Defina máquina de estados, orçamento/timeout, máximo de passos, stop conditions, identidade, permissões e checkpoints. Escalone a humano ou encerre diante de baixa confiança, conflito, ação irreversível ou orçamento excedido.

**Evidência mínima.** Grafo de fluxo, limites de autonomia, estado, permissões por etapa, fallback e observabilidade de trace.

**Bloqueio.** Bloquear agente autônomo sem limites de ação, orçamento e condição de parada.

**Fontes primárias/oficiais para consultar na entrega.**
- [Microsoft Research - AutoGen, artigo/projeto](https://www.microsoft.com/en-us/research/publication/autogen-enabling-next-gen-llm-applications-via-multi-agent-conversation-framework/) — documentacao-oficial-ou-projeto-primario
- [Yao et al. - ReAct, artigo original](https://arxiv.org/abs/2210.03629) — autor-ou-publicacao-primaria
- [OWASP - Top 10 for Agentic Applications 2026](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/) — fonte-de-apoio-a-confirmar-na-execucao

## IA-G07 — Tool calling

**Gatilho.** O modelo pode chamar ferramenta, API, banco ou ação externa.

**Decisão requerida.** Aprove somente com allowlist mínima, credenciais próprias e least privilege, validação determinística, timeout/retry/idempotência e aprovação humana para efeitos altos. Separe “propor chamada” de “autorizar execução”. Bloqueie argumentos fora da política e nunca permita que texto do modelo contorne ACL ou confirmação.

**Evidência mínima.** Schema estrito, allow-list, validação no servidor, idempotência, autorização e recibo por chamada.

**Bloqueio.** Bloquear ferramenta com parâmetros livres para ação sensível ou sem autorização determinística.

**Fontes primárias/oficiais para consultar na entrega.**
- [OpenAI API - Function calling](https://developers.openai.com/api/docs/guides/function-calling) — documentacao-oficial-ou-projeto-primario
- [OpenAI API - Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs) — documentacao-oficial-ou-projeto-primario
- [OWASP - LLM06:2025 Excessive Agency](https://genai.owasp.org/llmrisk/llm062025-excessive-agency/) — fonte-de-apoio-a-confirmar-na-execucao

## IA-G08 — Modelos de raciocínio / Large Reasoning Models (LRMs)

**Gatilho.** A tarefa requer raciocínio intensivo e o modelo/caminho de raciocínio altera custo, latência ou segurança.

**Decisão requerida.** Roteie para LRM quando a avaliação por classe de tarefa mostrar ganho material que compense orçamento e SLA; mantenha modelo rápido para casos simples. Exija resultado verificável, testes/ferramentas e limite de tokens/tempo. Nunca condicione aprovação à exposição de CoT; peça resposta concisa, fontes, premissas e verificação reproduzível.

**Evidência mínima.** Modelo e versão, eval de tarefa, orçamento, latência, verificadores externos e política de não expor raciocínio privado.

**Bloqueio.** Bloquear promessa de raciocínio confiável sem verificação externa da resposta.

**Fontes primárias/oficiais para consultar na entrega.**
- [DeepSeek-R1 - artigo original](https://arxiv.org/abs/2501.12948) — autor-ou-publicacao-primaria
- [OpenAI API - Reasoning models](https://developers.openai.com/api/docs/guides/reasoning) — documentacao-oficial-ou-projeto-primario
- [OpenAI - Learning to reason with LLMs](https://openai.com/index/learning-to-reason-with-llms/) — documentacao-oficial-ou-projeto-primario

## IA-G09 — Small Language Models (SLMs) e edge

**Gatilho.** Há requisito de inferência local/edge, baixa latência, privacidade ou operação desconectada.

**Decisão requerida.** Aprove edge/SLM após medir acurácia por fatia, TTFT, tokens/s, p95, RAM/VRAM, energia, tamanho e operação offline no hardware-alvo. Documente fallback e fluxo de dados. Rejeite claims de latência zero ou segurança automática; aplique assinatura, sandbox, criptografia, atualização e threat model do dispositivo.

**Evidência mínima.** Modelo/quantização, hardware alvo, qualidade, consumo, atualização e privacidade de dados.

**Bloqueio.** Bloquear uso de SLM/edge sem medir qualidade e capacidade do dispositivo real.

**Fontes primárias/oficiais para consultar na entrega.**
- [Microsoft Research - Phi-3 Technical Report](https://www.microsoft.com/en-us/research/publication/phi-3-technical-report-a-highly-capable-language-model-locally-on-your-phone/) — documentacao-oficial-ou-projeto-primario
- [Meta AI - Llama 3.2 para edge e vision](https://ai.meta.com/blog/llama-3-2-connect-2024-vision-edge-mobile-devices/) — documentacao-oficial-ou-projeto-primario
- [Meta AI - modelos quantizados e trade-off de qualidade](https://ai.meta.com/blog/meta-llama-quantized-lightweight-models/) — documentacao-oficial-ou-projeto-primario

## IA-G10 — Vision-Language Models (VLMs)

**Gatilho.** O sistema recebe imagem, vídeo, tela ou documento visual.

**Decisão requerida.** Use VLM somente se a modalidade visual elevar desempenho versus OCR/visão especializada + regras, medido em corpus real por tipo, resolução e subgrupo. Exija grounding/citação de região quando possível, abstention e revisão humana em alto risco. Isole conteúdo visual não confiável e teste instruções ocultas, manipulações e imagens degradadas.

**Evidência mínima.** Modelo multimodal, dados autorizados, eval multimodal, tratamento de conteúdo sensível e limites de confiança.

**Bloqueio.** Bloquear decisão crítica por VLM sem validação humana ou determinística proporcional ao risco.

**Fontes primárias/oficiais para consultar na entrega.**
- [DeepMind - Flamingo, artigo original](https://arxiv.org/abs/2204.14198) — autor-ou-publicacao-primaria
- [DeepMind - visão geral oficial do Flamingo](https://deepmind.google/blog/tackling-multiple-tasks-with-a-single-visual-language-model/) — documentacao-oficial-ou-projeto-primario
- [NIST AI 600-1 - riscos multimodais e deepfakes](https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.600-1.pdf) — norma-ou-organizacao-autoritativa

## IA-G11 — Checkpoints e memória de longo prazo

**Gatilho.** O sistema persiste memória, contexto ou estado entre execuções/sessões.

**Decisão requerida.** Persista apenas campos com finalidade, base de autorização/consentimento, tenant e TTL definidos. Exija proveniência, classificação, validação de admissão, criptografia, ACL, edição/exclusão, auditoria e teste de poisoning. Checkpoints devem ser versionados e retomados de modo idempotente. Não grave segredos, CoT bruto ou toda conversa por padrão.

**Evidência mínima.** Schema, proveniência, TTL, revogação, isolamento por usuário/tenant e defesa contra envenenamento.

**Bloqueio.** Bloquear memória persistente sem política de retenção, exclusão e controle de acesso.

**Fontes primárias/oficiais para consultar na entrega.**
- [Packer et al. - MemGPT, artigo original](https://arxiv.org/abs/2310.08560) — autor-ou-publicacao-primaria
- [OWASP - Top 10 for Agentic Applications 2026](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/) — fonte-de-apoio-a-confirmar-na-execucao
- [NIST AI 600-1 - privacidade, proveniência e revogação](https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.600-1.pdf) — norma-ou-organizacao-autoritativa

## IA-G12 — Breakpoints human-in-the-loop (HITL)

**Gatilho.** Um agente pode executar ação financeira, destrutiva, externa, irreversível ou de alto impacto.

**Decisão requerida.** Pause obrigatoriamente antes de ação irreversível, privilegiada, financeira/legal, publicação externa, uso de dado sensível ou quando confiança/evidência cair abaixo do limiar. Mostre diff e efeito, não CoT. Defina SLA, substituto, dupla aprovação quando necessário e fail-closed; meça taxa de reversão, tempo e concordância, e revise breakpoints.

**Evidência mínima.** Ponto de aprovação humana, resumo da ação, identidade do aprovador, prazo, rollback e recibo.

**Bloqueio.** Bloquear execução autônoma sensível sem aprovação humana efetiva.

**Fontes primárias/oficiais para consultar na entrega.**
- [NIST AI 600-1 - human moderation e configuração humano-IA](https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.600-1.pdf) — norma-ou-organizacao-autoritativa
- [OWASP - LLM06:2025 Excessive Agency](https://genai.owasp.org/llmrisk/llm062025-excessive-agency/) — fonte-de-apoio-a-confirmar-na-execucao
- [Microsoft Research - Guidelines for Human-AI Interaction](https://www.microsoft.com/en-us/research/wp-content/uploads/2019/01/Guidelines-for-Human-AI-Interaction-camera-ready.pdf) — documentacao-oficial-ou-projeto-primario

## IA-G13 — Observabilidade, evals e LLM-as-judge

**Gatilho.** Uma aplicação de IA está em avaliação, produção ou mudança de prompt/modelo/dados.

**Decisão requerida.** Avance somente com taxonomia de eventos, SLOs, dataset versionado, owner e alertas acionáveis. Redija/minimize antes da coleta; aplique RBAC, retenção e amostragem. Calibre juiz em amostra humana representativa, monitore acordo por fatia e recalcibre após mudanças. Não use LLM-as-judge como única autoridade em alto risco; combine testes determinísticos, especialistas e auditoria.

**Evidência mínima.** Traces, evals versionados, conjunto representativo, métricas, avaliação humana quando necessária e privacidade de telemetria.

**Bloqueio.** Bloquear promoção de IA sem comparação contra baseline e critério de regressão.

**Fontes primárias/oficiais para consultar na entrega.**
- [OpenTelemetry - GenAI observability e conteúdo sensível opt-in](https://opentelemetry.io/blog/2026/genai-observability/) — documentacao-oficial-ou-projeto-primario
- [OpenAI API - Evaluation best practices e calibração humana](https://developers.openai.com/api/docs/guides/evaluation-best-practices) — documentacao-oficial-ou-projeto-primario
- [Zheng et al. - Judging LLM-as-a-Judge, artigo original](https://arxiv.org/abs/2306.05685) — autor-ou-publicacao-primaria
