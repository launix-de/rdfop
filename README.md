# RDFOP (aka FOP II)

RDFOP is a feature oriented programming framework based on RDF (resource description format). It is a *universal low code tool* which means you have a WYSIWIG editor and you can edit every aspect of the software. A software is purely described by data in RDF format.

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

RDFOP uses a data-driven component system. Every UI element is described as RDF data — the same way your application data is stored. Components are defined as `rdfop:EditorComponent` instances in Turtle and can be swapped at runtime via AJAX.

### Defining a Component

A component needs three things:

1. **An entity type** — what kind of data it displays
2. **A component name** — `"view"`, `"edit"`, `"view-short"`, or any custom name
3. **An RDFHP template** — server-rendered HTML with SPARQL queries

Here is a minimal read-only component that displays a greeting:

```ttl
@prefix rdfop: <https://launix.de/rdfop/schema#> .

# 1. Define the entity type
rdfop:Greeting a rdfop:EntityType .
rdfop:message a rdf:Property ; rdfs:domain rdfop:Greeting .

# 2. Define the "view" component
rdfop:Greeting_view a rdfop:EditorComponent ;
  rdfop:forTypes rdfop:Greeting ;
  rdfop:componentName "view" ;
  rdfop:componentTemplate """@PREFIX rdfop: <https://launix.de/rdfop/schema#> .
SELECT ?msg WHERE { ?id rdfop:message ?msg }
BEGIN
?><div class='rdfop-c' data-rdfop-id='<?rdf PRINT HTML ?id ?>'>
  <p><?rdf PRINT HTML ?msg ?></p>
</div><?rdf
END""" .

# 3. Create an instance
myGreeting a rdfop:Greeting ;
  rdfop:message "Hello from RDFOP!" .
```

The template is standard RDFHP: a SPARQL query fetches data, `BEGIN...END` loops over results, and `?>...<?rdf` switches between code and HTML output. The variable `?id` is automatically set to the subject being rendered.

### The Component Wrapper

Every component must render a wrapper `<div>` with `class='rdfop-c'` and `data-rdfop-id='...'`. This is how the framework identifies the component for swapping:

```html
<div class='rdfop-c' data-rdfop-id='<?rdf PRINT HTML ?id ?>'>
  <!-- your content here -->
</div>
```

### Adding Edit Support

To make a component editable, define a second `EditorComponent` with `componentName "edit"`. The edit template provides the editing UI and uses data attributes to track the old value for save-back:

```ttl
rdfop:Greeting_edit a rdfop:EditorComponent ;
  rdfop:forTypes rdfop:Greeting ;
  rdfop:componentName "edit" ;
  rdfop:componentTemplate """@PREFIX rdfop: <https://launix.de/rdfop/schema#> .
SELECT ?msg WHERE { ?id rdfop:message ?msg }
BEGIN
?><div class='rdfop-c rdfop-c--editing'
     data-rdfop-id='<?rdf PRINT HTML ?id ?>'
     data-rdfop-prop='https://launix.de/rdfop/schema#message'
     data-rdfop-old='<?rdf PRINT JSON ?msg ?>'>
  <div class='rdfop-edit-toolbar'>
    <button onclick='rdfopCommit(this)'>&#x2714;</button>
    <button onclick='rdfopCancel(this)'>&#x2718;</button>
  </div>
  <textarea class='rdfop-editor'><?rdf PRINT HTML ?msg ?></textarea>
</div><?rdf
END""" .
```

Key attributes on the wrapper div:
- `data-rdfop-id` — the RDF subject being edited
- `data-rdfop-prop` — the full IRI of the property being edited
- `data-rdfop-old` — the original value, JSON-encoded via `PRINT JSON` (needed for DELETE on save)

### Switching Between View and Edit

The view template includes an edit button that triggers `rdfopEdit(this)`:

```html
<button class='rdfop-edit-btn' onclick='rdfopEdit(this)'>&#x270E;</button>
```

This calls `rdfopSwap(element, "edit")` which fetches the edit template from the server and replaces the DOM element. The edit template has save/cancel buttons:

```html
<button onclick='rdfopCommit(this)'>&#x2714;</button>  <!-- save -->
<button onclick='rdfopCancel(this)'>&#x2718;</button>  <!-- cancel -->
```

- **rdfopCommit** reads the textarea value, builds DELETE + INSERT TTL from the old/new values, POSTs to `/rdfop-save`, then swaps back to view.
- **rdfopCancel** simply swaps back to view (re-fetches fresh data from the server).

### Custom Component Names

You can define any number of named components per type. Convention: `"view"` is the default, `"edit"` is the editor. But you can add more:

```ttl
rdfop:Person_viewShort a rdfop:EditorComponent ;
  rdfop:forTypes rdfop:Person ;
  rdfop:componentName "view-short" ;
  rdfop:componentTemplate "..." .
```

Useful for table cells, list items, UML diagram nodes, etc. Call `rdfopSwap(element, "view-short")` to render it.

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
| `rdfopEdit(btn)` | Shorthand: find nearest `.rdfop-c` and swap to `"edit"` |
| `rdfopCancel(btn)` | Shorthand: find nearest `.rdfop-c` and swap to `"view"` |
| `rdfopCommit(btn)` | Save changes (DELETE old + INSERT new triple), then swap to `"view"` |

### Server Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/rdfop-render?id=...&mode=...` | GET | Render a component and return HTML |
| `/rdfop-save` | POST | Delete and/or insert triples (`delete=TTL&insert=TTL`) |

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

At first, you have to make and install rdfhp and memcp:
```
git clone https://github.com/launix-de/rdfop
cd rdfop
make # this clones https://github.com/launix-de/memcp and compiles it
```

Then run the server:
```
./run.sh
```

Then open: http://localhost:3443

`schema.ttl` and `example.ttl` are automatically imported at startup. You can also import additional TTL files via the web UI (Settings menu → TTL import).

## Vim syntax for Turtle (.ttl)

This repo includes a simple Vim/Neovim syntax highlighter for Turtle files.

- Files: `vim/ftdetect/ttl.vim` and `vim/syntax/ttl.vim`
- Usage (Vim): copy both files to `~/.vim/ftdetect/` and `~/.vim/syntax/`, or add this repo’s `vim/` directory to your `runtimepath`.
- Usage (Neovim): copy to `~/.config/nvim/ftdetect/` and `~/.config/nvim/syntax/`.
- Open any `*.ttl` file to get highlighting (directives, IRIs, QNames, strings, numbers, booleans, comments, etc.).
