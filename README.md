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

From the server console, you can import `.ttl` files via:
```
(load_ttl "rdf" (stream "example.ttl"))
```
