#!/usr/bin/env bash
# OrthoWatch one-command setup - prepares a cloned repo to run.
# It INSTALLS DEPENDENCIES ONLY; it never fetches data or runs the
# pipeline for you (those cost time and API budget - your call, and
# docs/02-phase-1-ingestion.md walks them).
set -e
echo "== OrthoWatch setup =="

command -v Rscript >/dev/null 2>&1 || {
  echo "R not found. Install R first: https://cran.r-project.org"; exit 1; }
command -v python3 >/dev/null 2>&1 || {
  echo "Python 3 not found. Install it first: https://www.python.org"; exit 1; }

echo "-- Python: creating .venv and installing requirements..."
python3 -m venv .venv
./.venv/bin/pip install --quiet --upgrade pip
./.venv/bin/pip install --quiet -r requirements.txt

echo "-- R: restoring pinned packages via renv (first run takes a while)..."
Rscript -e 'if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv", repos = "https://cloud.r-project.org"); renv::restore(prompt = FALSE)'

echo ""
echo "== Setup complete. Next steps =="
echo "1. API key (free, 2 min): docs/02-phase-1-ingestion.md, section 3"
echo "   - shell:  export OPENFDA_API_KEY=...   (in your shell startup file)"
echo "   - R apps: echo 'OPENFDA_API_KEY=...' >> .Renviron   (gitignored)"
echo "2. Activate Python:   source .venv/bin/activate"
echo "3. Fetch + build everything (~30-40 min):   Rscript run_pipeline.R all"
echo "4. Launch the app:    R -e 'shiny::runApp(\"app\")'"
echo ""
echo "The full tutorial starts at docs/01-setup.md."
