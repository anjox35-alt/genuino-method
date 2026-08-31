"""Testes dos gates.

Regra: cada gate precisa de ao menos um caso que prova que ele REPROVA. Um gate
que so foi visto aprovando nao foi testado -- foi acompanhado.
"""

from __future__ import annotations

import textwrap
from pathlib import Path

import pytest

from genuino_mcp import gates, libapi

# --------------------------------------------------------------------------
# scan_secrets
# --------------------------------------------------------------------------


def test_scan_secrets_reprova_token_github(tmp_path: Path) -> None:
    (tmp_path / "config.py").write_text(
        # genuino:fixture: literal falso, existe para provar que o gate reprova
        'TOKEN = "ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"\n',
        encoding="utf-8",
    )
    result = gates.scan_secrets(tmp_path)
    assert result.status == gates.FAIL
    assert any(f.rule == "github-token" for f in result.findings)


def test_scan_secrets_reprova_caminho_pessoal_windows(tmp_path: Path) -> None:
    (tmp_path / "notas.md").write_text(
        # genuino:fixture: literal falso, existe para provar que o gate reprova
        "O projeto vive em C:\\Users\\fulano\\projetos\\app\n",
        encoding="utf-8",
    )
    result = gates.scan_secrets(tmp_path)
    assert result.status == gates.FAIL
    assert any(f.rule == "windows-user-path" for f in result.findings)


def test_scan_secrets_reprova_chave_privada(tmp_path: Path) -> None:
    (tmp_path / "id_rsa").write_text(
        # genuino:fixture: literal falso, existe para provar que o gate reprova
        "-----BEGIN RSA PRIVATE KEY-----\nMIIE...\n",
        encoding="utf-8",
    )
    result = gates.scan_secrets(tmp_path)
    assert result.status == gates.FAIL


def test_scan_secrets_aprova_arvore_limpa(tmp_path: Path) -> None:
    (tmp_path / "app.py").write_text("print('ola')\n", encoding="utf-8")
    result = gates.scan_secrets(tmp_path)
    assert result.status == gates.PASS
    # Aprovacao honesta declara o proprio limite.
    assert result.limits


def test_scan_secrets_nao_reprova_placeholder(tmp_path: Path) -> None:
    """Gate ruidoso e desligado pelo time. Placeholder nao pode reprovar."""
    (tmp_path / "README.md").write_text(
        'Use TOKEN="ghp_your-token-example-here-0123456789"\n',
        encoding="utf-8",
    )
    result = gates.scan_secrets(tmp_path)
    assert result.status == gates.PASS


def test_scan_secrets_respeita_allow_paths(tmp_path: Path) -> None:
    fixtures = tmp_path / "fixtures"
    fixtures.mkdir()
    (fixtures / "leak.txt").write_text(
        # genuino:fixture: literal falso, existe para provar que o gate reprova
        "AKIAIOSFODNN7SECRET1\n", encoding="utf-8"
    )
    assert gates.scan_secrets(tmp_path).status == gates.FAIL
    assert gates.scan_secrets(tmp_path, allow_paths=["fixtures/"]).status == gates.PASS


def test_scan_secrets_ignora_diretorio_gerado(tmp_path: Path) -> None:
    gerado = tmp_path / "node_modules" / "pkg"
    gerado.mkdir(parents=True)
    (gerado / "index.js").write_text(
        # genuino:fixture: literal falso, existe para provar que o gate reprova
        'const k = "ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789";\n',
        encoding="utf-8",
    )
    assert gates.scan_secrets(tmp_path).status == gates.PASS


def test_scan_secrets_isenta_linha_com_marcador_de_fixture(tmp_path: Path) -> None:
    (tmp_path / "test_algo.py").write_text(
        '# genuino:fixture: literal falso\n'
        'K = "ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"\n',
        encoding="utf-8",
    )
    assert gates.scan_secrets(tmp_path).status == gates.PASS


def test_marcador_isenta_so_a_linha_declarada(tmp_path: Path) -> None:
    """O marcador nao pode virar um interruptor geral do gate no arquivo.

    Se isentasse o arquivo inteiro, um segredo real colado abaixo de uma fixture
    passaria despercebido.
    """
    # Montada em tempo de execucao: escrita inteira no fonte, esta linha nao
    # marcada dispararia o gate na varredura do proprio repositorio. Concatenar
    # mantem o teste honesto sem plantar o padrao contiguo em disco.
    nao_marcada = "gh" + "p_" + "zZyYxXwWvVuUtTsSrRqQpPoOnNmM987654"
    (tmp_path / "test_algo.py").write_text(
        "# genuino:fixture: literal falso\n"
        'MARCADA = "ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"\n'
        "\n"
        f'NAO_MARCADA = "{nao_marcada}"\n',
        encoding="utf-8",
    )
    result = gates.scan_secrets(tmp_path)
    assert result.status == gates.FAIL
    assert len(result.findings) == 1
    assert result.findings[0].line == 4


