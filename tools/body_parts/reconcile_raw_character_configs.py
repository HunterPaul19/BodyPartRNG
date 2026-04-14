from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


REGION_ORDER = [
    "Head",
    "Torso",
    "LeftArm",
    "RightArm",
    "LeftLeg",
    "RightLeg",
]

REGION_TEMPLATE_PIECE_IDS = {
    "Head": "rig_head",
    "Torso": "rig_torso",
    "LeftArm": "rig_left_arm",
    "RightArm": "rig_right_arm",
    "LeftLeg": "rig_left_leg",
    "RightLeg": "rig_right_leg",
}

REGION_DISPLAY_NAMES = {
    "Head": "Head",
    "Torso": "Torso",
    "LeftArm": "Left Arm",
    "RightArm": "Right Arm",
    "LeftLeg": "Left Leg",
    "RightLeg": "Right Leg",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Preview or apply body-part raw-character config reconciliation from a Studio preview JSON snapshot."
    )
    parser.add_argument("mode", choices=("preview", "apply"))
    parser.add_argument("--snapshot", required=True, help="Path to the JSON file exported by RawCharacterReconciler.ExportPreviewJson().")
    parser.add_argument(
        "--repo-root",
        help="Optional repo root override. Defaults to the parent of the tools folder containing this script.",
    )
    return parser.parse_args()


def load_snapshot(snapshot_path: Path) -> dict:
    data = json.loads(snapshot_path.read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict):
        raise ValueError("Snapshot JSON must decode to an object.")
    return data


def format_lua_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def format_lua_key(key: str) -> str:
    if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", key):
        return key
    return f"[{format_lua_string(key)}]"


def compute_line_offsets(lines: list[str]) -> list[int]:
    offsets = [0]
    total = 0
    for line in lines:
        total += len(line)
        offsets.append(total)
    return offsets


def locate_top_level_entry_bounds(text: str, key: str) -> tuple[int, int]:
    lines = text.splitlines(keepends=True)
    offsets = compute_line_offsets(lines)
    patterns = [
        re.compile(rf'^\t{re.escape(key)}\s*=\s*\{{\s*$'),
        re.compile(rf'^\t\[{re.escape(format_lua_string(key))}\]\s*=\s*\{{\s*$'),
    ]

    for index, line in enumerate(lines):
        stripped = line.rstrip("\r\n")
        if not any(pattern.match(stripped) for pattern in patterns):
            continue

        depth = stripped.count("{") - stripped.count("}")
        last_index = index
        while depth > 0:
            last_index += 1
            if last_index >= len(lines):
                raise ValueError(f'Unbalanced braces while scanning entry "{key}".')
            depth += lines[last_index].count("{") - lines[last_index].count("}")

        return offsets[index], offsets[last_index + 1]

    raise ValueError(f'Could not locate top-level entry "{key}".')


def replace_entry_block(text: str, key: str, new_block: str) -> str:
    start, end = locate_top_level_entry_bounds(text, key)
    return text[:start] + new_block + text[end:]


def get_entry_block(text: str, key: str) -> str:
    start, end = locate_top_level_entry_bounds(text, key)
    return text[start:end]


def locate_field_line_index(lines: list[str], field_name: str, indent_tabs: int) -> int:
    pattern = re.compile(rf'^\t{{{indent_tabs}}}{re.escape(field_name)}\s*=')
    for index, line in enumerate(lines):
        if pattern.match(line):
            return index
    raise ValueError(f'Could not locate field "{field_name}" at indent depth {indent_tabs}.')


def replace_scalar_field(block: str, field_name: str, value_source: str, indent_tabs: int) -> str:
    lines = block.splitlines(keepends=True)
    index = locate_field_line_index(lines, field_name, indent_tabs)
    indent = "\t" * indent_tabs
    lines[index] = f"{indent}{field_name} = {value_source},\n"
    return "".join(lines)


def ensure_scalar_field_after(block: str, field_name: str, value_source: str, indent_tabs: int, after_field_name: str) -> str:
    lines = block.splitlines(keepends=True)
    indent = "\t" * indent_tabs
    try:
        index = locate_field_line_index(lines, field_name, indent_tabs)
        lines[index] = f"{indent}{field_name} = {value_source},\n"
        return "".join(lines)
    except ValueError:
        after_index = locate_field_line_index(lines, after_field_name, indent_tabs)
        lines.insert(after_index + 1, f"{indent}{field_name} = {value_source},\n")
        return "".join(lines)


