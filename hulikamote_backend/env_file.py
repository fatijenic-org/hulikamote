"""
env_file.py - change a few KEY=value lines of a .env file and leave every other line (other secrets, comments) as it is.
"""
import os
from pathlib import Path


def update_env(path: Path, values: dict[str, str]) -> None:
    """Set each key in the file (replace its line, or add one) and in this process. Written in one step."""
    for key, value in values.items():
        if not key.isidentifier() or any(c in value for c in "\r\n\0"):
            raise ValueError(f"Cannot write {key}")
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    pending = dict(values)
    for i, line in enumerate(lines):
        key = line.split("=", 1)[0].strip()
        if "=" in line and not line.lstrip().startswith("#") and key in pending:
            lines[i] = f"{key}={pending.pop(key)}"
    lines += [f"{key}={value}" for key, value in pending.items()]
    temp = path.with_name(path.name + ".tmp")
    temp.write_text("\n".join(lines) + "\n", encoding="utf-8")
    temp.replace(path)
    os.environ.update(values)
