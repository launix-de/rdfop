# Low-Code Editor & Code Generator — Roadmap and Instructions
**Based on RDFOP / RDFHP wording and template syntax.**  
Triple store: **memcp** (used opaquely by RDFOP/RDFHP).  

---

## Overview

This project implements a low-code **model-driven development** platform using the RDF-first approach of **Resource Description Format Oriented Programming (RDFOP)**. Models, editor UI descriptions, generator rules and templates are represented as RDF (Turtle `.ttl`) and processed with RDFHP-style templates and SPARQL queries.

Key ideas:
- Models are arbitrary RDF graphs (one graph per module).
- The platform ships a *single hard-coded* TTL schema describing the editor components, code generator entry points, and minimal entity type / attribute constraints. Everything else is queryable and extensible by adding new RDF schema definitions and editor definitions.
- Code generation is driven by `rdfop:GeneratorRule` resources: each rule binds a SPARQL query to a template (RDFHP-style). Templates can emit any target language (JS, SQL, Python, C++, PHP...) and can call other rules recursively.
- Triple store: **memcp**. In practice RDFOP/RDFHP hides the memcp usage; your templates and SPARQL run against the RDFOP runtime.

---

## Major components

1. **Model Store**
   - memcp as triple store (opaque to templates).
   - Models are Turtle files / named graphs loaded into the RDF store.

2. **Self-describing Schema**
   - A minimal, hardcoded TTL schema describes:
     - Which entity types exist (`rdfop:EntityType`),
     - Attribute definitions (`rdfop:Attribute`), their types, and cardinalities (1:0..1, 1:1, 1:n),
     - Available editor components (`rdfop:EditorComponent`), and which attribute types they support,
     - Code generators (`rdfop:CodeGenerator`) and available target languages,
     - Generator rules (`rdfop:GeneratorRule`) linking SPARQL -> Template -> Output path metadata.
   - Everything else (models, UI layouts, specialized constraints) is loose and extensible via RDF.

3. **Editor UI**
   - Graph canvas (drag/drop), property inspector, triple/Turtle view, and template editor.
   - Editor components are described in RDF and use a two-way-binding HTML template syntax using RDF path references (SPARQL path-like bindings).
   - Components receive context variables such as:
     - `?id` — the RDF subject being edited.
     - `?schema` — the schema graph/node for current type.
     - `?depth` — recursion depth for nested editors (to cap circular nesting).
     - `?path` — the RDF path within the current model.
   - Editor components may emit RDF updates (triples) or patch transactions.

4. **Code Generator**
   - Generator rules are RDF resources that contain:
     - A SPARQL query (extracts model fragments)
     - An RDFHP-style template that renders code text
     - Metadata: output filename pattern, language tag, ordering and dependencies
   - Language-specific code generators (one per language) implement helper functions (e.g., type mapping, identifier escaping) and handle scope injection (mapping `{object}.age` to `table_alias.age` for SQL or `obj.age` for JS).
   - Security: code templates are sandboxed; generator helpers restrict access (e.g., permission checks injected as RDF facts can deny reading certain RDF paths).

---

## Editor component schema (conceptual)

Each editor component is described as an RDF resource with:
- `rdfop:componentId` — IRI/ID
- `rdfop:forTypes` — which attribute types or entity types it supports (rdf:list or path expression)
- `rdfop:template` — an RDFHP fragment describing the HTML UI with parameter bindings (see RDFHP syntax below)
- `rdfop:bindings` — mapping of UI controls to RDF paths (subject/predicate)
- `rdfop:maxDepth` — max recursion depth
- `rdfop:mode` — read/write or read-only
- `rdfop:previewQuery` — optional SPARQL to provide sample data for preview mode

Example RDFHP-like template concept (for binding):
```
PARAMETER ?id "id"      // id from the router
SELECT ?label WHERE { ?id rdf:label ?label }
?><div class="field">
  <label><?rdf PRINT HTML ?label ?></label>
  <input data-bind="rdf:object=?id; rdf:predicate=rdf:label" />
</div>
```

---

## Generator rule schema (conceptual)

