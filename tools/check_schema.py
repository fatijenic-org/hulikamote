"""
check_schema.py - check supabase/schema.sql before it is pasted into Supabase.

    hulikamote_backend/venv/Scripts/python.exe tools/check_schema.py

1. The file is parsed with PostgreSQL's own parser (pglast), function bodies included, so a typo is found here and not in the
   SQL editor.
2. Rules that must hold for the phone to be safe:
     - every table of ours has row-level security switched on;
     - every security-definer function fixes its search_path (otherwise it can be tricked into running other code);
     - nothing is granted to the anonymous role except the one function that has to be public;
     - the file can be run twice (tables, functions, triggers and policies are all re-runnable).
Needs `pip install pglast` (a parser only; it is not a backend dependency). Exit code 0 = fine.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

SCHEMA = Path(__file__).resolve().parents[1] / "supabase" / "schema.sql"
OUR_TABLES = {"profiles", "plates", "tickets", "notices", "appeals", "device_tokens"}
PUBLIC_FUNCTIONS = {"plate_taken"}          # the only functions the anonymous role may run


def check(sql: str) -> list[str]:
    """Returns the problems found (empty = fine)."""
    import pglast
    from pglast import ast
    from pglast.enums import AlterTableType

    problems: list[str] = []
    try:
        statements = pglast.parse_sql(sql)
    except pglast.parser.ParseError as exc:
        return [f"SQL does not parse: {exc}"]

    created, secured, definers_ok = set(), set(), []
    for raw in statements:
        node = raw.stmt
        if isinstance(node, ast.CreateStmt):
            name = node.relation.relname
            created.add(name)
            if not node.if_not_exists:
                problems.append(f"create table {name} is not re-runnable (add 'if not exists')")
        elif isinstance(node, ast.AlterTableStmt) and any(c.subtype == AlterTableType.AT_EnableRowSecurity for c in node.cmds):
            secured.add(node.relation.relname)
        elif isinstance(node, ast.CreateFunctionStmt):
            fname = node.funcname[-1].sval
            if not node.replace:
                problems.append(f"function {fname} is not re-runnable (use 'create or replace')")
            options = {o.defname: o.arg for o in node.options}
            language = options["language"].sval if "language" in options else ""
            body = options["as"][0].sval if "as" in options else ""
            if language == "plpgsql":
                try:
                    returns = node.returnType.names[-1].sval if node.returnType else "void"
                    pglast.parse_plpgsql(f"create function f() returns {returns} language plpgsql as $b$ {body} $b$")
                except pglast.parser.ParseError as exc:
                    problems.append(f"function {fname}: body does not parse: {exc}")
            if "security" in options and options["security"].boolval:
                fixed_path = any(o.defname == "set" and getattr(o.arg, "name", "") == "search_path" for o in node.options)
                definers_ok.append((fname, fixed_path))

    for name in sorted(OUR_TABLES - created):
        problems.append(f"table {name} is not created")
    for name in sorted(OUR_TABLES - secured):
        problems.append(f"table {name} has no row-level security")
    for fname, has_path in definers_ok:
        if not has_path:
            problems.append(f"security-definer function {fname} does not fix its search_path")

    # grants to the anonymous role: only PUBLIC_FUNCTIONS (and nothing on the tables)
    for match in re.finditer(r"grant\s+(?P<what>.+?)\s+on\s+(?P<on>.+?)\s+to\s+(?P<who>[^;]+);", sql, flags=re.I | re.S):
        who = {w.strip().lower() for w in match["who"].split(",")}
        if "anon" in who:
            target = re.sub(r"\(.*", "", match["on"].replace("function", "")).strip().split(".")[-1]
            if target not in PUBLIC_FUNCTIONS:
                problems.append(f"grants {match['what'].strip()} on {match['on'].strip()} to anon")

    # re-runnable policies and triggers: each 'create policy/trigger' has a 'drop ... if exists' before it
    for kind in ("policy", "trigger"):
        for match in re.finditer(rf"create\s+{kind}\s+(\"[^\"]+\"|\w+)\s+on\s+([\w.]+)", sql, flags=re.I):
            name, table = match.group(1), match.group(2)
            if not re.search(rf"drop\s+{kind}\s+if\s+exists\s+{re.escape(name)}\s+on\s+{re.escape(table)}", sql, flags=re.I):
                problems.append(f"{kind} {name} on {table} is not re-runnable (add 'drop {kind} if exists' before it)")
    return problems


def main() -> int:
    try:
        import pglast  # noqa: F401
    except ImportError:
        print("This check needs the PostgreSQL parser:  pip install pglast")
        return 2
    problems = check(SCHEMA.read_text(encoding="utf-8"))
    for line in problems:
        print("PROBLEM:", line)
    if not problems:
        print(f"{SCHEMA.name}: parses, and the safety rules hold.")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
