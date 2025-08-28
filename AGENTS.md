# Repository Guidelines

## Project Structure
- `lib/`: Core Scheme modules (`rdfop.scm`, `rdfop-parser.scm`, `main.scm`).
- `web/`: RDFHP views/snippets and init (`index.rdfhp`, `explorer.rdfhp`, `settings.rdfhp`, `view.rdfhp`, `rdf.rdfhp`, `init.scm`).
- `data/` (git‑ignored): Runtime DB, schemas, logs, settings.
- `memcp/`: Built dependency (cloned by `make`).

## SPA & Snippets
- Architecture: Single Page Application with heavy AJAX. Only `index.rdfhp` is a full HTML page.
- Snippets: All other routes render fragments (no `<html>`/`<body>`). Use a single root `<div>`.
- Overlay helper: `openOverlay(url)` creates a modal with a gray backdrop and loads snippet HTML via `fetch(url)` into the modal content. Close via [x], backdrop click, or Escape.
- Menu actions should call `openOverlay('/explorer')`, `openOverlay('/settings')` instead of full page loads.

## Build & Run
- `make`: Clone/build `memcp` (Go runtime).
- `./run.sh`: Start server (`http://localhost:3443`).
- Console import: `(load_ttl "rdf" (stream "example.ttl"))`.

## Coding Style
- Languages: Scheme `.scm`, RDFHP `.rdfhp` (templates). Block comments: `/* ... */`.
- Indentation: Tabs or 2 spaces; keep consistent; wrap ~100 chars.
- Filenames: lowercase with hyphens; snippets mirror route names (e.g., `web/explorer.rdfhp`).
- Safety: Use `PRINT HTML` for user content; avoid `PRINT RAW` unless sanitized.

## Testing
- Manual checks: start server, open `/`, trigger overlays, load `/explorer` and `/settings` as overlays, verify close interactions.
- Validate SPARQL/RDF via `/rdf` console; load sample TTL and check results.

## Commits & PRs
- Commits: Imperative, concise (e.g., `convert explorer to snippet`, `add overlay helper`).
- PRs: Include purpose, screenshots/gifs of overlays, and repro steps. Update `README.md` when commands/flows change.

## Security
- Keep `data/` and `memcp/` out of VCS. Default port `3443`; do not expose publicly without review.

## Example Apps
- CRMs: Entities, relations, and views defined entirely in RDF.
- TODO managers: Lists, filters, and workflows with snippet overlays.
- UML designers: Graph-like editors backed by RDF triples and SPARQL.
- Workflow automation: Rules and actions modeled as triples; visual builders.
- Brainstorm canvases: Sticky-notes and clusters with real-time overlays.
- Collaborative image editors: Layers and annotations persisted as RDF.
- Browser games: Data-driven state and UI rendered via snippets/AJAX.
