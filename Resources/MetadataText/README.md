# German metadata display

`german-umlauts.json` contains complete-word mappings derived from igerman98's
German Hunspell dictionary, distributed by
[wooorm/dictionaries](https://github.com/wooorm/dictionaries/tree/8cfea406b505e4d7df52d5a19bce525df98c54ab/dictionaries/de).
The data is redistributed under GPL-3.0; see `NOTICE.txt` and
`COPYING-GPL-3.0.txt`.

Regenerate from the pinned, SHA-256-checked upstream data with:

```sh
python3 scripts/generate-german-umlauts.py
```

The generator includes base words and conservative single-affix forms. Compound,
continuation and circumfix rules are excluded. Existing dictionary spellings and
protected international names win over potential umlaut substitutions; ambiguous
substitutions are discarded. Words without umlauts never introduce a standalone
ss → ß conversion. The generator records the complete transformation from the
upstream source; the dictionary itself is not edited.

The app applies this to display names, descriptions and episode text, preserving
capitalization and Unicode. Unknown words and mixed-case names are left alone.
Raw provider strings are retained for Codable round trips and content identity;
URLs and identifiers are not normalized. The lexicon loads once, and corrected
strings use a bounded 1 MiB cache.
