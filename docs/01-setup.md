# 01 — Setup: from a blank laptop to a working workshop

**Prerequisites:** a laptop (Windows or macOS), an internet connection, and
about 60–90 minutes. No prior installs, no prior knowledge.
**Learning goal:** by the end you will have every tool installed, understand
what each one is for, have a GitHub repository containing this project's
skeleton, and have made your first commit. You will also understand *why*
projects isolate their environments.
**Checkpoint at the end:** a verification checklist where every command
produces the expected output.

> **How to read this doc:** numbered steps are actions — do them one at a
> time. Text between steps explains why. Commands appear in boxes like
> `this`; type them exactly (or copy-paste) into your **terminal** — that's
> the text-based command window we'll open in Step 3. Lines starting with
> `#` inside command boxes are comments for you, not commands.

---

## 1. What we're installing, and why

| Tool | What it is (plain words) | Why this project needs it |
|---|---|---|
| **R** | A programming language built by statisticians for data analysis | All statistical analysis here is in R — the standard language of medical and pharma statistics |
| **RStudio** | A friendly workbench (editor) for writing and running R | Makes R usable: run code line by line, see plots and tables |
| **Python** | A general-purpose programming language | Fetches data from the FDA API — the most common ingestion language in industry |
| **Git** | A save-game system for code: every meaningful change becomes a snapshot you can return to | Tracks every change the project makes; also how work gets to GitHub |
| **GitHub** | The online home for Git snapshots — where the project lives in public | So anyone can read, reproduce, and learn from this work |
| **Quarto** | Turns text + code + outputs into polished self-updating reports | Powers the surveillance report in phase 7 |

Everything is free.

---

## 2. Install R

R comes from CRAN, the official R archive.

1. Go to <https://cran.r-project.org>.
2. Click **Download R for Windows** → **base** → **Download R-x.y.z for
   Windows** (the version number will be whatever is current).
   *On macOS:* click **Download R for macOS** and pick the file matching
   your chip — **Apple silicon (arm64)** for M-series Macs (2021 or newer),
   **Intel** for older ones. (Apple menu → About This Mac shows which you
   have.)
3. Open the downloaded installer and accept every default. Click through
   until it finishes.

That's it — but don't open R directly; we'll always use it through RStudio.

## 3. Install RStudio, and meet the terminal

1. Go to <https://posit.co/download/rstudio-desktop/>.
2. Scroll past the R step (done) and download **RStudio Desktop** for your
   system. Install with all defaults.
3. Open RStudio. You'll see several panes. The two that matter today:
   - **Console** (left or bottom-left): where R code runs interactively.
   - **Terminal** (a tab next to Console): a text window that talks to your
     *computer* rather than to R. Git and Python commands go here.
4. Click the **Terminal** tab. Verify R is properly installed by typing in
   the **Console** (not the terminal):

```r
R.version.string
```

Expected output (version number may differ):

```
[1] "R version 4.5.1 (2025-06-13)"
```

> **Why one workbench?** You could use separate apps for everything, but
> running R, the terminal, Git, and file browsing in one window keeps a
> beginner's world small. Later phases all happen inside RStudio.

## 4. Install Python

1. Go to <https://www.python.org/downloads/> and click the big yellow
   download button.
2. Run the installer. **Windows, critical step:** on the first screen, tick
   the checkbox **"Add python.exe to PATH"** before clicking Install. (PATH
   is the list of places your computer looks for programs; without this,
   typing `python` in a terminal finds nothing.) macOS: just accept defaults.
3. **Close and reopen RStudio** (the terminal only learns about new programs
   when it restarts). In the **Terminal** tab:

```bash
python --version
```

Expected output (any 3.11+ version is fine):

```
Python 3.13.2
```

> macOS note: if `python` says "command not found", try `python3 --version`
> — on Macs the command is often named `python3`. If so, use `python3`
> everywhere this guide says `python`.

