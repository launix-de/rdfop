# Low-Code Editor & Code Generator — Final Roadmap

This roadmap describes the complete architecture, concepts, design decisions, and implementation details of a model-driven low-code editor and code generator based on RDFOP, RDFHP templates, and memcp triple store.

---

## General Concept

The system is a **model-driven development environment** where arbitrary models (e.g. UML, state machines, workflow diagrams) can be defined, edited, and transformed into executable code in various programming languages.  
It is based on three layers:

1. **Schema Layer** — Describes entities, attributes, constraints, editor components, and generator rules in RDF (Turtle).  
2. **Editor Layer** — Provides human-editable UI components for creating and modifying model instances. UI components are RDFHP templates (read-only scaffolds) combined with Vue.js bindings to RDFJSON data.  
3. **Code Generator Layer** — Uses recursive template expansion (`COMPILE(language, node, context)`) to transform models into target languages.

Key ideas:
- Models are arbitrary RDF graphs (one graph per module).
- The platform ships a *single hard-coded* TTL schema describing the editor components, code generator entry points, and minimal entity type / attribute constraints. Everything else is queryable and extensible by adding new RDF schema definitions and editor definitions.
- Code generation is driven by `rdfop:GeneratorRule` resources: each rule binds a SPARQL query to a template (RDFHP-style). Templates can emit any target language (JS, SQL, Python, C++, PHP...) and can call other rules recursively.
- Data is stored in triple stores in **memcp**, exposed through **RDFJSON** and **RDFHP**. The system separates **code definitions** from **data instances** by database contexts.  

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
     - Code generators (`rdfop:CodeGenerator`) for each available target language producing the code via RDFHP
   - Everything else (models, UI layouts, specialized constraints) is loose and extensible via RDF.

3. **Editor UI**
   - Graph canvas (drag/drop), property inspector, triple/Turtle view, and template editor.
   - Editor components are described in RDF and use a two-way-binding HTML template syntax using RDF path references (SPARQL path-like bindings).
   - Components receive context variables such as:
     - `?id` — the RDF subject being edited.
     - `?depth` — recursion depth for nested editors (to cap circular nesting).
   - Editor components may emit RDF updates (triples) or patch transactions.
   - you can recursively call COMPONENT(?editor, ?params...) to insert another template into the editor

4. **Code Generator**
   - Generator rules are RDF resources that contain:
     - An RDFHP template that renders code text, getting ?id (node id), ?context (context descriptor)
     - you can recursively call COMPILE(?lang, ?id, ?context) inside RDFHP
   - Language-specific code generators (one per language) implement helper functions (e.g., type mapping, identifier escaping) and handle scope injection (mapping `{object}.age` to `table_alias.age` for SQL or `obj.age` for JS).

---

## Node Identifiers

- **Types and editor components**: Use stable names like `rdfop:GeneratorRule`.  
- **Instances created by editors**: Use UUID-based IRIs (`urn:uuid:...`).

---

## Editor Components

- Editor components are described in the schema as instances of `rdfop:EditorComponent`.  
- Each editor declares:
  - `rdfop:forTypes`: which entity types or data types it edits.  
  - `rdfop:template`: an RDFHP preview template containing SPARQL and static rendering.  
  - `rdfop:componentParam`: JSON parameters (e.g. ListEditor’s subEditor).  
  - `rdfop:initTemplate`: for creating default node data with a new UUID.  
  - `rdfop:dbContext`: defines which memcp database the editor operates on (code vs data).

**Binding Mechanism:**  
- RDFHP templates are run over the code database to produce a the vue.js template
- data is fetched using **RDFJSON** queries
- Vue.js is used to bind to the values fetched from the **RDFJSON** query
- RDFJSON produces a JSON object and provenance metadata (linking attributes back to triples).  
- Vue.js binds UI components to JSON data fields (`data.fieldname`).

**Save-back:**  
- Edits generate two TTL snippets:  
  - `DELETE.ttl` removes old triples.  
  - `INSERT.ttl` adds new triples.  
- This supports rollbackable transactions and avoids write-after-write hazards.  

**Recursive Deletion / GC:**  
- Each entity type can define `rdfop:recursiveDelete` rules.  
- Memcp also runs a garbage collector to remove dangling unpinned nodes.  

