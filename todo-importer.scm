(createdatabase "rdf")
(createtable "rdf" "rdf" '('("column" "s" "text" '() "") '("column" "p" "text" '() "") '("column" "o" "text" '() "") '("unique" "u" '("s" "p" "o"))) '() true)
(set test (parse_ttl (load "example.ttl")))
(insert "rdf" "rdf" '("s" "p" "o") (test "facts") true)
