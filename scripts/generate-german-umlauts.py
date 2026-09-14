#!/usr/bin/env python3
"""Generate a conservative display-only umlaut lexicon from pinned igerman98 data.

The output is derived GPL-3.0 dictionary data, not a general German spell checker.
Only unambiguous, complete words are mapped; valid original spellings win.
"""
import hashlib
import json
from pathlib import Path
import re
import urllib.request

REVISION = "8cfea406b505e4d7df52d5a19bce525df98c54ab"
BASE = f"https://raw.githubusercontent.com/wooorm/dictionaries/{REVISION}/dictionaries/de/"
HASHES = {
    "index.aff": "57fdd1b16aac2131003c91e0cf2a488becb970382a402a9ce089307301cb3ef0",
    "index.dic": "b5c781a0cf6f285fb6b9b8ab02fbea104b987104a1efdda8a835837e89e3ec77",
    "license": "03abf202c6e207d41f054083cafccbb174a30f6b330ea8dba3aeef0a279cb83e",
}
OUT = Path(__file__).resolve().parents[1] / "Resources" / "MetadataText"
# International names also used in German metadata. These are not misspellings
# even when reversing a transliteration happens to produce a dictionary word.
PROTECTED = {"noel", "noels", "noelle", "phoenix", "phoebe", "zoe", "coen", "coens"}


def fetch(name):
    data = urllib.request.urlopen(BASE + name, timeout=30).read()
    assert hashlib.sha256(data).hexdigest() == HASHES[name], name
    return data.decode("utf-8")


def generate():
    aff, dic, license_text = (fetch(name) for name in HASHES)
    rules = {}
    for line in aff.splitlines():
        parts = line.split()
        if len(parts) < 5 or parts[0] not in ("PFX", "SFX"):
            continue
        kind, flag, strip, add, condition = parts[:5]
        # Compound-only / continuation / circumfix rules are deliberately not
        # expanded. Guessing compounds could change personal names and loanwords.
        if "/" in add or flag in "mhf" or "-" in add:
            continue
        pattern = re.compile(("^" + condition) if kind == "PFX" else (condition + "$"))
        rules.setdefault(flag, []).append((kind, "" if strip == "0" else strip,
                                          "" if add == "0" else add, pattern))
    words = set()
    for line in dic.splitlines()[1:]:
        if not line or line[0].isspace():
            continue
        word, _, flags = line.partition("/")
        if not word.isalpha() or set(flags) & set("dohfn"):
            continue
        words.add(word.lower())
        for flag in flags:
            for kind, strip, add, pattern in rules.get(flag, []):
                if not pattern.search(word):
                    continue
                if kind == "PFX" and word.startswith(strip):
                    expanded = add + word[len(strip):]
                elif kind == "SFX" and word.endswith(strip):
                    expanded = (word[:-len(strip)] if strip else word) + add
                else:
                    continue
                if expanded.isalpha():
                    words.add(expanded.lower())
    candidates = {}
    transliterate = str.maketrans({"ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss"})
    for word in words:
        if not any(letter in word for letter in "äöü"):
            continue
        key = word.translate(transliterate)
        if key != word and key not in words and key not in PROTECTED:
            candidates.setdefault(key, set()).add(word)
    corrections = {key: next(iter(values)) for key, values in candidates.items() if len(values) == 1}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "german-umlauts.json").write_text(
        json.dumps(corrections, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    (OUT / "NOTICE.txt").write_text(
        license_text + "\nHarbor derivative: unambiguous complete-word umlaut mappings.\n"
        + f"Source: {BASE}\nGenerator: scripts/generate-german-umlauts.py\n"
        + "Redistributed under GPL-3.0; see COPYING-GPL-3.0.txt.\n", encoding="utf-8")
    print(f"Generated {len(corrections):,} unambiguous umlaut spellings from {len(words):,} words.")


if __name__ == "__main__":
    generate()
