# Repository Guidelines

## Project Structure & Module Organization
- `lib/`: Core Scheme modules (`rdfop.scm`, `rdfop-parser.scm`, `main.scm`).
- `web/`: RDFHP templates and app init (`index.rdfhp`, `view.rdfhp`, `rdf.rdfhp`, `init.scm`). Routes are registered in `init.scm`.
- `data/` (git‑ignored): Runtime database, schemas, logs, and settings.
- `memcp/`: Built dependency (cloned by `make`).
- Root: `Makefile`, `run.sh`, demo `example.ttl`, optional `index.html` (frontend prototype).

## Build, Test, and Development Commands
- `make`: Clones and builds `memcp` (Go), the runtime for this repo.
- `./run.sh`: Starts the server via `memcp` with `lib/main.scm` and `web/init.scm`.
- Open `http://localhost:3443`: Browse routes (`/`, `/index`, `/view`, `/rdf`, `/about`).
- From server console, import data: `(load_ttl "rdf" (stream "example.ttl"))`.

## Coding Style & Naming Conventions
- Language: Scheme‑like `.scm` and `.rdfhp` templates; block comments use `/* ... */`.
- Indentation: Tabs or 2 spaces; keep it consistent within a file; wrap at ~100 chars.
- Filenames: Lowercase; hyphens allowed for modules (e.g., `rdfop-parser.scm`); templates mirror routes (e.g., `web/view.rdfhp`).
- Templates: Prefer `PRINT HTML` for user content; only use `PRINT RAW` when safe.

## Testing Guidelines
- No formal test harness yet. Use manual checks:
  - Start server and exercise routes.
  - Validate SPARQL/RDFHP via `/rdf` console.
  - Load `.ttl` fixtures with `load_ttl` and verify query results.
- Add small, focused modules; keep side effects in `web/init.scm`.

## Commit & Pull Request Guidelines
- Commits: Short, imperative subject lines (e.g., `add RDF console`, `fix parser error`).
- PRs: Include purpose, key changes, reproduction steps, and screenshots of pages or console output where relevant. Link issues.
- Keep diffs focused; update `README.md` when behavior or commands change.

## Security & Configuration Tips
- `data/` and `memcp/` are git‑ignored; do not commit runtime data.
- Default port is `3443` (see `web/init.scm`). Avoid exposing publicly without hardening.
- CSP in `index.html` is dev‑oriented; adjust when building a real frontend.
