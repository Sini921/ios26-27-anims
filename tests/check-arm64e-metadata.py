"""Check the actual class_ro fixups in built packages, not compiler flags."""
import re
import subprocess
import sys
import tempfile
from pathlib import Path


for argument in sys.argv[1:]:
    package = Path(argument)
    with tempfile.TemporaryDirectory(prefix="27anims-metadata-") as directory:
        subprocess.run(["dpkg-deb", "-x", str(package), directory], check=True)
        checked = 0
        for binary in Path(directory).rglob("*"):
            if not binary.is_file():
                continue
            with binary.open("rb") as stream:
                magic = stream.read(4)
            if magic not in (b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xcf\xfa\xed\xfe"):
                continue
            symbols = subprocess.check_output(["nm", "-arch", "arm64e", "-nm", str(binary)], text=True)
            classes = re.findall(
                r"^([0-9a-fA-F]+).*\bexternal (_OBJC_(?:META)?CLASS_\$_\S+)$", symbols, re.MULTILINE
            )
            fixups = subprocess.check_output(
                ["xcrun", "dyld_info", "-arch", "arm64e", "-fixups", str(binary)], text=True
            )
            types = {
                int(address, 16): kind
                for address, kind in re.findall(r"\b(0x[0-9a-fA-F]+)\s+(\S+)", fixups)
            }
            assert classes, f"No defined Objective-C classes found: {binary}"
            for address, name in classes:
                # objc_class: isa, superclass, cache[2], class_data_bits_t.
                kind = types.get(int(address, 16) + 32)
                assert kind == "rebase", f"{binary.name}: {name} class_ro uses {kind}, expected unsigned rebase"
            checked += 1
            print(f"PASS {package.name}: {binary.name}, {len(classes)} unsigned class_ro pointers")
        assert checked == 2, f"Expected tweak and preferences binaries in {package}, found {checked}"