---

## RDFJSON Query & Save-Back

RDFJSON is basically SPARQL but with JSON_ARRAYAGG() and JSON_OBJECTAGG() extension that provides additional provenance data to know the exact triples that were considered building the result.

Example SPARQL:  
```sparql
SELECT ?person (JSON_ARRAYAGG(?phone) AS ?phones)
WHERE {
  ?person ex:hasPhone ?phone .
}
GROUP BY ?person
```

Produces JSON:  
```json
{
  "person": "Alice",
  "phones": ["123", "456"]
}
```

Or:
```sparql
SELECT (JSON_OBJECTAGG(?property, ?value) AS ?jsonObject)
WHERE {
  ex:Alice ?property ?value .
}
```

which produces:

```json
{
  "jsonObject": {
    "ex:name": "Alice",
    "ex:age": 30,
    "ex:city": "Berlin"
  }
}
```

---

## Code Generators

- There is **one generator per language and node type**.  
- Generators are instances of `rdfop:CodeGenerator`.  
- for instance: Expressions (AST) are compiled recursively using `COMPILE(language, node, context)`.  
- The `context` may be an RDF node or a JSON object carrying scope (e.g., table aliases in SQL).

**Example:**  
SQL generator template for addition:  
```rdfhp
SELECT ?left, ?right WHERE { ?id a "operator+", left ?left, right ?right. }
?>(<? COMPILE("sql", ?left, ?ctx) ?>) + (<? COMPILE("sql", ?right, ?ctx) ?>)<?
```

---

## Export Filters

- `rdfop:attrKind` distinguishes attributes:  
  - `"essential"`, `"code"`, `"codemeta"`, `"ui"`, `"userdata"`.  
- Export filters whitelist/blacklist attributes when extracting `.ttl` files.  
- Metadata like UML X/Y coordinates can be excluded.  

---

## Immutable COW Graphs

- Code definitions are **immutable**: editing creates a copy-on-write version of the root node tree.  
- Subtrees are reused; only modified nodes are copied.  
- Tenants/users reference specific code root nodes:  
  - Production uses stable pinned roots.  
  - Test users can use new roots.  
- Garbage collector removes unreferenced roots.  
- Data nodes are **mutable**.  

---

## Separation of Code and Data

- Different memcp databases (schemas) are used:  
  - Code definitions to render the editor templates: for example `code_instance35`.  
  - Runtime data for the RDFJSON queries: for example `data_instance55`.  

---

## Realtime Collaboration

- memcp stores triples in an SQL table `(s,p,o)`.  
- TRIGGERs capture changes and stream them via websockets.  
- Clients subscribe do node ids via a watchlist
- Editors merge incoming diffs into local Vue.js models.  

---

## Translation and Localization

- All components, filters, and types may define `rdfs:label` with language tags.  
- Editors fetch localized names for displaying titles, buttons, and labels.  

---

## Implementation Roadmap

### Phase 0 — Core (Weeks 0–2)
- Implement RDF schema (`schema.ttl`).  
- Implement RDFJSON query runner with provenance.  
- Implement memcp transaction system with `DELETE/INSERT` TTL apply.  

### Phase 1 — Editor Binding (Weeks 2–6)
- Develop Vue.js binding layer to RDFJSON.  
- Implement save-back (JSON diff → TTL patches).  
- Implement editor initializers with `rdfop:initTemplate`.  

### Phase 2 — Generators (Weeks 6–10)
- Implement SQL and JS generators.  
- Recursive AST compilation via `COMPILE()`.  
- Support context propagation.  

### Phase 3 — Export & Versioning (Weeks 10–14)
- Implement filtered exports via `rdfop:attrKind`.  
- Implement immutable COW roots and pinning/GC.  
- Implement recursive delete rules.  

### Phase 4 — Realtime & Multi-Tenant (Weeks 14–20)
- Implement websocket streaming with memcp TRIGGERs.  
- Implement watchlists.  
- Implement schema/dbContext propagation for separating code and data.  

---

## Deliverables

- `schema.ttl` — self-describing schema.  
- `roadmap.md` — this document.  
- Prototype editors (ListEditor, SimpleText).  
- Example generator rules (UML → SQL).  
- Export and versioning system.  
- Realtime collaborative editor.  

---
