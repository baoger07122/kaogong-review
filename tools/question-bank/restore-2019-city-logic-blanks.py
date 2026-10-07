#!/usr/bin/env python3
"""Restore manually verified logic-blank markers in a question-bank JSON export.

The source PDF's text layer omits the drawn answer lines. This tool therefore
uses an explicit, reviewed anchor manifest; it never guesses blank locations
from punctuation. It also validates that every question in the declared logic
blank range has the expected number of markers and validates sentence
insertion questions in a separate manifest section.

Requires pdfplumber for checking the source PDF text layer.
"""

from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
import os
import re
import sys
import tempfile
import unicodedata
from pathlib import Path
from typing import Any

PLACEHOLDER = "______"


def fail(message: str) -> None:
    raise ValueError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def compact(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value)
    return re.sub(r"\s+", "", normalized)


def find_gap(text: str, after: str, before: str, question_number: int, slot_number: int) -> tuple[int, int]:
    """Find one unambiguous whitespace/placeholder gap between the two anchors."""
    after_positions = [m.start() for m in re.finditer(re.escape(after), text)]
    before_positions = [m.start() for m in re.finditer(re.escape(before), text)]
    candidates: list[tuple[int, int]] = []
    for after_start in after_positions:
        start = after_start + len(after)
        for before_start in before_positions:
            if before_start < start:
                continue
            gap = text[start:before_start]
            if not gap.strip() or gap == PLACEHOLDER:
                candidates.append((start, before_start))
    if len(candidates) != 1:
        fail(
            f"Q{question_number} slot {slot_number}: expected one whitespace or "
            f"{PLACEHOLDER!r} gap between anchors, found {len(candidates)}"
        )
    return candidates[0]


def validate_source_slot(page_text: str, after: str, before: str, question_number: int, slot_number: int) -> None:
    source = compact(page_text)
    pattern = compact(after) + compact(before)
    count = source.count(pattern)
    if count != 1:
        fail(
            f"Q{question_number} slot {slot_number}: source PDF page does not contain "
            f"the unique adjacent anchor sequence (found {count})"
        )


def validate_source_sentence_marker(
    page_text: str, after: str, before: str, question_number: int
) -> None:
    source = compact(page_text)
    after_positions = [m.start() for m in re.finditer(re.escape(compact(after)), source)]
    before_positions = [m.start() for m in re.finditer(re.escape(compact(before)), source)]
    if len(after_positions) != 1 or len(before_positions) != 1:
        fail(f"Sentence-insertion Q{question_number}: PDF source anchors are not unique")
    start = after_positions[0] + len(compact(after))
    end = before_positions[0]
    if end < start or placeholder_runs(source[start:end]) != [PLACEHOLDER]:
        fail(f"Sentence-insertion Q{question_number}: source PDF must contain one six-underscore marker")


def placeholder_runs(stem: str) -> list[str]:
    return re.findall(r"_{3,}", stem)


def question_map(payload: dict[str, Any]) -> dict[int, dict[str, Any]]:
    result: dict[int, dict[str, Any]] = {}
    for question in payload.get("questions", []):
        number = question.get("number")
        if not isinstance(number, int) or number in result:
            fail(f"Question number is missing or duplicated: {number!r}")
        result[number] = question
    return result


