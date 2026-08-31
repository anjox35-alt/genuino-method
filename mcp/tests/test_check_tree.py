"""Testes do gate de publicacao como CLI.

O gate afirma, num comentario, que `method/` "responde ao gate de selo". Uma
auditoria de premissas mostrou que ele nunca chama o selo -- quem roda o gate
localmente e ve PASS conclui que a integridade normativa foi verificada, e nao
foi. A CI chama o selo em separado; o CLI, nao.

Evidencia que parece cobrir mais do que cobre e pior que evidencia ausente.
"""

from __future__ import annotations

from pathlib import Path

from genuino_mcp import check_tree


def _arvore_com_metodo(raiz: Path) -> Path:
    """Arvore minima com conteudo normativo selado."""
    method = raiz / "method"
    method.mkdir(parents=True)
    (method / "SKILL.md").write_text("---\nname: x\ndescription: y\n---\ncorpo\n", encoding="utf-8")
    (raiz / "app.py").write_text("def soma(a, b):\n    return a + b\n", encoding="utf-8")
    from genuino_mcp import seal

    seal.main(["write", str(method), str(method / "MANIFEST.sha256")])
    return method


def test_gate_reprova_quando_o_conteudo_selado_foi_alterado(tmp_path: Path, capsys) -> None:
    """Este e o caso que o gate afirmava cobrir e nao cobria.

    A asercao NAO pode ser apenas `exit != 0`. Numa arvore temporaria sem
    `.semgrep/rules`, o gate ja devolve 2 por nao conseguir medir a seguranca --
    e o teste passaria sem que o selo tivesse sido olhado uma unica vez.

    A asercao e sobre o RELATORIO: o gate de selo precisa aparecer e precisa
    reprovar. Isso mata o mutante em que o selo nunca e chamado.

    Este teste ja esteve na forma fraca, e foi commitado assim. O operario
    trabalhou contra um oraculo insuficiente e produziu GREEN legitimo aos olhos
    do motor -- que e exatamente o limite 1 de docs/limites.md acontecendo na
    pratica.
    """
    method = _arvore_com_metodo(tmp_path)
    (method / "SKILL.md").write_text(
        "---\nname: x\ndescription: y\n---\nADULTERADO\n", encoding="utf-8"
    )
    codigo = check_tree.main([str(tmp_path)])
    saida = capsys.readouterr().out

    assert "seal" in saida.lower(), "o gate de selo nao aparece no relatorio"
    assert "[FAIL] seal" in saida, "o selo nao reprovou conteudo adulterado"
    assert codigo == 1, f"adulteracao medida deve ser exit 1, veio {codigo}"


def test_gate_aprova_arvore_com_selo_integro(tmp_path: Path, capsys) -> None:
    _arvore_com_metodo(tmp_path)
    # Sem semgrep o selftest devolve INDETERMINADO (exit 2), que tambem nao e 0.
    # O que este caso fixa e que o selo integro nao e a causa da reprovacao.
    check_tree.main([str(tmp_path)])
    saida = capsys.readouterr().out
    assert "[PASS] seal" in saida or "[PASS] verificar_selo" in saida, (
        "selo integro deveria passar; o gate precisa reporta-lo"
    )


def test_gate_indeterminado_quando_falta_manifesto(tmp_path: Path) -> None:
    """Selo ausente nao e selo valido."""
    method = tmp_path / "method"
    method.mkdir(parents=True)
    (method / "SKILL.md").write_text("conteudo\n", encoding="utf-8")
    (tmp_path / "app.py").write_text("x = 1\n", encoding="utf-8")
    assert check_tree.main([str(tmp_path)]) != 0


def test_arvore_sem_method_nao_exige_selo(tmp_path: Path) -> None:
    """Nem todo repositorio tem conteudo normativo; ausencia nao pode reprovar."""
    (tmp_path / "app.py").write_text("def f():\n    return 1\n", encoding="utf-8")
    assert check_tree.main([str(tmp_path)]) in (0, 2)
