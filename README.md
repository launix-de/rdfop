# rdfop - Resource Description Format Oriented Programming

RDFOP is a template renderer for various RDF based formats. In a rule manager, template rules can be put over RDF items.

## The .rdfhp format

RDFHP stands for RDF hypertext preprocessor and has the following syntax:

```
PARAMETER ?page "page" // reads GET parameter "page" into ?page
PREFIX lx <https://launix.de/rdf/#>
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

## Build Instructions

At first, you have to make and install rdfhp and memcp:
```
git clone https://github.com/launix-de/rdfop
cd rdfop

git clone https://github.com/launix-de/memcp
make -C memcp # install go if you haven't go installed on your computer
```

Then run the server:
```
./memcp/memcp memcp/lib/rdf.scm lib/rdfop.scm web/init.scm # load with only rdf lib from memcp, rdfop and our web app
```