def validate_full_package(payload: dict[str, Any], manifest: dict[str, Any]) -> None:
    if payload.get("format") != "kaogong-question-bank" or payload.get("schemaVersion") != 1:
        fail("Unsupported question-bank JSON format or schemaVersion")
    paper = payload.get("paper")
    if not isinstance(paper, dict) or not paper.get("id") or not paper.get("title"):
        fail("Paper identity or title is missing")

    modules = payload.get("modules")
    materials = payload.get("materials")
    questions = payload.get("questions")
    assets = payload.get("assets")
    if not all(isinstance(value, list) for value in (modules, materials, questions, assets)):
        fail("modules, materials, questions, and assets must be arrays")
    expected_counts = {
        "modules": manifest["expectedModuleCount"],
        "materials": manifest["expectedMaterialCount"],
        "questions": manifest["expectedQuestionCount"],
        "assets": manifest["expectedAssetCount"],
    }
    for field, expected in expected_counts.items():
        if len(payload[field]) != expected:
            fail(f"Expected {expected} {field}, found {len(payload[field])}")
    if {question.get("number") for question in questions} != set(range(1, manifest["expectedQuestionCount"] + 1)):
        fail("Question numbers must cover the complete expected range without gaps")

    module_ids = {module.get("id") for module in modules}
    material_by_id = {material.get("id"): material for material in materials}
    question_by_id = {question.get("id"): question for question in questions}
    asset_by_id = {asset.get("id"): asset for asset in assets}
    for field, values in (("module", modules), ("material", materials), ("question", questions), ("asset", assets)):
        ids = [value.get("id") for value in values]
        if any(not isinstance(value, str) or not value for value in ids) or len(set(ids)) != len(ids):
            fail(f"{field} stable IDs are missing or duplicated")
    all_entity_ids = [paper["id"]] + [value["id"] for value in modules + materials + questions + assets]
    if len(set(all_entity_ids)) != len(all_entity_ids):
        fail("Stable IDs must be unique across the paper, modules, materials, questions, and assets")

    asset_references: dict[str, tuple[str, str, str]] = {}

    def reference_asset(asset_id: str, owner_type: str, owner_id: str, role: str, label: str) -> None:
        if asset_id:
            if asset_id in asset_references:
                fail(f"{label}: asset {asset_id} is referenced more than once")
            asset_references[asset_id] = (owner_type, owner_id, role)

    for module in modules:
        if module.get("paperID") != paper["id"] or not module.get("title"):
            fail(f"Module {module.get('id')} has a missing title or mismatched paperID")
    for material in materials:
        if material.get("paperID") != paper["id"] or material.get("moduleID") not in module_ids:
            fail(f"Material {material.get('id')} has a mismatched paper or module link")
        asset_id = material.get("imageAssetID", "")
        reference_asset(asset_id, "material", material["id"], "共用材料", f"Material {material['id']}")
    for question in questions:
        number = question.get("number")
        label = f"Q{number}"
        if question.get("paperID") != paper["id"] or question.get("moduleID") not in module_ids:
            fail(f"{label}: mismatched paper or module link")
        material_id = question.get("materialID", "")
        if material_id and (material_id not in material_by_id
                            or material_by_id[material_id].get("moduleID") != question.get("moduleID")):
            fail(f"{label}: material link is missing or crosses modules")
        if question.get("answer") not in {"A", "B", "C", "D"}:
            fail(f"{label}: answer is outside A-D")
        if not isinstance(question.get("stem"), str):
            fail(f"{label}: stem must be a string")
        options = question.get("options")
        if not isinstance(options, list) or any(not isinstance(option, dict) for option in options):
            fail(f"{label}: options must be an array of objects")
        if [option.get("id") for option in options] != ["A", "B", "C", "D"]:
            fail(f"{label}: expected options A-D in order")
        if not question["stem"].strip() and not question.get("stemImageAssetID"):
            fail(f"{label}: both stem and stem image are empty")
        stem_asset = question.get("stemImageAssetID", "")
        reference_asset(stem_asset, "question", question["id"], "题干整图", f"{label} stem")
        for option in options:
            if not option.get("text") and not option.get("imageAssetID"):
                fail(f"{label} option {option.get('id')}: text and image are both empty")
            asset_id = option.get("imageAssetID", "")
            reference_asset(asset_id, "option", question["id"], f"选项{option['id']}", f"{label} option {option['id']}")

    asset_paths: set[str] = set()
    for asset in assets:
        asset_id = asset["id"]
        path = asset.get("path", "")
        parts = path.split("/")
        if len(parts) != 2 or parts[0] != "assets" or parts[1] in {"", ".", ".."}:
            fail(f"Asset {asset_id}: unsafe or unsupported relative path {path!r}")
        if path in asset_paths:
            fail(f"Asset {asset_id}: duplicate image path {path!r}")
        asset_paths.add(path)
        expected_owner = asset_references.get(asset_id)
        if expected_owner is None:
            fail(f"Asset {asset_id}: unreferenced image asset")
        owner_type, owner_id, role = expected_owner
        compatible_owner_types = {owner_type}
        if owner_type == "option":
            compatible_owner_types.add("question")
        if asset.get("ownerType") not in compatible_owner_types or asset.get("ownerID") != owner_id or asset.get("role") != role:
            fail(f"Asset {asset_id}: owner or role does not match its referenced field")
        if asset.get("paperID") != paper["id"] or not asset.get("fileName"):
            fail(f"Asset {asset_id}: missing fileName or mismatched paperID")
        try:
            image_data = base64.b64decode(asset["dataBase64"], validate=True)
        except (KeyError, ValueError) as exc:
            fail(f"Asset {asset_id}: invalid base64 image data ({exc})")
        digest = hashlib.sha256(image_data).hexdigest()
        if digest.lower() != str(asset.get("sha256", "")).lower():
            fail(f"Asset {asset_id}: embedded image hash does not match sha256")
        mime = asset.get("mimeType")
        valid_png = image_data.startswith(b"\x89PNG\r\n\x1a\n") and mime == "image/png"
        valid_jpeg = image_data.startswith(b"\xff\xd8\xff") and mime in {"image/jpeg", "image/jpg"}
        if not (valid_png or valid_jpeg):
            fail(f"Asset {asset_id}: image bytes do not match mimeType")