# --------------------------------------------------------------------------
# check_bloat
# --------------------------------------------------------------------------


def test_check_bloat_reprova_arquivo_longo(tmp_path: Path) -> None:
    (tmp_path / "gigante.py").write_text("x = 1\n" * 50, encoding="utf-8")
    result = gates.check_bloat(
        tmp_path, gates.BloatThresholds(max_file_lines=10)
    )
    assert result.status == gates.FAIL
    assert any(f.rule == "arquivo-longo" for f in result.findings)


def test_check_bloat_reprova_funcao_longa(tmp_path: Path) -> None:
    corpo = "\n".join(f"    a{i} = {i}" for i in range(40))
    (tmp_path / "longa.py").write_text(
        f"def enorme():\n{corpo}\n", encoding="utf-8"
    )
    result = gates.check_bloat(
        tmp_path, gates.BloatThresholds(max_file_lines=9999, max_function_lines=10)
    )
    assert result.status == gates.FAIL
    assert any(f.rule == "funcao-longa" for f in result.findings)


def test_check_bloat_reprova_bloco_duplicado(tmp_path: Path) -> None:
    bloco = "\n".join(f"valor{i} = compute({i})" for i in range(12))
    for nome in ("a.py", "b.py", "c.py"):
        (tmp_path / nome).write_text(bloco + "\n", encoding="utf-8")
    result = gates.check_bloat(
        tmp_path,
        gates.BloatThresholds(
            max_file_lines=9999,
            max_function_lines=9999,
            max_duplicate_block_lines=12,
            min_duplicate_occurrences=3,
        ),
    )
    assert result.status == gates.FAIL
    assert any(f.rule == "bloco-duplicado" for f in result.findings)


def test_check_bloat_aprova_codigo_enxuto(tmp_path: Path) -> None:
    (tmp_path / "ok.py").write_text(
        "def soma(a, b):\n    return a + b\n", encoding="utf-8"
    )
    result = gates.check_bloat(tmp_path)
    assert result.status == gates.PASS


# --------------------------------------------------------------------------
# validate_skill
# --------------------------------------------------------------------------


def _skill(tmp_path: Path, content: str) -> Path:
    path = tmp_path / "SKILL.md"
    path.write_text(textwrap.dedent(content).lstrip(), encoding="utf-8")
    return path


def test_validate_skill_aprova_arquivo_correto(tmp_path: Path) -> None:
    path = _skill(
        tmp_path,
        """
        ---
        name: meu-gate
        description: Use when precisar verificar algo concreto.
        ---

        # Corpo da skill
        """,
    )
    assert gates.validate_skill(path).status == gates.PASS


def test_validate_skill_reprova_sem_frontmatter(tmp_path: Path) -> None:
    path = _skill(tmp_path, "# Sem frontmatter\n")
    result = gates.validate_skill(path)
    assert result.status == gates.FAIL
    assert result.findings[0].rule == "frontmatter-ausente"


def test_validate_skill_reprova_name_nao_kebab(tmp_path: Path) -> None:
    path = _skill(
        tmp_path,
        """
        ---
        name: MeuGate_Errado
        description: Use when algo.
        ---
        corpo
        """,
    )
    result = gates.validate_skill(path)
    assert result.status == gates.FAIL
    assert any(f.rule == "name-nao-kebab" for f in result.findings)


def test_validate_skill_reprova_campo_fora_da_allowlist(tmp_path: Path) -> None:
    path = _skill(
        tmp_path,
        """
        ---
        name: meu-gate
        description: Use when algo.
        autor: alguem
        ---
        corpo
        """,
    )
    result = gates.validate_skill(path)
    assert result.status == gates.FAIL
    assert any(f.rule == "campo-nao-permitido" for f in result.findings)


def test_validate_skill_reprova_todo_no_corpo(tmp_path: Path) -> None:
    path = _skill(
        tmp_path,
        """
        ---
        name: meu-gate
        description: Use when algo.
        ---
        TODO: escrever isso depois
        """,
    )
    result = gates.validate_skill(path)
    assert result.status == gates.FAIL
    assert any(f.rule == "todo-no-corpo" for f in result.findings)