A `rdfop:GeneratorRule` contains:
- `rdfop:ruleId`
- `rdfop:language` (e.g., "sql", "js", "python")
- `rdfop:sparql` (SPARQL string)
- `rdfop:template` (RDFHP template string or pointer)
- `rdfop:outputPath` (filename pattern, templated)
- `rdfop:dependsOn` (other rule IRIs to run first)
- `rdfop:params` (parameter definitions for the rule)

Templates use RDFHP syntax:
```
PREFIX ex: <https://example.org/model#>
SELECT ?class ?p WHERE {?class a ex:Class; ex:prop ?p}
BEGIN
-- class: <?rdf PRINT RAW ?class ?>
-- prop: <?rdf PRINT RAW ?p ?>
END
```

Templates can include helper invocations and call other generator rules by including their `ruleId` (recursive composition).

---

## Expression compilation strategy

Expressions (e.g., `age >= 18`) are stored as first-class RDF nodes (an AST). Example:
```ttl
:expr1 a rdfop:Expr ;
  rdfop:operator "gte" ;
  rdfop:left :ageRef ;
  rdfop:right 18 .
```

A generator rule per language compiles these ASTs:
- A SPARQL query extracts the AST structure for an expression.
- Template renders per-language code using helpers:
  - `expr_to_js`, `expr_to_sql`, `expr_to_py`, etc.
- Scope injection: generator receives a `?scopeMapping` param (e.g., `?scopeMapping = { "self": "u", "order": "o" }`) so variable references become `u.age` (SQL `u.age`), `self.age` (JS `self.age`) or `order["age"]` (Python), as required.
- Security rules can be evaluated at generation time by querying RDF policies; if forbidden, the generator emits comments/warnings or raises errors.

---

## AST, Expressions, and UI editing

Because the editor schema is expressive, you can create components to edit AST nodes:
- Node type definitions in RDF: `rdfop:ExprType` with allowed operators and arities.
- Editor components render operator dropdowns and sub-editors for operands (recursively), respecting `rdfop:maxDepth`.

---

## Roadmap (milestones)

1. **M0 — Core (Weeks 0–2)**
   - Produce self-describing TTL schema for editor components, code generator, generator rules, and minimal attribute typing. (see `schema.ttl`)
   - Build a CLI to load a module (TTL) into memcp and run a generator rule.

2. **M1 — Prototype UI (Weeks 2–6)**
   - Basic graph canvas using cytoscape.js and RDFHP templates for UI snippets.
   - Property inspector and Turtle editor.
   - Template editor (Monaco) with "run preview" that executes rule SPARQL and renders template preview.

3. **M2 — Language targets & helpers (Weeks 6–10)**
   - Implement JS and SQL generator helpers (type mapping, escaping, scope injection).
   - Expression compiler for simple ASTs.

4. **M3 — Advanced UI & AST editors (Weeks 10–14)**
   - AST-specific editor components (operator dropdown, nested operand panes).
   - Configurable recursion depth & circular reference protection.
   - Module packaging and parameters UI.

5. **M4 — Security & multi-tenant (Weeks 14–18)**
   - Policy injection mechanism via RDF facts.
   - Sandbox generator execution (containerized).

6. **M5 — Libraries & marketplace (Weeks 18–26)**
   - Template & generator rule marketplace, versioned modules, example modules (UML → SQL + React CRUD).
   - Documentation and onboarding tutorials.

---

## Best practices

- Keep generator rules small and composable (one SPARQL + one template per concern).
- Use SHACL or lightweight SPARQL validation shapes to validate models before generation.
- Use parameters for scope mapping and environment-specific config.
- Sandbox template execution and validate template outputs (no arbitrary shell execution).

---

## RDFHP quick reference (used in templates)

- `PARAMETER ?param "name"` — bind GET/compile parameter
- `PREFIX p: <...>` — declare prefixes
- `SELECT ...` — run SPARQL; `BEGIN ... END` loops over results
- `<?rdf PRINT RAW ?var ?>` / `HTML` / `SQL` — safe printing

---

## What I produced
- `schema.ttl` — a self-describing RDF schema for the editor + generator (Turtle).
- `roadmap.md` — this roadmap/instructions document.

Place these files into a module package and `load_ttl` them into RDFOP/memcp. Use the RDFOP runtime (see https://github.com/launix-de/rdfop) to run RDFHP templates and generate artifacts.

---