## 5. Install Git

**Windows:**

1. Go to <https://git-scm.com/downloads>, download the Windows installer.
2. Run it. It asks ~12 questions; **accept every default**. (The defaults
   include Git Credential Manager, which will handle GitHub logins for you.)
3. Restart RStudio again.

**macOS:** in the RStudio Terminal, type:

```bash
git --version
```

If Git is missing, macOS pops up an offer to install "command line developer
tools" — click **Install** and wait. Then rerun the command.

Either system, expected output:

```
git version 2.47.0
```

Now introduce yourself to Git — this name and email get stamped onto every
snapshot you make (use the email you'll register on GitHub):

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

(No output means it worked — a very Unix habit: silence is success.)

## 6. Install Quarto

1. Go to <https://quarto.org/docs/get-started/> and download the installer
   for your system. Install with defaults.
2. Restart RStudio one more time (last time, promise). In the Terminal:

```bash
quarto --version
```

Expected output: a version number like `1.7.32`.

## 7. Create your GitHub account and the project repository

1. Go to <https://github.com> → **Sign up**. Choose a professional username
   — it becomes part of this project's public address (e.g., `firstname-lastname` or similar).
   The free plan is all you need.
2. Once logged in, click the **+** (top right) → **New repository**.
3. Fill in:
   - **Repository name:** `orthowatch`
   - **Description:** `Post-market signal detection for orthopedic devices, on real FDA MAUDE data`
   - **Public** (so others can read and reproduce it)
   - Tick **"Add a README file"** (this gives the repo a starting point we
     can clone; we'll replace the README's contents in a moment)
4. Click **Create repository**.

> **Why public from day one?** A repo with weeks of honest, incremental
> commits tells a far better story than one giant "finished project" upload.
> Your commit history is evidence that you actually built this.

## 8. Clone the repository to your laptop

**Cloning** means downloading the repo *with its Git memory attached*, so
snapshots you make locally can be pushed back up.

1. On your repo's GitHub page, click the green **<> Code** button and copy
   the **HTTPS** URL (looks like `https://github.com/YOURNAME/orthowatch.git`).
2. In the RStudio Terminal, go to your home folder and clone:

```bash
cd ~
git clone https://github.com/YOURNAME/orthowatch.git
```

Expected output:

```
Cloning into 'orthowatch'...
remote: Enumerating objects: 3, done.
...
Receiving objects: 100% (3/3), done.
```

3. The first time you *push* (upload) later, Git will pop up a GitHub login
   window — sign in through the browser when it does. That's Git Credential
   Manager doing its job; you won't be asked again.

4. Now open the project in RStudio: **File → Open Project...** won't find
   one yet, so instead use **File → New Project → Existing Directory**,
   browse to the `orthowatch` folder, and click **Create Project**. RStudio
   restarts *inside* the project — from now on, always work here. (This
   also created an `orthowatch.Rproj` file; it just marks the folder as an
   RStudio project.)

## 9. Create the folder structure

In the RStudio Terminal (which now opens inside the project folder —
check that the prompt shows `orthowatch`):

```bash
# -p means "create parent folders as needed, and don't complain if they exist"
mkdir -p data/raw data/processed ingest R analysis app report tests docs
```

What each folder is for (this layout mirrors how professional analysis
repos are organized — one home per kind of thing):

| Folder | Purpose |
|---|---|
| `data/raw/` | Untouched API downloads. Never edited, never committed. |
| `data/processed/` | The SQLite database and cleaned outputs. Regenerated by scripts. |
| `ingest/` | Python scripts that fetch data (phase 1) |
| `R/` | Reusable R functions — the tested "engine" |
| `analysis/` | Exploratory R scripts you run line by line |
| `app/` | The Shiny dashboard (phase 6) |
| `report/` | The Quarto report (phase 7) |
| `tests/` | Automated tests (phase 4 onward) |
| `docs/` | These tutorials |

Git ignores empty folders, so drop a placeholder file in each:

```bash
touch data/raw/.gitkeep data/processed/.gitkeep ingest/.gitkeep R/.gitkeep analysis/.gitkeep app/.gitkeep report/.gitkeep tests/.gitkeep docs/.gitkeep
```

(`touch` creates an empty file; `.gitkeep` is just a conventional name.)

5. Now add this project's starter files: copy the `README.md`, `.gitignore`,
   and `docs/` files provided with this tutorial into the folder, replacing
   the README GitHub created. (If you received them from the blueprint chat,
   download and drop them in; the repo and the tutorial stay in sync from
   here on.)

> **What's a .gitignore?** A list of files Git should pretend not to see.
> Ours excludes `data/` (regenerated by scripts — committing data would
> bloat the repo and hide whether the pipeline really works), package
> libraries (reinstallable), and OS junk. Open it — every line is commented.

## 10. Set up the R environment with renv

Here is the *why* before the how. Packages are add-ons to R (or Python) that
other people wrote. If you install them globally — one shared pile for your
whole laptop — then six months from now, upgrading a package for some other
project can silently break this one. An **isolated environment** gives each
project its own sealed toolbox, plus a written list of exactly which tool
versions it uses, so anyone (including future-you) can
recreate it perfectly. In R that tool is **renv**; in Python, **venv**.

In the RStudio **Console** (the R one, not the Terminal):

```r
# Install renv itself (one-time, from CRAN)
install.packages("renv")

# Initialize an isolated library for THIS project
renv::init()
```

Expected: a wall of text ending with something like:

```
- Project '~/orthowatch' loaded. [renv 1.1.x]
```

renv created a `renv/` folder (the toolbox) and `renv.lock` (the written
list — this one DOES get committed). RStudio may restart itself; that's
normal.

Now install the core packages for the first phases (this takes 5–15
minutes — tidyverse is big; good moment for a coffee):

```r
# tidyverse: the standard toolkit for data manipulation and plotting
# DBI + RSQLite: how R talks to SQLite databases
# janitor: small helpers for cleaning messy column names and data
install.packages(c("tidyverse", "DBI", "RSQLite", "janitor"))

# Snapshot: write the exact versions into renv.lock
renv::snapshot()
```

When `snapshot()` asks to proceed, type `y`. Expected ending:

```
- Lockfile written to "~/orthowatch/renv.lock".
```

## 11. Set up the Python environment with venv

Same idea, Python flavor. In the **Terminal**:

```bash
# Create a virtual environment in a folder called .venv
python -m venv .venv
```

(Silence = success. A `.venv/` folder appeared; it's gitignored.)

Activate it — "activation" just means "for this terminal session, use the
project's Python, not the global one":

```bash
# Windows:
.venv\Scripts\activate
# macOS / Linux:
source .venv/bin/activate
```

Expected: your prompt now starts with `(.venv)`. Then install the two
packages phase 1 needs, and write the version list:

```bash
# requests: makes web/API calls   pandas: tables in Python
pip install requests pandas

# Freeze the exact versions into a file (Python's renv.lock equivalent)
pip freeze > ingest/requirements.txt
```

Expected after install: `Successfully installed ... requests-2.x.x ...`

> You must re-activate the venv (the `activate` command above) each time
> you open a fresh terminal to run Python. Forgetting is the #1 beginner
> stumble — the error looks like `ModuleNotFoundError: No module named
> 'requests'`.

## 12. Your first commit and push

A **commit** is one named snapshot; a **push** uploads your snapshots to
GitHub. The rhythm you'll repeat at every checkpoint:

```bash
# 1. See what changed
git status

# 2. Stage everything new/changed ("put it in the box")
git add .

# 3. Snapshot with a message ("label the box")
git commit -m "Set up project skeleton: folders, renv, venv, docs"

# 4. Upload to GitHub
git push
```

Expected after `git push` (first time, the GitHub login window appears —
sign in via browser):

```
Enumerating objects: ...
To https://github.com/YOURNAME/orthowatch.git
   abc1234..def5678  main -> main
```

Refresh your GitHub page — your structure and docs are live. 🎉

### 12b. The verification habit (three checks that prevent real incidents)

Every one of these guards against a mistake that actually happened
during this project's build — adopt them as reflexes:

1. **Confirm files landed — especially dot-files.** macOS Finder hides
   files starting with a dot, making them the easiest to lose when
   copying. Don't trust your eyes; ask Git or the shell:
   `git ls-files | grep gitignore` or `ls -la`. (Real incident: a
   `.gitignore` arrived without its dot and sat inert while the real
   one lacked the protective rules.)
2. **Prove ignore rules fire before relying on them.**
   `git check-ignore -v path/to/file` prints the exact rule catching a
   file — or nothing, meaning it's NOT protected. Cheap to run, and
   the difference between "I think it's ignored" and "it's ignored".
   (Real incident: a 4 MB generated file reached the public repo
   because its rule was missing; `check-ignore` would have said so in
   one line.)
3. **Read BOTH zones of `git status` before every commit.** The top
   zone ("Changes to be committed") is what the commit will contain;
   the bottom ("Changes not staged") will be silently left behind.
   Scan the top for anything that shouldn't ship (data, generated
   files, secrets) and the bottom for anything that should. (Real
   incident: an edited `.gitignore` sat unstaged through a commit
   whose message claimed to include it.)

Thirty seconds total, every commit. The phase guides' commit steps
assume you're doing this.

## 13. Verification checklist

Run each; tick each ✅ when the output matches.

| # | Where | Command | Expected |
|---|---|---|---|
| 1 | Console | `R.version.string` | an R 4.x version string |
| 2 | Terminal | `python --version` | Python 3.11+ |
| 3 | Terminal | `git --version` | git 2.x |
| 4 | Terminal | `quarto --version` | a version number |
| 5 | Console | `library(tidyverse)` | loads with a startup message, no error |
| 6 | Console | `library(DBI); library(RSQLite)` | silence (= success) |
| 7 | Terminal (venv active) | `python -c "import requests, pandas; print('ok')"` | `ok` |
| 8 | Browser | your GitHub repo page | folders + docs visible, commit message shown |

All eight pass? **Setup phase complete — commit checkpoint reached.** You
built a professional-grade workshop: isolated environments, version control,
and a public repo. Many working analysts never set this up properly.

## 14. Troubleshooting (most common errors)

**`python` / `git` / `quarto` : command not found** — the terminal was open
before the install finished. Close and reopen RStudio. On Windows for
Python: you missed the "Add to PATH" checkbox — rerun the installer, choose
**Modify**, and enable it.

**macOS: `python` not found but `python3` works** — normal; use `python3`
and `pip3` throughout, or note that once the venv is activated, plain
`python` works inside it.

**`ModuleNotFoundError: No module named 'requests'`** — your venv isn't
activated in this terminal. Rerun the `activate` command from step 11.

**`renv::init()` seems stuck** — it's compiling packages; on a slow laptop
tidyverse can take 20 minutes. Watch for CPU activity; only worry after
30+ minutes of true silence.

**`git push` rejected / authentication failed** — the browser login window
sometimes opens *behind* RStudio. Check your taskbar/dock. Still stuck:
run `git push` again; Windows users can also install "Git Credential
Manager" manually from its GitHub page.

**RStudio can't find the Terminal tab** — menu **Tools → Terminal → New
Terminal**.

**Corporate laptop blocks installs** — do this project on a personal
machine; personal projects shouldn't live on an employer's device anyway.

---

**Next:** [`02-phase-1-ingestion.md`](02-phase-1-ingestion.md) — your first
API call, and real FDA data landing on your laptop.
