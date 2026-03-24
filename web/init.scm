/*

            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
                    Version 2, December 2004

 Copyright (C) 2024  Carl-Philip Hänsch
 Everyone is permitted to copy and distribute verbatim or modified
 copies of this license document, and changing it is allowed as long
 as the name is changed.

            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

  0. You just DO WHAT THE FUCK YOU WANT TO.
*/

/*

template for an app



this module requires to load at least memcp/lib/rdf.scm first; better import memcp/lib/main.scm

*/

/* TODO: move this to rdfop.scm, make it parameterizable (rdfop_serve schema folder port) */

(createdatabase "rdf" true)
(createtable "rdf" "rdf" '('("column" "s" "text" '() '()) '("column" "p" "text" '() '()) '("column" "o" "text" '() '()) '("unique" "u" '("s" "p" "o"))) '() true)

/* schema.ttl: watch + hot-reload (delete old triples, insert new) */
(set _schema_old (newsession))
(watch "../schema.ttl" (lambda (content) (begin
    (set old (_schema_old "ttl"))
    (if (not (nil? old))
        (try (lambda () (delete_ttl "rdf" old)) (lambda (e) (print "schema delete error: " e)))
    )
    (try (lambda () (begin (load_ttl "rdf" content) (_schema_old "ttl" content) (print "schema.ttl reloaded")))
         (lambda (e) (print "schema.ttl load error: " e)))
)))

/* example.ttl: only load if database is empty (no user data yet) */
(set _has_data (newsession))
(define resultrow (lambda (o) (_has_data "found" true)))
(eval (parse_sparql "rdf" "SELECT ?t WHERE { main a ?t }"))
(if (nil? (_has_data "found"))
    (try (lambda () (begin (load_ttl "rdf" (load "../example.ttl")) (print "example.ttl loaded (fresh db)")))
         (lambda (e) (try (lambda () (begin (load_ttl "rdf" (load "example.ttl")) (print "example.ttl loaded (fresh db)"))) (lambda (e2) nil))))
    (print "example.ttl skipped (database has data)")
)

/* custom function for query execution */
(rdf_functions "execute_rdf" (lambda (req res) (begin
    (set q (req "query"))
    (set bodyParts (req "bodyParts"))
    /* extract 'rdf' from query/bodyParts assoc lists */
    (set rdfParam (try (lambda () (reduce_assoc (q) (lambda (acc k v) (if (equal? k "rdf") v acc)) nil)) (lambda (e) nil)))
    (set rdfBody (try (lambda () (reduce_assoc (bodyParts) (lambda (acc k v) (if (equal? k "rdf") v acc)) nil)) (lambda (e) nil)))
    (set rdf (coalesce rdfParam rdfBody "SELECT ?s, ?p, ?o WHERE {?s ?p ?o}"))
	(set print (res "print"))

	/* compile and execute rdf */
    (define formula (try (lambda () (parse_sparql "rdf" rdf)) (lambda (e) (print "<div class='error'>Parser error: <b>" (htmlentities e) "</b></div>"))))
	/*(print "formula=" formula)*/
	(set state (newsession))
	(set print_header (once (lambda (o) (begin
		(state "printed" true)
		(print "<thead><tr>")
		(map_assoc o (lambda (k v) (print "<th>" (htmlentities k) "</th>")))
		(print "</tr></thead><tbody>")
	))))
	(define resultrow (lambda (o) (begin
		(print_header o)
		(print "<tr>")
		(map_assoc o (lambda (k v) (print "<td>" (htmlentities v) "</td>")))
		(print "</tr>")
	)))



	(if (not (nil? formula)) (begin
		(print "<div class='card'><table class='table'>")
		(try (lambda () (eval formula)) (lambda (e) (print "<tr class='error'><th>Error:</th><td>" (htmlentities e) "</td></tr>")))
		(if (state "printed") (print "</tbody>") (print "<tr><td class='empty'>No results.</td></tr>"))
		(print "</table></div>")
	))

	(print "<h3 class='mt-4'>RDF console</h3>")
	(print "<div class='card pad'>")
	(print "<form method='POST' action='rdf' onsubmit='return openOverlaySubmitReplace(this)'>")
    (print "<textarea class='input w-100 h-30vh' name='rdf'>" (htmlentities rdf) "</textarea>")
	(print "<div class='mt-2'>")
	(print "<button class='btn primary' type='button' onclick='return openOverlaySubmitReplace(this.form)'>Execute</button> ")
	(print "<button class='btn' type='button' onclick='return openOverlaySubmit(this.form)'>Open in new overlay</button>")
	(print "</div>")
	(print "</form>")
	(print "</div>")

)))

