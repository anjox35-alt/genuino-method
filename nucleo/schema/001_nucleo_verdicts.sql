-- Vereditos publicos do genuino-method.
--
-- Aplicado no Supabase em 2026-08-31 como migration `nucleo_verdicts_inicial`.
-- Este arquivo e a copia versionada: um esquema que so existe dentro do painel
-- do provedor nao e auditavel por quem clona o repositorio.
--
-- Existe para fechar o limite 13 de docs/limites.md: `runs/` esta no
-- .gitignore, entao a evidencia que a R2 exige vive apenas na maquina que
-- rodou o loop. Quem clona tem a palavra do autor de que os gates passaram --
-- exatamente o que o metodo recusa aceitar em qualquer outro lugar.
--
-- O que entra aqui ja passou por `genuino_mcp.publish.build_public_verdict`,
-- que sanitiza caminhos e RECUSA quando nao consegue garantir a sanitizacao.
-- Esta tabela e o destino, nao o filtro.

create table if not exists public.nucleo_verdicts (
    id              uuid primary key default gen_random_uuid(),

    mission_id      text        not null,
    run_id          text        not null,
    verdict         text        not null,
    iterations      integer     not null,

    write_set       text[]      not null,
    oracle_paths    text[]      not null,

    -- Ancoram o veredito nos insumos: o motor e a missao que foram lidos.
    engine_sha256   text        not null,
    mission_sha256  text        not null,

    -- Ancora o registro no arquivo de origem, calculado ANTES da sanitizacao.
    -- E o elo que permite a quem tem o verdict.json provar que este registro
    -- veio dele.
    verdict_sha256  text        not null,

    repo_commit     text,
    notes           jsonb       not null default '[]'::jsonb,
    published_at    timestamptz not null default now(),

    -- Um mesmo run nao pode ser publicado duas vezes com conteudos diferentes.
    constraint nucleo_verdicts_run_unico unique (mission_id, run_id),

    -- As tres faixas do contrato de exit code, e nada alem delas.
    constraint nucleo_verdicts_faixa
        check (verdict in ('GREEN', 'RED', 'INDETERMINADO')),

    constraint nucleo_verdicts_iteracoes_nao_negativas
        check (iterations >= 0),

    -- Hash que nao tem forma de hash nao ancora nada.
    constraint nucleo_verdicts_engine_hex   check (engine_sha256   ~ '^[0-9a-f]{64}$'),
    constraint nucleo_verdicts_mission_hex  check (mission_sha256  ~ '^[0-9a-f]{64}$'),
    constraint nucleo_verdicts_verdict_hex  check (verdict_sha256  ~ '^[0-9a-f]{64}$')
);

comment on table public.nucleo_verdicts is
    'Vereditos publicos do green loop. Leitura anonima e deliberada: evidencia que so o autor consegue ler nao e evidencia.';

create index if not exists nucleo_verdicts_missao_data
    on public.nucleo_verdicts (mission_id, published_at desc);

alter table public.nucleo_verdicts enable row level security;

-- Leitura publica e o PROPOSITO desta tabela, nao um descuido de RLS.
-- O painel do NUCLEO le sem autenticar, e qualquer pessoa pode conferir os
-- hashes contra o repositorio publico.
drop policy if exists nucleo_verdicts_leitura_publica on public.nucleo_verdicts;
create policy nucleo_verdicts_leitura_publica
    on public.nucleo_verdicts
    for select
    to anon, authenticated
    using (true);

-- Nenhuma policy de insert, update ou delete. Sem elas, `anon` e
-- `authenticated` nao escrevem: com RLS ligada, o que nao tem policy e negado.
-- A escrita acontece pela service role, que ignora RLS e vive apenas na
-- maquina do autor.
