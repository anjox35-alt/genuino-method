#!/usr/bin/env python3
"""Validate a Genuíno operational-decision receipt without making a verdict."""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

BASE = Path(__file__).resolve().parent
CONTRACT = json.loads((BASE / "operational-contract-51.json").read_text(encoding="utf-8"))
SCHEMA = json.loads((BASE / "decision-receipt-schema.json").read_text(encoding="utf-8"))
VALID = set(CONTRACT["mandatory_statuses"])
EXPECTED_IDS = [rule["id"] for rule in CONTRACT["rules"]]
TYPE_LABELS = {
    "non_empty_string": "texto não-vazio",
    "non_empty_array": "array não-vazio",
    "non_empty_string_array": "array não-vazio de textos não-vazios",
    "rfc3339": "instante RFC 3339 com offset",
    "evidence_manifest_binding": "objeto exato {path, sha256}",
}
KNOWN_TYPES = frozenset(TYPE_LABELS)
RFC3339 = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"
    r"(?:\.[0-9]{1,6})?(?:Z|[+-][0-9]{2}:[0-9]{2})$"
)
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def parse_rfc3339_utc(value: object) -> datetime | None:
    if type(value) is not str or RFC3339.fullmatch(value) is None:
        return None
    try:
        normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    return parsed.astimezone(timezone.utc)


def schema_errors() -> list[str]:
    """Confere a coerência entre contrato e schema antes de qualquer leitura de recibo.

    Sem esta passagem, uma lacuna de configuração emerge como `KeyError` ou
    `ValueError` não capturado no meio da validação, indistinguível de um recibo
    inválido. Aqui ela vira `STOP` explícito com o defeito nomeado.
    """
    problems: list[str] = []
    types = SCHEMA.get("field_types", {})
    evidence = SCHEMA.get("evidence_by_status", {})
    required_top = SCHEMA.get("required_top_level", [])
    allowed_top = SCHEMA.get("allowed_top_level", [])
    required_decision = SCHEMA.get("rule_decision_fields", [])
    allowed_decision = SCHEMA.get("allowed_rule_decision_fields", [])

    for label, group in (
        ("required_top_level", required_top),
        ("allowed_top_level", allowed_top),
        ("rule_decision_fields", required_decision),
        ("allowed_rule_decision_fields", allowed_decision),
    ):
        if type(group) is not list or not group or any(type(item) is not str or not item for item in group):
            problems.append(f"{label} deve ser lista não-vazia de strings")
    if not set(required_top).issubset(allowed_top):
        problems.append("required_top_level precisa ser subconjunto de allowed_top_level")
    if not set(required_decision).issubset(allowed_decision):
        problems.append("rule_decision_fields precisa ser subconjunto de allowed_rule_decision_fields")
    if SCHEMA.get("schema_version") != "1.1.0":
        problems.append("schema_version do schema deve ser 1.1.0")

    for status in sorted(VALID):
        if status not in evidence:
            problems.append(f"status obrigatório sem evidence_by_status: {status}")
            continue
        group = evidence[status]
        if type(group) is not list or not group:
            # Grupo vazio não desabilita a exigência de forma visível: ele faz o laço de
            # evidência de validate() não executar, e o status passa sem justificativa.
            problems.append(
                f"status obrigatório com evidência vazia ou malformada: {status} -> {group!r}"
            )

    referenced = list(allowed_top)
    referenced += list(allowed_decision)
    for status, group in sorted(evidence.items()):
        if type(group) is not list:
            problems.append(f"evidence_by_status[{status}] deve ser lista: {group!r}")
            continue
        referenced += group
    for field in sorted(set(referenced)):
        if field not in types:
            problems.append(f"campo referenciado sem entrada em field_types: {field}")

    for field, label in sorted(types.items()):
        if label not in KNOWN_TYPES:
            problems.append(f"rótulo de tipo desconhecido em field_types[{field}]: {label}")

    if not EXPECTED_IDS:
        problems.append("contrato sem regras")
    return problems


def has_expected_type(value: object, expected: str) -> bool:
    if expected == "non_empty_string":
        return type(value) is str and bool(value.strip())
    if expected == "non_empty_array":
        return type(value) is list and bool(value)
    if expected == "non_empty_string_array":
        return (
            type(value) is list
            and bool(value)
            and all(type(item) is str and bool(item.strip()) for item in value)
        )
    if expected == "rfc3339":
        return parse_rfc3339_utc(value) is not None
    if expected == "evidence_manifest_binding":
        return (
            type(value) is dict
            and set(value) == {"path", "sha256"}
            and type(value.get("path")) is str
            and bool(value["path"].strip())
            and type(value.get("sha256")) is str
            and SHA256.fullmatch(value["sha256"]) is not None
        )
    raise ValueError(f"Tipo desconhecido no schema: {expected}")


def valid_field(container: dict, field: str) -> bool:
    return has_expected_type(container.get(field), SCHEMA["field_types"][field])