def locate_table_field_bounds(block: str, field_name: str, indent_tabs: int) -> tuple[int, int]:
    lines = block.splitlines(keepends=True)
    offsets = compute_line_offsets(lines)
    pattern = re.compile(rf'^\t{{{indent_tabs}}}{re.escape(field_name)}\s*=\s*\{{\s*$')

    for index, line in enumerate(lines):
        stripped = line.rstrip("\r\n")
        if not pattern.match(stripped):
            continue

        depth = stripped.count("{") - stripped.count("}")
        last_index = index
        while depth > 0:
            last_index += 1
            if last_index >= len(lines):
                raise ValueError(f'Unbalanced braces while scanning table field "{field_name}".')
            depth += lines[last_index].count("{") - lines[last_index].count("}")

        return offsets[index], offsets[last_index + 1]

    raise ValueError(f'Could not locate table field "{field_name}".')


def replace_table_field(block: str, field_name: str, replacement: str, indent_tabs: int) -> str:
    start, end = locate_table_field_bounds(block, field_name, indent_tabs)
    return block[:start] + replacement + block[end:]


def replace_key_line(block: str, key: str) -> str:
    lines = block.splitlines(keepends=True)
    lines[0] = f'\t{format_lua_key(key)} = {{\n'
    return "".join(lines)


def build_pieces_by_region_table(entry: dict) -> str:
    lines = ["\t\tpiecesByRegion = {\n"]
    for region in REGION_ORDER:
        lines.append(f'\t\t\t{region} = {format_lua_string(entry["piecesByRegion"][region])},\n')
    lines.append("\t\t},\n")
    return "".join(lines)


def build_set_block(template_block: str, entry: dict) -> str:
    block = replace_key_line(template_block, entry["setId"])
    block = replace_scalar_field(block, "id", format_lua_string(entry["setId"]), 2)
    block = replace_scalar_field(block, "displayName", format_lua_string(entry["displayName"]), 2)
    block = ensure_scalar_field_after(block, "sourceModelName", format_lua_string(entry["sourceModelName"]), 2, "displayName")
    block = replace_scalar_field(block, "assetGroup", format_lua_string(entry["assetGroup"]), 2)
    block = replace_scalar_field(block, "assetModel", format_lua_string(entry["assetModel"]), 2)
    block = replace_scalar_field(block, "displayName", format_lua_string(entry["displayName"]), 3)
    block = replace_table_field(block, "piecesByRegion", build_pieces_by_region_table(entry), 2)
    return block


def build_piece_block(template_block: str, set_entry: dict, region: str) -> str:
    piece_id = set_entry["piecesByRegion"][region]
    display_name = f'{set_entry["displayName"]} {REGION_DISPLAY_NAMES[region]}'

    block = replace_key_line(template_block, piece_id)
    block = replace_scalar_field(block, "id", format_lua_string(piece_id), 2)
    block = replace_scalar_field(block, "displayName", format_lua_string(display_name), 2)
    block = replace_scalar_field(block, "region", format_lua_string(region), 2)
    block = replace_scalar_field(block, "setId", format_lua_string(set_entry["setId"]), 2)
    block = replace_scalar_field(block, "assetGroup", format_lua_string(set_entry["assetGroup"]), 2)
    block = replace_scalar_field(block, "assetModel", format_lua_string(set_entry["assetModel"]), 2)
    return block


def insert_blocks_before_return(text: str, blocks: list[str]) -> str:
    marker = "\n}\n\nreturn "
    insert_at = text.rfind(marker)
    if insert_at == -1:
        raise ValueError("Could not locate the final table closing marker.")
    return text[:insert_at] + "".join(blocks) + text[insert_at:]


