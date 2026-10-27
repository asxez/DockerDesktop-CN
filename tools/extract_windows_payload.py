import sys
from pathlib import Path

import pefile

SEVEN_ZIP_MAGIC = b"7z\xbc\xaf\x27\x1c"


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: extract_windows_payload.py <installer.exe> <output_dir>", file=sys.stderr)
        return 1

    installer = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    output_dir.mkdir(parents=True, exist_ok=True)

    pe = pefile.PE(str(installer), fast_load=True)
    pe.parse_data_directories(
        directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_RESOURCE"]]
    )

    if not hasattr(pe, "DIRECTORY_ENTRY_RESOURCE"):
        print("installer has no PE resources", file=sys.stderr)
        return 2

    candidates = []
    for type_entry in pe.DIRECTORY_ENTRY_RESOURCE.entries:
        if type_entry.struct.Id != 10:  # RT_RCDATA
            continue
        for name_entry in type_entry.directory.entries:
            name = str(name_entry.name or name_entry.struct.Id)
            for lang_entry in name_entry.directory.entries:
                data = lang_entry.data.struct
                blob = pe.get_data(data.OffsetToData, data.Size)
                if blob.startswith(SEVEN_ZIP_MAGIC):
                    candidates.append((name, len(blob), blob))

    if not candidates:
        print("no 7z payload found in installer resources", file=sys.stderr)
        return 2

    # 优先使用 DOCKERDESKTOP；否则取最大的 7z 资源。
    preferred = [item for item in candidates if item[0].upper() == "DOCKERDESKTOP"]
    name, _, blob = preferred[0] if preferred else max(candidates, key=lambda item: item[1])

    target = output_dir / "DOCKERDESKTOP.7z"
    target.write_bytes(blob)
    print(target)
    print(f"resource={name} size={len(blob)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
