![RDFOP screenshot](assets/screenshot.png)

# RDFOP (aka FOP II)

RDFOP is a feature oriented programming framework based on RDF (resource description format). It is a *universal low code tool* which means you have a WYSIWIG editor and you can edit every aspect of the software. A software is purely described by data in RDF format.

## Architecture Guide

RDF is the source of truth for both application data and UI layout. The browser
renders RDFHP component fragments and persists user actions back into the RDF
graph; a reload must reconstruct the same committed state.

The central architectural contracts are documented in
[docs/architecture.md](docs/architecture.md), including:

- generic `/<action>/<id>` resource routing and the separate fragment endpoint;
- component resolution, snippet wrappers, and SPA remounting;
- `ComponentSelector`, `Split`, and `TabGroup` ownership semantics;
- URI-based drag and drop and its move-versus-copy rules;
- mutation, cleanup, refresh, and reload invariants;
- the `TableView` row and open-target contract.

Repository-wide implementation invariants for coding agents and contributors
are summarized in [AGENTS.md](AGENTS.md).

### Building an Application

An RDFOP application is primarily an RDF schema plus an RDF instance graph:

1. Define domain types and properties in Turtle.
2. Bind each renderable type to an `rdfop:view` and, where needed, an
   `rdfop:edit` component.
3. Compose the `main` layout from `Split`, `TabGroup`, `ComponentSelector`, and
   domain-facing components such as `TableView`.
4. Declare application actions as `rdfop:Method` resources and attach their
   RDFHP implementations directly to a resource or to its type.
5. Persist all user-visible state changes as RDF mutations; rendering the graph
   again must reproduce the application state.