def summarize_snapshot(snapshot: dict) -> str:
    summary = snapshot.get("summary", {})
    lines = [
        f'Raw characters discovered: {summary.get("rawCharacterCount", 0)}',
        f'Matched configs: {summary.get("matchedConfigCount", 0)}',
        f'New configs needed: {summary.get("newConfigCount", 0)}',
        f'Missing-raw configs: {summary.get("missingRawConfigCount", 0)}',
        f'Conflicts: {summary.get("conflictCount", 0)}',
        f'Requires local config sync: {bool(snapshot.get("requiresLocalConfigSync", False))}',
    ]

    matched_updates = [entry for entry in snapshot.get("matchedConfigs", []) if entry.get("sourceModelNameChanged")]
    if matched_updates:
        lines.append("Source model updates:")
        for entry in matched_updates:
            lines.append(
                f'  - {entry["setId"]}: {entry.get("previousSourceModelName")} -> {entry.get("nextSourceModelName")}'
            )

    new_configs = snapshot.get("newConfigs", [])
    if new_configs:
        lines.append("New configs:")
        for entry in new_configs:
            lines.append(f'  - {entry["rawName"]} -> {entry["setId"]}')

    missing_raw = snapshot.get("missingRawConfigs", [])
    if missing_raw:
        lines.append("Missing raw configs left untouched:")
        for entry in missing_raw:
            lines.append(f'  - {entry["setId"]}: {entry["sourceModelName"]}')

    conflicts = snapshot.get("conflicts", [])
    if conflicts:
        lines.append("Conflicts:")
        for entry in conflicts:
            lines.append(
                f'  - {entry["rawName"]} ({entry["slug"]}) -> {", ".join(entry["conflictedSetIds"])}'
            )

    return "\n".join(lines)


def apply_snapshot(snapshot: dict, repo_root: Path) -> list[str]:
    sets_path = repo_root / "src/game/ReplicatedStorage/Shared/Config/BodyParts/Sets.lua"
    pieces_path = repo_root / "src/game/ReplicatedStorage/Shared/Config/BodyParts/Pieces.lua"

    sets_text = sets_path.read_text(encoding="utf-8")
    pieces_text = pieces_path.read_text(encoding="utf-8")

    rig_set_block = get_entry_block(sets_text, "rig")
    rig_piece_blocks = {
        region: get_entry_block(pieces_text, template_piece_id)
        for region, template_piece_id in REGION_TEMPLATE_PIECE_IDS.items()
    }

    change_notes: list[str] = []

    for matched_entry in snapshot.get("matchedConfigs", []):
        if not matched_entry.get("sourceModelNameChanged"):
            continue

        set_id = matched_entry["setId"]
        set_block = get_entry_block(sets_text, set_id)
        updated_block = ensure_scalar_field_after(
            set_block,
            "sourceModelName",
            format_lua_string(matched_entry["nextSourceModelName"]),
            2,
            "displayName",
        )
        sets_text = replace_entry_block(sets_text, set_id, updated_block)
        change_notes.append(
            f'updated set "{set_id}" sourceModelName -> {matched_entry["nextSourceModelName"]}'
        )

    new_set_blocks: list[str] = []
    new_piece_blocks: list[str] = []

    for new_entry in snapshot.get("newConfigs", []):
        set_id = new_entry["setId"]

        try:
            get_entry_block(sets_text, set_id)
            raise ValueError(f'Set "{set_id}" already exists locally; refusing to append a duplicate.')
        except ValueError as error:
            if "Could not locate top-level entry" not in str(error):
                raise

        new_set_blocks.append(build_set_block(rig_set_block, new_entry))
        change_notes.append(f'created set "{set_id}" from raw "{new_entry["rawName"]}"')

        for region in REGION_ORDER:
            piece_id = new_entry["piecesByRegion"][region]
            try:
                get_entry_block(pieces_text, piece_id)
                raise ValueError(f'Piece "{piece_id}" already exists locally; refusing to append a duplicate.')
            except ValueError as error:
                if "Could not locate top-level entry" not in str(error):
                    raise

            new_piece_blocks.append(build_piece_block(rig_piece_blocks[region], new_entry, region))
            change_notes.append(f'created piece "{piece_id}"')

    if new_set_blocks:
        sets_text = insert_blocks_before_return(sets_text, new_set_blocks)
    if new_piece_blocks:
        pieces_text = insert_blocks_before_return(pieces_text, new_piece_blocks)

    sets_path.write_text(sets_text, encoding="utf-8")
    pieces_path.write_text(pieces_text, encoding="utf-8")
    return change_notes


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve() if args.repo_root else Path(__file__).resolve().parents[2]
    snapshot = load_snapshot(Path(args.snapshot).resolve())

    print(summarize_snapshot(snapshot))

    if args.mode == "preview":
        return 0

    notes = apply_snapshot(snapshot, repo_root)
    print("")
    print("Applied local config changes:")
    for note in notes:
        print(f"  - {note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
