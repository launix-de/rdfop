(createdatabase "rdf" true)
(createtable "rdf" "rdf" '('("column" "s" "text" '() "") '("column" "p" "text" '() "") '("column" "o" "text" '() "") '("unique" "u" '("s" "p" "o"))) '() true)
(set test (parse_ttl (load "example.ttl")))
(insert "rdf" "rdf" '("s" "p" "o") (test "facts") true)
/* select b.o as template from rdf a, rdf b where a.s = 1 and a.p = 'lx:isa' and a.o = b.s and b.p = 'lx:template' */
