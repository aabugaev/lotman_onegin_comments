# «Евгений Онегин» with Yu. M. Lotman's commentary

A reader for Pushkin's novel in which every place commented on by Lotman is
highlighted. Click (or tap) a highlighted place and the commentary on it opens
in a panel on the right (a bottom sheet on a phone).

**Read it:** <https://aabugaev.github.io/lotman_onegin_comments/>
(GitHub Pages must be enabled for the repository: *Settings → Pages → Deploy
from a branch → `main` / root*.)

## What is in the repository

| Path | What it is |
| --- | --- |
| `index.html`, `assets/` | the reader — plain HTML/CSS/JS, no build step |
| `data/onegin.json` | the novel: dedication, eight chapters, Pushkin's notes, translations of foreign phrases |
| `data/lotman-map.json` | **the correspondence file**: which fragment of the novel each entry of the commentary refers to |
| `tools/` | scripts that produce the two data files |

### The correspondence file

`data/lotman-map.json` has one entry per line. For example:

```json
{"id":"1.IV:13-14","ch":1,"scope":"lines","block":"1.IV","lines":[13,14],"ref":"IV, 13—14",
 "lemma":"...Свет решил, / Что он умен и очень мил","spans":[[13,19,29],[14,0,23]],
 "page":552,"anchor":"$p552"}
```

- `block` — id of a block in `onegin.json` (`1.IV` is chapter 1, stanza IV;
  `3.tatiana`, `3.song`, `8.onegin` are the letters and the song; `N.ep` an epigraph).
- `scope` — what is commented on: `lines` (specific verses), `stanza` (a whole
  stanza, or a run of stanzas up to `to`), `block`, `epigraph`, `chapter`,
  `title`, `subtitle`, `dedication`.
- `lines` — first and last verse, numbered within the block as Lotman numbers them.
- `lemma` — the words of Pushkin that Lotman quotes at the head of the entry.
- `spans` — where exactly those words are: `[verse, from, to]`, character
  offsets in the verse string of `onegin.json`. This is what gets highlighted.
- `page`, `anchor` — page of the 1995 edition and the nearest anchor on the FEB
  page, used to open the entry at its source.

509 entries are mapped: 436 to specific verses, the rest to stanzas, epigraphs,
chapter openings, the title and the dedication.

## Where the text of the commentary comes from

Pushkin's text is in the public domain. Lotman's commentary is not (Yu. M. Lotman
died in 1993), so **its text is not in this repository** — only the map above.
The reader shows the commentary in one of two ways:

1. **From FEB.** By default the panel opens the commentary on
   [feb-web.ru](https://feb-web.ru/feb/pushkin/critics/lot/lot-472-.htm), scrolled
   to the page with the entry.
2. **From your own copy.** `tools/build.sh` also writes
   `local/lotman-comments.json` (git-ignored) with the entries cut out one by
   one. Load that file once via **Аа → Текст комментария → Загрузить файл…** and
   the entries are shown directly in the panel. The file stays in that browser
   only (IndexedDB), so do it once per device. Please keep the file to yourself.

Add `?feb` to the address to see mode 1 even when a copy is loaded.

## Rebuilding the data

From Git Bash (needs `pdftotext`, `perl`, `curl` — all ship with Git for Windows),
with the PDF of the novel in the repository root:

```bash
bash tools/build.sh
```

To read locally (the page uses `fetch`, so it needs a web server rather than `file://`):

```bash
perl tools/serve.pl
```

and open <http://localhost:8765/>. Served this way, the reader picks up
`local/lotman-comments.json` automatically.

## Sources

- А. С. Пушкин. Евгений Онегин — text from the PDF edition supplied with the project.
- Лотман Ю. М. Роман А. С. Пушкина «Евгений Онегин». Комментарий // Лотман Ю. М.
  Пушкин. — СПб.: Искусство-СПБ, 1995. — С. 472—762. Electronic publication:
  ФЭБ «Русская литература и фольклор».

## Known gaps

- The PDF edition drops the verse quotations inside some of Pushkin's own notes
  (8, 9, 25, 29, 31, 34, 35, 40, 42).
- The PDF has no «Отрывки из путешествия Онегина» and no tenth chapter, so
  Lotman's commentary on them is not mapped yet; neither are his introductory
  essays (chronology, the sketch of gentry life).