def validate(receipt: object, *, observed_at: datetime) -> list[str]:
    errors: list[str] = []
    if type(receipt) is not dict:
        return ["O recibo deve ser um objeto JSON."]

    allowed_top = set(SCHEMA["allowed_top_level"])
    unknown_top = sorted(set(receipt) - allowed_top)
    if unknown_top:
        errors.append("Campos de topo não permitidos: " + ", ".join(unknown_top))

    expected_version = SCHEMA["schema_version"]
    if receipt.get("schema_version") != expected_version:
        errors.append(f"schema_version deve ser exatamente {expected_version}")

    for field in SCHEMA["required_top_level"]:
        if not valid_field(receipt, field):
            expected = TYPE_LABELS[SCHEMA["field_types"][field]]
            errors.append(f"Campo obrigatório ausente ou inválido: {field} (esperado {expected})")
    for field in allowed_top - set(SCHEMA["required_top_level"]):
        if field in receipt and not valid_field(receipt, field):
            expected = TYPE_LABELS[SCHEMA["field_types"][field]]
            errors.append(f"Campo opcional inválido: {field} (esperado {expected})")

    decisions = receipt.get("rule_decisions")
    if type(decisions) is not list or not decisions:
        return errors

    valid_decisions: list[dict] = []
    for index, decision in enumerate(decisions):
        if type(decision) is not dict:
            errors.append(f"Decisão na posição {index} deve ser um objeto JSON.")
            continue
        unknown_fields = sorted(set(decision) - set(SCHEMA["allowed_rule_decision_fields"]))
        if unknown_fields:
            errors.append(
                f"Decisão na posição {index}: campos não permitidos: {', '.join(unknown_fields)}"
            )
        for field in SCHEMA["rule_decision_fields"]:
            if not valid_field(decision, field):
                expected = TYPE_LABELS[SCHEMA["field_types"][field]]
                errors.append(
                    f"Decisão na posição {index}: {field} ausente ou inválido "
                    f"(esperado {expected})"
                )
        for field in set(decision) & (
            set(SCHEMA["allowed_rule_decision_fields"]) - set(SCHEMA["rule_decision_fields"])
        ):
            if not valid_field(decision, field):
                expected = TYPE_LABELS[SCHEMA["field_types"][field]]
                errors.append(
                    f"Decisão na posição {index}: {field} inválido (esperado {expected})"
                )
        valid_decisions.append(decision)

    received_ids = [
        decision["rule_id"]
        for decision in valid_decisions
        if valid_field(decision, "rule_id")
    ]
    missing = [rule_id for rule_id in EXPECTED_IDS if rule_id not in received_ids]
    unknown = [rule_id for rule_id in received_ids if rule_id not in EXPECTED_IDS]
    duplicate = sorted({rule_id for rule_id in received_ids if received_ids.count(rule_id) > 1})
    if missing:
        errors.append("Regras sem decisão: " + ", ".join(missing))
    if unknown:
        errors.append("IDs desconhecidos: " + ", ".join(unknown))
    if duplicate:
        errors.append("IDs duplicados: " + ", ".join(duplicate))
    for decision in valid_decisions:
        rule_id = decision.get("rule_id", "<sem-id>")
        status = decision.get("status")
        if not valid_field(decision, "status"):
            continue
        if status not in VALID:
            errors.append(f"{rule_id}: status inválido: {status!r}")
            continue
        for field in SCHEMA["evidence_by_status"][status]:
            if not valid_field(decision, field):
                expected = TYPE_LABELS[SCHEMA["field_types"][field]]
                errors.append(f"{rule_id}: {status} exige {field} como {expected}")
        if status == "EXCECAO_AUTORIZADA" and valid_field(decision, "expires_at"):
            expiry = parse_rfc3339_utc(decision["expires_at"])
            if expiry is not None and expiry <= observed_at:
                errors.append(
                    f"{rule_id}: EXCECAO_AUTORIZADA expirou em {decision['expires_at']}"
                )
    return errors


def main() -> int:
    if len(sys.argv) != 4 or sys.argv[2] != "--observed-at":
        print("Uso: python validate_receipt.py caminho/recibo.json --observed-at RFC3339")
        return 2
    configuration = schema_errors()
    if configuration:
        print("STOP: configuração inválida do contrato ou do schema")
        for problem in configuration:
            print("- " + problem)
        return 2
    observed_at = parse_rfc3339_utc(sys.argv[3])
    if observed_at is None:
        print("STOP: --observed-at deve ser instante RFC 3339 com offset")
        return 2
    path = Path(sys.argv[1])
    try:
        receipt = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        print(f"STOP: não foi possível ler recibo: {error}")
        return 2
    errors = validate(receipt, observed_at=observed_at)
    if errors:
        print("STOP: recibo de decisão inválido")
        for error in errors:
            print("- " + error)
        return 1
    print("PASS: estrutura do recibo válida; isso não prova a verdade das evidências.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
