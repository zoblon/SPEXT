#!/usr/bin/env python3
"""Helper for the guard tests: works with the string catalogs without Xcode.

  xcstrings_tool.py lproj <catalog.xcstrings> <resources-dir>
      Writes <lang>.lproj/<table>.strings for every language of the catalog (including the
      source language), so a plain bundle can load the real translations.

  xcstrings_tool.py check <catalog.xcstrings> <sources-dir>
      Verifies that the catalog and the Swift sources agree:
        - every String(localized: "...") key exists in the catalog,
        - every key of the catalog is used in the sources (no stale entries),
        - every translatable key has a translation for each language,
        - translations keep the same format specifiers as the key.
"""
import json
import os
import re
import sys

SPECIFIER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|s)")


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def languages(catalog):
    found = {catalog["sourceLanguage"]}
    for entry in catalog["strings"].values():
        found.update(entry.get("localizations", {}))
    return sorted(found)


def translation(catalog, key, language):
    entry = catalog["strings"][key]
    unit = entry.get("localizations", {}).get(language, {}).get("stringUnit")
    if unit is not None:
        return unit["value"]
    if language == catalog["sourceLanguage"]:
        return key
    return None


def escape(value):
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def write_lproj(catalog_path, out_dir):
    catalog = load(catalog_path)
    table = os.path.splitext(os.path.basename(catalog_path))[0]
    for language in languages(catalog):
        folder = os.path.join(out_dir, f"{language}.lproj")
        os.makedirs(folder, exist_ok=True)
        lines = []
        for key in sorted(catalog["strings"]):
            if catalog["strings"][key].get("shouldTranslate") is False:
                continue
            value = translation(catalog, key, language)
            if value is not None:
                lines.append(f'"{escape(key)}" = "{escape(value)}";')
        with open(os.path.join(folder, f"{table}.strings"), "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")


def swift_sources(directory):
    for base, _, files in os.walk(directory):
        for name in files:
            if name.endswith(".swift"):
                path = os.path.join(base, name)
                with open(path, encoding="utf-8") as handle:
                    yield path, handle.read()


def to_key(literal):
    """Swift literal body -> catalog key: interpolations become %@."""
    return re.sub(r"\\\([^)]*\)", "%@", literal)


def multiline_body(raw):
    lines = raw.split("\n")
    indent = len(lines[-1]) - len(lines[-1].lstrip())
    body = "\n".join(line[indent:] for line in lines[:-1])
    return re.sub(r"\\\n", "", body)


def localized_keys(source):
    keys = [to_key(m.group(1)) for m in re.finditer(r'String\(localized:\s*"(?!"")((?:[^"\\]|\\.)*)"', source)]
    for m in re.finditer(r'String\(localized:\s*"""\n(.*?)"""', source, re.S):
        keys.append(to_key(multiline_body(m.group(1))))
    return keys


def check(catalog_path, sources_dir):
    catalog = load(catalog_path)
    strings = catalog["strings"]
    problems = []
    sources = list(swift_sources(sources_dir))
    corpus = "\n".join(text for _, text in sources)

    for path, text in sources:
        for key in localized_keys(text):
            if key not in strings:
                problems.append(f"{os.path.relpath(path)}: key missing in catalog: {key!r}")

    langs = [lang for lang in languages(catalog) if lang != catalog["sourceLanguage"]]
    for key, entry in strings.items():
        if entry.get("shouldTranslate") is False:
            continue
        pattern = re.escape(key).replace("%@", r"\\\([^)]*\)").replace("\\ ", " ")
        multiline = "\n".join(line.strip() for line in corpus.split("\n"))
        if not re.search(pattern, corpus) and not re.search(pattern, multiline):
            problems.append(f"stale catalog key (not used in sources): {key!r}")
        for lang in langs:
            value = translation(catalog, key, lang)
            if value is None or not value.strip():
                problems.append(f"missing {lang} translation: {key!r}")
            elif SPECIFIER.findall(value) != SPECIFIER.findall(key):
                problems.append(f"format specifiers differ in {lang}: {key!r}")

    for problem in problems:
        print("FAIL:", problem, file=sys.stderr)
    if problems:
        sys.exit(1)
    print(f"PASS: String catalog is consistent ({len(strings)} keys, languages: {', '.join(languages(catalog))})")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "lproj":
        write_lproj(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "check":
        check(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