def test_validate_skill_indeterminado_se_arquivo_ausente(tmp_path: Path) -> None:
    result = gates.validate_skill(tmp_path / "nao-existe.md")
    assert result.status == gates.INDETERMINADO


def test_validate_skill_aceita_bloco_escalar_yaml(tmp_path: Path) -> None:
    """Regressao: a skill canonica usa `description: >` com linhas indentadas.

    A primeira versao deste validador tratava cada linha de continuacao como
    campo malformado e reprovava um arquivo perfeitamente valido. Um gate que
    reprova conteudo bom acaba desligado, que e a pior falha possivel.
    """
    path = _skill(
        tmp_path,
        """
        ---
        name: genuino
        description: >
          Primeira linha da descricao longa, que continua
          por varias linhas indentadas ate o fim do bloco.
        ---

        # Corpo
        """,
    )
    result = gates.validate_skill(path)
    assert result.status == gates.PASS


def test_validate_skill_ainda_reprova_lixo_nao_indentado(tmp_path: Path) -> None:
    """A tolerancia ao bloco escalar nao pode virar tolerancia a lixo."""
    path = _skill(
        tmp_path,
        """
        ---
        name: meu-gate
        description: Use when algo.
        isto nao e um campo nem continuacao
        ---
        corpo
        """,
    )
    result = gates.validate_skill(path)
    assert result.status == gates.FAIL
    assert any(f.rule == "frontmatter-malformado" for f in result.findings)


# --------------------------------------------------------------------------
# scan_security
# --------------------------------------------------------------------------