Small applications can be assembled almost entirely from the built-in
components. A custom `rdfop:EditorComponent` is needed when the domain requires
its own query, markup, or interaction. Component definitions are themselves RDF:
the built-in component editor edits their RDFHP template, CSS, and JavaScript and
previews the result against a selected resource. Application features should
therefore normally be developed as editable RDFHP components and methods rather
than as additions to the Scheme server. See
[Building an application](docs/architecture.md#8-building-an-application) for a
minimal schema and layout example.

The browser starts with one rendered component, conventionally the resource
`main`. That component composes the rest of the interface from RDF layout nodes:
selectors provide user-configurable palettes, while tab groups, splits, and
editors provide larger work areas.

Every rendered component occupies its own `.rdfop-c` DOM element. It can ask
`/rdfop-render` for fresh HTML and replace only that element through
`rdfopSwap(...)`. Components may contain further components; because each child
has its own component root and render parameters, it can be refreshed or
switched independently of its parent.

RDF resources should appear as real action links wherever practical. Their URLs
are also the common drag payload, so an object can be opened, dragged into a
split or tab, assigned to a selector, or dropped into a compatible resource
selection field. Drop targets validate the resource and persist the resulting
RDF relation rather than merely moving DOM nodes.

`TableView` is the central application-development component for every list of
entities. New list requirements belong in the shared TableView—sorting,
filtering, virtual scrolling, datatype-aware cells, list/chip presentation,
global actions, and per-item actions—not in application-specific list widgets.
Its RDF configuration selects the entity type, filter, ordering, properties,
cell presentation, and interactions. The same configuration has an editor;
whether a user may invoke it must ultimately be controlled through user
capabilities, allowing both adaptable and fixed applications.

## Knowledge Bases and Triple Stores

To store data of any kind, a so-called _knowledge base_ is used.
The most common format for knowledge bases is the so-called _triple store_ AKA RDF (Resource Description Format).
RDF organizes all data in so-called triplets (subject, predicate, object). A common format to express RDF data is .ttl.
Here's an example `.ttl` file:
```
peter a Person;
 forename "Peter";
 surname "Griffindor".
```
which is a short form of:
```
peter a Person.
peter forename "Peter".
peter surname "Griffindor".
```

Now you can query RDF data using SPARQL:
```
SELECT ?forename, ?surname
WHERE {
	?person a Person;
	forename ?forename;
	surname ?surname.
}
```
which will result in:
```
{ "forename": "Peter", "surname": "Griffindor" }
```

## The .rdfhp format

Now if you can query arbitrary knowledge from the knowledge base, what to do next?
We have to somehow style and display the retrieved data. This is what RDFHP is for.
RDFHP stands for RDF hypertext preprocessor and has the following syntax:

```
@PREFIX lx: <https://launix.de/rdf/#> .

PARAMETER ?page "page" // reads GET parameter "page" into ?page

SELECT ?title, ?content WHERE {?page lx:isa lx:page; lx:title ?title; lx:content ?content}

?><!doctype html><html><head>
<title><?rdf PRINT HTML ?title ?></title>
</head><body>
<?rdf PRINT RAW ?content ?>
</body></html>
```

with the following syntax rules:

- `PARAMETER ?param param` will bind ?param to the GET parameter "param"
- you need to write `PREFIX` only once per rdfhp document
- if you add `BEGIN...END` after a `SELECT`, the part between `BEGIN` and `END` is looped over the results
- if there is not `BEGIN...END` after a `SELECT`, only one result will be fetched and the selected variables will be inserted into the current scope
- `PRINT FORMAT ?variable` will print out the content of the variable. `FORMAT` is one of `RAW`, `HTML`, `JSON`, `SQL` and will especially escape strings to be invulnerable to XSS or SQL injections

## Component System

RDFOP uses a data-driven component system. Every UI element is described as RDF data — the same way your application data is stored. Components are defined as `rdfop:EditorComponent` instances in Turtle and are linked from an `rdfop:EntityType` via predicates such as `rdfop:view` and `rdfop:edit`.

### Defining a Component

A minimal component consists of:

1. An entity type (`rdfop:EntityType`)
2. One or more component bindings such as `rdfop:view` or `rdfop:edit`
3. An RDFHP template on the `rdfop:EditorComponent`

```ttl
@prefix rdfop: <https://launix.de/rdfop/schema#> .
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

rdfop:Greeting a rdfop:EntityType ; rdfs:label "Greeting" .
rdfop:message a rdf:Property ; rdfs:domain rdfop:Greeting ; rdfs:range rdfs:Literal .

rdfop:Greeting_view a rdfop:EditorComponent ;
  rdfop:componentTemplate """@PREFIX rdfop: <https://launix.de/rdfop/schema#> .
PARAMETER ?id "id"
SELECT ?msg WHERE { ?id rdfop:message ?msg }
BEGIN
?><div class='rdfop-c'
       data-rdfop-params='{&quot;id&quot;:<?rdf PRINT JSON ?id ?>}'
       data-testid='<?rdf PRINT HTML ?id ?>'>
  <p><?rdf PRINT HTML ?msg ?></p>
</div><?rdf
END""" .

rdfop:Greeting rdfop:view rdfop:Greeting_view .

myGreeting a rdfop:Greeting ;
  rdfop:message "Hello from RDFOP!" .
```

The template is standard RDFHP: a SPARQL query fetches data, `BEGIN...END` loops over results, and `?>...<?rdf` switches between code and HTML output. The variable `?id` is passed as a request parameter to the component template.

### Wrapper Contract

Every swappable component should render a root element with `class='rdfop-c'` and `data-rdfop-params='...'`. The current runtime uses `data-rdfop-params` rather than the older `data-rdfop-id` / `data-rdfop-prop` pattern.

Typical wrapper:

```html
<div class='rdfop-c'
     data-rdfop-params='{&quot;id&quot;:<?rdf PRINT JSON ?id ?>}'
     data-testid='<?rdf PRINT HTML ?id ?>'>
  <!-- your content here -->
</div>
```

`data-testid` is optional for the UI itself, but useful for the embedded Playwright tests.

### View / Edit Switching

Components are usually switched with:

- `rdfopSwap(el, "view")`
- `rdfopSwap(el, "edit")`

The runtime fetches `/rdfop-render?...` and replaces the current `.rdfop-c` node with freshly rendered HTML. Saving is typically done through `rdfopCommit(...)`, which POSTs DELETE/INSERT Turtle to `/rdfop-save`.

### RDFHP Print Formats

Inside templates, use `PRINT FORMAT ?var` to output values safely:

| Format | Function | Use for |
|--------|----------|---------|
| `RAW` | No escaping | Trusted HTML content |
| `HTML` | Escapes `<>&"` | Text in HTML elements and attributes |
| `JSON` | JSON-encodes with quotes | Data attributes, JavaScript values |
| `URL` | URL-encodes | Query parameters, href attributes |

### JavaScript API

The framework provides these global functions:

| Function | Description |
|----------|-------------|
| `rdfopSwap(el, mode)` | Replace a `.rdfop-c` element with a different component mode |
| `rdfopCommit(btn)` | Save changes (DELETE old + INSERT new triple), then swap to `"view"` |
| `rdfopSave(deleteTtl, insertTtl)` | Low-level triple mutation helper used by many components |
| `rdfopRefreshCanvas()` | Re-render the main canvas while preserving active tabs |

### Server Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/<action>/<id>` | GET | Invoke an RDF-defined resource action; `view` renders the full page shell |
| `/rdfop-render?id=...&mode=...` | GET | Render a component and return HTML |
| `/rdfop-save` | POST | Delete and/or insert triples (`delete=TTL&insert=TTL`) |
| `/rdfop-create` | POST | Create a new child entity under a parent |
| `/rdfop-create-entity` | POST | Create a standalone entity from an `EntityType` and its `initTemplate` |
| `/rdfop-delete` | POST | Delete a subtree by id |
| `/rdfop-source-cleanup` | POST | Server-side cleanup for cross-window drag/drop moves |
| `/rdfop-playwright-tests` | GET | Expose embedded Playwright tests stored in RDF |

### Built-In Layout Components

The current UI is centered around a few self-describing layout primitives:

- `rdfop:ComponentSelector` — palette / placeholder that either shows a palette or a selected child
- `rdfop:Split` / `rdfop:SplitH` / `rdfop:SplitV` — split panes with draggable separator
- `rdfop:TabGroup` / `rdfop:Tab` — tabbed layout with reorderable tabs
- `rdfop:TableView` / `rdfop:TableColumn` / `rdfop:TableAction` — type-based tables with configurable columns, open targets, and toolbar actions
- `rdfop:HTMLView`, `rdfop:Website`, `rdfop:Browser`, `rdfop:Explorer`, `rdfop:Settings`, `rdfop:SPARQLConsole`, `rdfop:TTLImport`

Drag and drop is URI-based. Resource URLs generally follow `/<action>/<id>`.
The current component-drag protocol specifically transports the resource's
`view` action URL; external `http/https` links can be dropped into palettes or
tab bars and are materialized as `rdfop:Website` nodes.

`TableView` instances select rows by `rdfop:itemType`. Their ordered
`rdfop:TableColumn` children name direct RDF properties. `rdfop:openTarget`
can point to a `TabGroup` or to `rdfop:OverlayTarget`; `rdfop:openAction`
selects `rdfop:view` or `rdfop:edit`. Opening the same resource and action in a
tab group activates the existing tab instead of creating a duplicate.
Ordered `rdfop:TableAction` children add any number of toolbar buttons. Each
button has a label plus an `rdfop:action` method and `rdfop:target` resource.
The standard `rdfop:create` action treats its target as an entity type, creates
a standalone instance, refreshes the table, and opens the new row through the
table's configured open target.

## What You Can Build

RDFOP is designed for highly interactive, data-driven apps. With its RDF-first data model, SPARQL queries, and snippet-based SPA UI (AJAX overlays), you can create:

- CRMs: Contacts, companies, pipelines, custom fields, and reports.
- TODO list managers: Tasks, tags, filters, and Kanban views.
- UML chart designers: Diagrams persisted as triples; queryable models.
- Workflow automation tools: Rules, triggers, actions; visual editors.
- Brainstorming canvases: Notes, groups, relations; collaborative sessions.
- Collaborative image editors: Annotations and layers stored in RDF.
- Browser games: Game state and levels expressed as data, rendered via snippets.

## Build Instructions

Build the bundled `memcp` dependency:
```
git clone https://github.com/launix-de/rdfop
cd rdfop
make
```

Then run the server:
```
./run.sh
```

Then open: http://localhost:3443

On startup, RDFOP loads `components.ttl`, which in turn includes the component files under `components/`. `example.ttl` is loaded only for a fresh empty database. You can import additional TTL files via the web UI (`Settings` → `TTL Import`).

## Testing

Playwright is configured to start the app via `./run.sh`:

```bash
npm install
npm run test:playwright
```

The test cases are embedded in the RDF schema itself via `rdfop:PlaywrightTest` and exposed through `/rdfop-playwright-tests`. This makes it possible to keep component-specific regression tests next to the component definitions.

## Vim syntax for Turtle (.ttl)

This repo includes a simple Vim/Neovim syntax highlighter for Turtle files.

- Files: `vim/ftdetect/ttl.vim` and `vim/syntax/ttl.vim`
- Usage (Vim): copy both files to `~/.vim/ftdetect/` and `~/.vim/syntax/`, or add this repo’s `vim/` directory to your `runtimepath`.
- Usage (Neovim): copy to `~/.config/nvim/ftdetect/` and `~/.config/nvim/syntax/`.
- Open any `*.ttl` file to get highlighting (directives, IRIs, QNames, strings, numbers, booleans, comments, etc.).
