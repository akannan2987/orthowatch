[← README](../README.md) · [All docs in order](../README.md#the-tutorial-in-order) · [Glossary](GLOSSARY.md)

# Uninstalling OrthoWatch — completely and safely

The project was built to be **self-contained**: the app, the Python
venv, the R package library, the raw data, and the database all live
*inside the project folder*. Removing that folder removes almost
everything.

## 0. Before you delete: what you cannot get back

- **The raw data snapshot.** `data/` is gitignored — deletion is
  permanent, and MAUDE *revises reports in place* (see the honesty
  notes), so a future re-fetch may not return today's exact bytes.
  If any analysis mattered, export it first: Data tab → CSV/Excel,
  and consider keeping a copy of `data/raw/` elsewhere.
- **The run history.** The ledger lives in the database; it goes
  with the folder.

Everything else — code, docs, figures, report — is safe on GitHub.

## 1. The core removal (one command)

```bash
cd ~/Documents/Work/projects
rm -rf orthowatch
```

That removes: the code, `data/raw` and the database, the Python
venv (`.venv/`), the project's R packages (`renv/`), and the
project `.Renviron` holding your API key copy.

## 2. Optional leftovers, in likely order of caring

**Your API key line in the shell startup file** — doc 02 added
`export OPENFDA_API_KEY=...` to `~/.zshrc` (or `~/.bash_profile`).
Open the file, delete that line, save. (The key itself can also be
abandoned harmlessly — it grants nothing but rate limits.)

**The renv package cache** — renv keeps downloaded R packages in a
*shared* cache outside the project (macOS:
`~/Library/Caches/org.R-project.R/R/renv`) so other projects can
reuse them. Leave it unless you use renv nowhere else; then the
cache folder can be deleted too.

**The GitHub repository** — if the public copy should go as well:
GitHub → repo → Settings → scroll to Danger Zone → Delete this
repository (it asks you to type the name; this also removes the
Pages site and releases). Deleting local first and GitHub second is
the safe order — never the reverse until you're sure.

**System applications** — R, RStudio, Python, Git, and Quarto were
installed machine-wide in doc 01 and are shared by any other
project; uninstall them only if you truly use them nowhere
(standard macOS app removal / installer docs apply).

## 3. Verify

```bash
ls ~/Documents/Work/projects/orthowatch   # No such file or directory
grep OPENFDA ~/.zshrc                     # (nothing, if you removed the line)
```

That's the whole footprint. A project that documents its own
removal is telling you it knows exactly where it put things.