/* helper: render an RDFHP template string with ?id substituted */
/* template compile cache: compiled formulas keyed by fnv_hash of template string */
(set _tpl_cache (newsession))
(define _compile_tpl (lambda (tpl) (begin
    (set key (fnv_hash tpl))
    (set cached (_tpl_cache key))
    (if (not (nil? cached)) cached (begin
        (define watchnil (lambda (fn cb) nil))
        (set compiled (parse_rdfhp "rdf" (concat "\n" tpl) watchnil))
        (_tpl_cache key compiled)
        compiled
    ))
)))
(define render_rdfhp_template (lambda (tpl id req res) (begin
    (define print (res "print"))
    (try (lambda () (begin
        (define formula (_compile_tpl tpl))
        (eval formula)
    )) (lambda (e) (print (concat "<div class='error'>Template error: <b>" (htmlentities e) "</b></div>"))))
)))

/* component renderer: renders a component for a given subject + mode
   mode defaults to "view" if not provided
   RDFHP usage: CALL render_component("main", REQ, RES)
              or CALL render_component("main", REQ, RES, "edit") */
(rdf_functions "render_component" (lambda (id req res) (begin
    (set print (res "print"))
    (set mode (coalesce (try (lambda () ((req "query") "mode")) (lambda (e) nil)) "view"))
    /* wrap IRIs containing : in angle brackets for SPARQL */
    (set sparql_id (if (match id (regex ":" _) true false) (concat "<" id ">") id))
    (set _rc (newsession))

    /* 1. Try EditorComponent with matching forTypes + componentName */
    (try (lambda () (begin
        (define resultrow (lambda (o) (_rc "tpl" (o "?tpl"))))
        (eval (parse_sparql "rdf" (concat
            "@prefix rdfop: <https://launix.de/rdfop/schema#> . "
            "SELECT ?tpl WHERE { "
            "?comp a rdfop:EditorComponent ; "
            "rdfop:forTypes ?type ; "
            "rdfop:componentName \"" mode "\" ; "
            "rdfop:componentTemplate ?tpl . "
            sparql_id " a ?type }"
        )))
    )) (lambda (e) nil))

    /* 2. Fallback: viewTemplate on the EntityType (legacy, only for mode=view) */
    (if (and (nil? (_rc "tpl")) (equal? mode "view"))
        (try (lambda () (begin
            (define resultrow (lambda (o) (_rc "tpl" (o "?tpl"))))
            (eval (parse_sparql "rdf" (concat
                "SELECT ?tpl WHERE { " sparql_id " a ?t . ?t <https://launix.de/rdfop/schema#viewTemplate> ?tpl }"
            )))
        )) (lambda (e) nil))
    )

    /* 3. Render the template — inject id into query params */
    (if (not (nil? (_rc "tpl"))) (begin
        /* build a req wrapper: copy all original query params, set id + mode */
        (set _q (newsession))
        (try (lambda () (map_assoc ((req "query")) (lambda (k v) (_q k v)))) (lambda (e) nil))
        (_q "id" id)
        (_q "mode" mode)
        (set wrapped_req (newsession))
        (wrapped_req "query" _q)
        (wrapped_req "method" (try (lambda () (req "method")) (lambda (e) "GET")))
        (wrapped_req "body" (try (lambda () (req "body")) (lambda (e) (lambda () ""))))
        (wrapped_req "bodyParts" (try (lambda () (req "bodyParts")) (lambda (e) (lambda () '()))))
        (render_rdfhp_template (_rc "tpl") id wrapped_req res)
    )
        (print "<div class='empty'>Component not found or no view method.</div>")
    )
)))

/* View method: HTMLView(html) — renders raw HTML content */
(rdf_functions "view_HTMLView" (lambda (id req res) (begin
    (set print (res "print"))
    /* Strict: only prefixed schema property */
    (set q (concat "SELECT ?h WHERE { " id " <https://launix.de/rdfop/schema#html> ?h }"))
    (define formula (try (lambda () (parse_sparql "rdf" q)) (lambda (e) (print "<div class='error'>Parser error: <b>" (htmlentities e) "</b></div>") nil)))
    (define resultrow (lambda (o) (if (nil? (o "h")) (print "") (print (o "h")))))
    (if (not (nil? formula)) (eval formula))
)))

/* custom function for TTL import */
(rdf_functions "import_ttl" (lambda (req res) (begin
    (set print (res "print"))
    (set method (req "method"))
    (set q (req "query"))
    /* Prefer decoded bodyParts first (application/x-www-form-urlencoded) */
    (set ttlFromParts (try (lambda () (reduce_assoc ((req "bodyParts")) (lambda (acc k v) (if (equal? k "ttl") v acc)) nil)) (lambda (e) nil)))
    /* Fallback: raw body, supports ttl=... or raw TTL */
    (set rawBody (if (nil? ttlFromParts) (try (lambda () ((req "body"))) (lambda (e) nil)) nil))
    (set ttlFromBody nil)
    (if (and (nil? ttlFromParts) (not (nil? rawBody)) (not (equal? rawBody ""))) (begin
        (match rawBody
            (regex "(^|[&])ttl=([^&]*)" _ _ enc) (set ttlFromBody (urldecode enc))
            rawBody (set ttlFromBody rawBody)
        )
    ))
    (set ttl (coalesce (if (nil? q) nil (q "ttl")) ttlFromParts ttlFromBody))
    (if (equal? method "POST")
        (if (or (nil? ttl) (equal? ttl ""))
            (print "<div class='card pad' style='border-left:4px solid #f59e0b'>No TTL provided.</div>")
            (try
                (lambda ()
                    (begin
                        (set st (newsession))
                        (set lastError nil)
                        (set s (replace ttl "\r\n" "\n"))
                        /* Extract header (@prefix lines) to preserve prefixes */
                        (set header "")
                        (match s
                            (regex "(?ms:^((?:[\t ]*@prefix[^\n]*\n)+))" _ h) (set header h)
                            s nil
                        )
                        /* Try full TTL */
                        (try (lambda () (begin (load_ttl "rdf" ttl) (st "imported" true))) (lambda (e1) (set lastError e1)))
                        /* Also try per-statement import to catch any missed statements */
                        (set parts (split s ".\n"))
                        (define import_part (lambda (p) (begin
                            (set p2 (replace (replace (replace (replace p "\r" "") "\n" "") "\t" "") " " ""))
                            (if (or (nil? p2) (equal? p2 "")) true
                                (try (lambda () (begin (load_ttl "rdf" (concat header p ".\n")) (st "imported" true))) (lambda (e2) (begin (set lastError e2) true)))
                            )
                        )))
                        (map parts import_part)
                        (if (st "imported")
                            (print "<div class='card pad' style='border-left:4px solid #059669'>Imported TTL successfully.</div>")
                            (if (nil? lastError)
                                (print "<div class='card pad' style='border-left:4px solid #f59e0b'>No triples imported.</div>")
                                (print "<div class='card pad' style='border-left:4px solid #b91c1c'><div class='error'>Import error: " (htmlentities lastError) "</div></div>")
                            )
                        )
                    )
                )
                (lambda (e)
                    (print "<div class='card pad' style='border-left:4px solid #b91c1c'><div class='error'>Import error: " (htmlentities e) "</div></div>")
                )
            )
        )
        /* GET (or others): don’t show a status until user submits */
    )
)))

/* AJAX component render: GET /rdfop-render?id=main&mode=edit */
(rdfop_routes "/rdfop-render" (lambda (req res) (begin
    ((res "header") "Content-Type" "text/html")
    ((res "status") 200)
    ((rdf_functions "render_component") ((req "query") "id") req res)
)))

/* POST /rdfop-create — create a new node: parent=ID&type=Tab (returns new node id) */
(rdfop_routes "/rdfop-create" (lambda (req res) (begin
    ((res "header") "Content-Type" "text/plain")
    (set body_raw (try (lambda () ((req "body"))) (lambda (e) "")))
    (set bp (newsession))
    (map (split body_raw "&") (lambda (pair) (begin
        (set parts (split pair "="))
        (set k (urldecode (replace (car parts) "+" " ")))
        (set v (urldecode (replace (coalesce (car (cdr parts)) "") "+" " ")))
        (bp k v)
    )))
    (set parent_id (bp "parent"))
    (set node_type (bp "type"))
    (if (or (nil? parent_id) (nil? node_type)) (begin
        ((res "status") 400)
        ((res "print") "missing parent or type")
    ) (begin
        (set new_id (concat "urn:uuid:" (uuid)))
        /* compute next order number: count existing children */
        (set _cnt (newsession))
        (_cnt "n" 0)
        (set sparql_parent (if (match parent_id (regex ":" _) true false) (concat "<" parent_id ">") parent_id))
        (define resultrow (lambda (o) (_cnt "n" (+ (_cnt "n") 1))))
        (try (lambda () (eval (parse_sparql "rdf" (concat "SELECT ?c WHERE { ?c <https://launix.de/rdfop/schema#parent> " sparql_parent " }")))) (lambda (e) nil))
        (set order (+ (_cnt "n") 1))
        /* build TTL via session to avoid scoping issues */
        (set _t (newsession))
        (_t "ttl" (concat
            "<" new_id "> a <" node_type "> .\n"
            "<" new_id "> <https://launix.de/rdfop/schema#parent> " sparql_parent " .\n"
            "<" new_id "> <https://launix.de/rdfop/schema#order> \"" order "\" .\n"
        ))
        /* type-specific defaults */
        (if (equal? node_type "https://launix.de/rdfop/schema#Tab") (begin
            (set child_id (concat "urn:uuid:" (uuid)))
            (_t "ttl" (concat (_t "ttl")
                "<" new_id "> <https://launix.de/rdfop/schema#tabLabel> \"New Tab\" .\n"
                "<" new_id "> <https://launix.de/rdfop/schema#children> <" child_id "> .\n"
                "<" child_id "> a <https://launix.de/rdfop/schema#HTMLView> .\n"
                "<" child_id "> <https://launix.de/rdfop/schema#parent> <" new_id "> .\n"
                "<" child_id "> <https://launix.de/rdfop/schema#html> \"<p>New tab content</p>\" .\n"
            ))
        ))
        (try (lambda () (load_ttl "rdf" (_t "ttl"))) (lambda (e) (begin ((res "status") 500) ((res "print") (concat "error: " e)))))
        ((res "status") 200)
        ((res "print") new_id)
    ))
)))

/* POST /rdfop-save — receives urlencoded delete=TTL&insert=TTL */
(rdfop_routes "/rdfop-save" (lambda (req res) (begin
    ((res "header") "Content-Type" "text/plain")
    (set body_raw (try (lambda () ((req "body"))) (lambda (e) "")))
    /* parse urlencoded body */
    (set bp (newsession))
    (map (split body_raw "&") (lambda (pair) (begin
        (set parts (split pair "="))
        (set k (urldecode (replace (car parts) "+" " ")))
        (set v (urldecode (replace (coalesce (car (cdr parts)) "") "+" " ")))
        (bp k v)
    )))
    (set del_ttl (bp "delete"))
    (set ins_ttl (bp "insert"))
    /* DELETE triples */
    (if (and (not (nil? del_ttl)) (not (equal? del_ttl "")))
        (try (lambda () (delete_ttl "rdf" del_ttl)) (lambda (e) (print "delete_ttl error: " e)))
    )
    /* INSERT triples */
    (if (and (not (nil? ins_ttl)) (not (equal? ins_ttl "")))
        (try (lambda () (load_ttl "rdf" ins_ttl)) (lambda (e) (print "load_ttl error: " e)))
    )
    ((res "status") 200)
    ((res "print") "ok")
)))

/* template scipt for subpage */
(watch "index.rdfhp" (lambda (content) (rdfop_route "/" "rdf" content watch)))
(watch "index.rdfhp" (lambda (content) (rdfop_route "/index" "rdf" content watch)))
(watch "explorer.rdfhp" (lambda (content) (rdfop_route "/explorer" "rdf" content watch)))
(watch "settings.rdfhp" (lambda (content) (rdfop_route "/settings" "rdf" content watch)))
(watch "ttl-import.rdfhp" (lambda (content) (rdfop_route "/ttl-import" "rdf" content watch)))
(watch "view.rdfhp" (lambda (content) (rdfop_route "/view" "rdf" content watch)))
(watch "rdf.rdfhp" (lambda (content) (rdfop_route "/rdf" "rdf" content watch)))
(watch "component.rdfhp" (lambda (content) (rdfop_route "/component" "rdf" content watch)))

/* handcraftet about page */
(rdfop_routes "/about" (lambda (req res) (begin
	(print "request " req)
	((res "header") "Content-Type" "text/html")
	((res "status") 200)
	((res "print") "<h1>About</h1>
		       visit us on <a href='https://github.com/launix-de/rdfop'>github</a>
		       <br>
		       <a href='index'>back</a>
	")
)))



(serve 3443 http_handler)
(print "")
(print "listening on http://localhost:3443")
(print "")