def verify_unchanged_except_stems(original: dict[str, Any], updated: dict[str, Any], changed_ids: set[str]) -> None:
    if original.keys() != updated.keys():
        fail("Top-level JSON keys changed")
    for key in original:
        if key != "questions" and original[key] != updated[key]:
            fail(f"Non-question payload changed: {key}")

    old_questions = {q["id"]: q for q in original["questions"]}
    new_questions = {q["id"]: q for q in updated["questions"]}
    if old_questions.keys() != new_questions.keys():
        fail("Question stable IDs changed")
    for stable_id, old in old_questions.items():
        new = new_questions[stable_id]
        if stable_id in changed_ids:
            old_without_stem = {k: v for k, v in old.items() if k != "stem"}
            new_without_stem = {k: v for k, v in new.items() if k != "stem"}
            if old_without_stem != new_without_stem:
                fail(f"Question fields other than stem changed: {stable_id}")
        elif old != new:
            fail(f"Unexpected question change: {stable_id}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, default=Path(__file__).with_name("2019-city-logic-blank-audit.json"))
    parser.add_argument("--verify-only", action="store_true", help="Validate an already corrected output without writing it")
    args = parser.parse_args()

    try:
        import pdfplumber
    except ImportError as exc:
        fail(f"pdfplumber is required: {exc}")

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    if sha256(args.pdf) != manifest["sourcePdfSha256"].upper():
        fail("Source PDF hash does not match the manually reviewed source in the manifest")

    original = json.loads(args.input.read_text(encoding="utf-8"))
    validate_full_package(original, manifest)
    updated = copy.deepcopy(original)
    questions = question_map(updated)
    source_range = manifest["logicBlankRange"]
    expected_range = set(range(source_range[0], source_range[1] + 1))
    logic_entries = {entry["number"]: entry for entry in manifest["logicBlankQuestions"]}
    if set(logic_entries) != expected_range:
        fail("Every number in logicBlankRange must have an explicit visual audit entry")
    if len(questions) != manifest["expectedQuestionCount"]:
        fail(f"Expected {manifest['expectedQuestionCount']} questions, found {len(questions)}")

    pages: dict[int, str] = {}
    with pdfplumber.open(args.pdf) as pdf:
        for number in expected_range | {entry["number"] for entry in manifest["sentenceInsertionQuestions"]}:
            entry = logic_entries.get(number)
            if entry is None:
                entry = next(e for e in manifest["sentenceInsertionQuestions"] if e["number"] == number)
            page_number = entry["pdfPage"]
            if page_number < 1 or page_number > len(pdf.pages):
                fail(f"Q{number}: PDF page {page_number} is outside the source")
            if page_number not in pages:
                pages[page_number] = pdf.pages[page_number - 1].extract_text() or ""

    changed_ids: set[str] = set()
    for number in sorted(expected_range):
        entry = logic_entries[number]
        question = questions.get(number)
        if question is None:
            fail(f"Q{number}: absent from question JSON")
        if str(question.get("originalPage")) != str(entry["pdfPage"]):
            fail(f"Q{number}: JSON originalPage does not match audited PDF page")
        stem = question.get("stem")
        if not isinstance(stem, str):
            fail(f"Q{number}: stem is missing")
        if entry.get("visualAudit") != "manually-verified-rendered-page":
            fail(f"Q{number}: rendered-page visual audit is not recorded")

        slots = entry["slots"]
        if not slots or entry.get("visualBlankCount") != len(slots):
            fail(f"Q{number}: visual blank count must match the explicit slot list")
        for index, slot in enumerate(slots, start=1):
            after, before = slot["after"], slot["before"]
            validate_source_slot(pages[entry["pdfPage"]], after, before, number, index)
            start, end = find_gap(stem, after, before, number, index)
            gap = stem[start:end]
            if gap != PLACEHOLDER and not gap.isspace() and gap:
                fail(f"Q{number} slot {index}: refusing to replace non-whitespace text {gap!r}")
            if not args.verify_only and gap != PLACEHOLDER:
                stem = stem[:start] + PLACEHOLDER + stem[end:]
        if not args.verify_only:
            question["stem"] = stem
        runs = placeholder_runs(question["stem"])
        if runs != [PLACEHOLDER] * entry["visualBlankCount"]:
            fail(f"Q{number}: expected {entry['visualBlankCount']} six-underscore markers, found {runs}")
        changed_ids.add(question["id"])

    sentence_entries = manifest["sentenceInsertionQuestions"]
    for entry in sentence_entries:
        number = entry["number"]
        question = questions.get(number)
        if question is None:
            fail(f"Sentence-insertion Q{number}: absent from question JSON")
        if str(question.get("originalPage")) != str(entry["pdfPage"]):
            fail(f"Sentence-insertion Q{number}: JSON originalPage does not match audited PDF page")
        if entry.get("visualAudit") != "manually-verified-rendered-page":
            fail(f"Sentence-insertion Q{number}: rendered-page audit is not recorded")
        validate_source_sentence_marker(
            pages[entry["pdfPage"]], entry["pdfAfter"], entry["pdfBefore"], number
        )
        sentence_start, sentence_end = find_gap(
            question.get("stem", ""), entry["after"], entry["before"], number, 1
        )
        if question["stem"][sentence_start:sentence_end] != PLACEHOLDER:
            fail(f"Sentence-insertion Q{number}: JSON placeholder is not between its audited anchors")
        runs = placeholder_runs(question.get("stem", ""))
        if runs != [PLACEHOLDER] * entry["expectedPlaceholders"]:
            fail(
                f"Sentence-insertion Q{number}: expected {entry['expectedPlaceholders']} "
                f"marker(s), found {runs}"
            )
        if number in expected_range:
            fail(f"Q{number}: sentence insertion cannot also be classified as a logic blank")

    verify_unchanged_except_stems(original, updated, changed_ids)
    validate_full_package(updated, manifest)
    if len({q["id"] for q in updated["questions"]}) != len(updated["questions"]):
        fail("Question stable IDs are not unique")

    if args.verify_only:
        print(
            f"Verified {len(updated['questions'])} questions; "
            f"{sum(e['visualBlankCount'] for e in logic_entries.values())} logic blanks; "
            f"{len(sentence_entries)} separately checked sentence-insertion question(s)."
        )
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=args.output.name + ".", suffix=".tmp", dir=args.output.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(updated, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        os.replace(temp_name, args.output)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)
    print(
        f"Wrote {args.output}; verified {len(updated['questions'])} questions, "
        f"{sum(e['visualBlankCount'] for e in logic_entries.values())} logic blanks, "
        f"and {len(sentence_entries)} separately checked sentence-insertion question(s)."
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