def test_scan_security_nunca_devolve_pass_sem_ferramenta(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Ausencia de ferramenta nao e ausencia de vulnerabilidade."""
    monkeypatch.setattr(gates.shutil, "which", lambda _name: None)
    result = gates.scan_security(tmp_path)
    assert result.status == gates.INDETERMINADO
    assert result.status != gates.PASS


def test_scan_security_indeterminado_quando_ferramenta_erra(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Exit >= 2 do semgrep e erro da ferramenta, nao aprovacao do codigo."""
    import subprocess

    monkeypatch.setattr(gates.shutil, "which", lambda _name: "semgrep")

    def fake_run(*_args, **_kwargs):
        return subprocess.CompletedProcess(
            args=[], returncode=2, stdout="", stderr="config invalido"
        )

    monkeypatch.setattr(gates.subprocess, "run", fake_run)
    result = gates.scan_security(tmp_path)
    assert result.status == gates.INDETERMINADO


# --------------------------------------------------------------------------
# libapi
# --------------------------------------------------------------------------


def test_verify_python_symbol_confirma_api_v2_do_sdk() -> None:
    """O caso concreto que originou este servidor."""
    result = libapi.verify_python_symbol("mcp.server.MCPServer")
    assert result.status == gates.PASS


def test_verify_python_symbol_reprova_api_v1_legada() -> None:
    """`FastMCP` e a API v1. Um modelo gerando de memoria escreve este import."""
    result = libapi.verify_python_symbol("mcp.server.fastmcp.FastMCP")
    assert result.status == gates.FAIL


def test_verify_python_symbol_reprova_simbolo_inexistente() -> None:
    result = libapi.verify_python_symbol("pathlib.PathQueNaoExiste")
    assert result.status == gates.FAIL


def test_verify_python_symbol_indeterminado_sem_ponto() -> None:
    assert libapi.verify_python_symbol("pathlib").status == gates.INDETERMINADO


def test_verify_node_package_reprova_pacote_ausente(tmp_path: Path) -> None:
    (tmp_path / "package.json").write_text('{"name":"x"}', encoding="utf-8")
    result = libapi.verify_node_package(tmp_path, "inexistente")
    assert result.status == gates.FAIL


def test_verify_node_package_le_versao_resolvida(tmp_path: Path) -> None:
    pkg = tmp_path / "node_modules" / "alguma-lib"
    pkg.mkdir(parents=True)
    (pkg / "package.json").write_text(
        '{"name":"alguma-lib","version":"3.4.5"}', encoding="utf-8"
    )
    result = libapi.verify_node_package(tmp_path, "alguma-lib")
    assert result.status == gates.PASS
    assert "3.4.5" in result.summary


def test_context7_nunca_finge_ter_a_resposta() -> None:
    result = libapi.context7_guidance("react", "hooks")
    assert result.status == gates.INDETERMINADO
    assert "nao faz proxy" in " ".join(result.limits)


def test_check_bloat_respeita_skip_paths(tmp_path: Path) -> None:
    """Conteudo selado nao pode gerar achado sobre o qual ninguem pode agir."""
    selado = tmp_path / "method"
    selado.mkdir()
    (selado / "importado.py").write_text("x = 1\n" * 50, encoding="utf-8")
    th = gates.BloatThresholds(max_file_lines=10)
    assert gates.check_bloat(tmp_path, th).status == gates.FAIL
    assert gates.check_bloat(tmp_path, th, skip_paths=("method/",)).status == gates.PASS


def test_skip_paths_do_bloat_nao_afeta_scan_secrets(tmp_path: Path) -> None:
    """A isencao vale para estilo, jamais para credencial."""
    selado = tmp_path / "method"
    selado.mkdir()
    (selado / "vaza.py").write_text(
        # genuino:fixture: literal falso, existe para provar que o gate reprova
        'K = "ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"\n',
        encoding="utf-8",
    )
    assert gates.scan_secrets(tmp_path).status == gates.FAIL


def test_funcao_longa_nao_engole_o_codigo_abaixo(tmp_path: Path) -> None:
    """Regressao: a ultima funcao de um script engolia todo o top-level abaixo.

    Uma funcao de oito linhas era reportada com cento e oitenta. Gate que acusa
    o inocente perde a autoridade de acusar o culpado.
    """
    corpo_solto = "\n".join(f"Write-Output {i}" for i in range(200))
    (tmp_path / "script.ps1").write_text(
        "function Curta {\n    Write-Output 'ok'\n}\n\n" + corpo_solto + "\n",
        encoding="utf-8",
    )
    result = gates.check_bloat(
        tmp_path, gates.BloatThresholds(max_file_lines=9999, max_function_lines=20)
    )
    assert not any(f.rule == "funcao-longa" for f in result.findings)


def test_funcao_longa_ainda_e_detectada_com_chaves(tmp_path: Path) -> None:
    """A correcao nao pode virar cegueira: funcao grande de verdade reprova."""
    corpo = "\n".join(f"    Write-Output {i}" for i in range(60))
    (tmp_path / "grande.ps1").write_text(
        f"function Enorme {{\n{corpo}\n}}\n", encoding="utf-8"
    )
    result = gates.check_bloat(
        tmp_path, gates.BloatThresholds(max_file_lines=9999, max_function_lines=20)
    )
    assert any(f.rule == "funcao-longa" for f in result.findings)


def test_scan_respeita_gitignore_quando_ha_repositorio(tmp_path: Path) -> None:
    """Reprovar por arquivo ignorado ensina o time a ignorar o gate."""
    import subprocess

    subprocess.run(["git", "init", "-q", str(tmp_path)], check=False, capture_output=True)
    (tmp_path / ".gitignore").write_text("runs/\n", encoding="utf-8")
    ignorado = tmp_path / "runs"
    ignorado.mkdir()
    (ignorado / "log.txt").write_text(
        # genuino:fixture: literal falso, existe para provar que o gate reprova
        'K = "ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"\n',
        encoding="utf-8",
    )
    (tmp_path / "app.py").write_text("print('ok')\n", encoding="utf-8")
    assert gates.scan_secrets(tmp_path).status == gates.PASS


# --------------------------------------------------------------------------
# scan_security e selftest
# --------------------------------------------------------------------------


def test_scan_security_indeterminado_sem_regras_vendorizadas(tmp_path: Path) -> None:
    """Ausencia de regras nao e ausencia de vulnerabilidade."""
    result = gates.scan_security(tmp_path)
    assert result.status == gates.INDETERMINADO
    assert result.status != gates.PASS


def test_selftest_indeterminado_sem_diretorio(tmp_path: Path) -> None:
    result = gates.selftest_security(tmp_path)
    assert result.status == gates.INDETERMINADO


def test_selftest_exige_os_dois_arquivos_de_controle(tmp_path: Path) -> None:
    """Só o inseguro nao basta: sem o seguro nao da para medir falso positivo."""
    d = tmp_path / ".semgrep" / "selftest"
    d.mkdir(parents=True)
    (d / "insecure.ts").write_text("eval(userInput);\n", encoding="utf-8")
    result = gates.selftest_security(tmp_path)
    assert result.status == gates.INDETERMINADO
    assert "secure" in result.summary
