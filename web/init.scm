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

/* simple loader */
/* intentionally no robustness here; memcp/load_ttl should handle multi-statements */

/* load base schema + example data (from project root) */
(try (lambda () (load_ttl "rdf" (load "../schema.ttl"))) (lambda (e)
    (try (lambda () (load_ttl "rdf" (load "schema.ttl"))) (lambda (e2) (print "")))
))
(try (lambda () (load_ttl "rdf" (load "../example.ttl"))) (lambda (e)
    (try (lambda () (load_ttl "rdf" (load "example.ttl"))) (lambda (e2) (print "")))
))

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

/* component renderer: dispatch by type and call registered view method */
(rdf_functions "render_component" (lambda (id req res) (begin
    (set print (res "print"))
    (set printed false)

    /* Resolve all rdf types for id, then try view_<Type>(id, req, res) */
    (set q (concat "SELECT ?t WHERE { " id " a ?t }"))
    (define formula (try (lambda () (parse_sparql "rdf" q)) (lambda (e) (begin (print "<div class='error'>Parser error: <b>" (htmlentities e) "</b></div>") nil))))
    (define resultrow (lambda (o) (begin
        (set t (o "t"))
        /* Prefer data-defined RDFHP template: t viewTemplate ?tpl */
        (set tpl nil)
        (try (lambda () (begin
            (set qtpl (concat "SELECT ?tpl WHERE { " id " a ?t . ?t <https://launix.de/rdfop/schema#viewTemplate> ?tpl }"))
            (define resultrow (lambda (o3) (set tpl (o3 "tpl"))))
            (define ftpl (parse_sparql "rdf" qtpl))
            (eval ftpl)
        )) (lambda (e) nil))
        (if (not (nil? tpl)) (begin
            (set printed true)
            (set tpl2 (concat "\n" (replace tpl "?id" id)))
            (define watchnil (lambda (fn cb) nil))
            (define formula (try (lambda () (parse_rdfhp "rdf" tpl2 watchnil)) (lambda (e) (print "<div class='error'>Template error: <b>" (htmlentities e) "</b></div>"))))
            (if (not (nil? formula)) (eval formula))
        ) (begin
            /* Try mapping via RDF: t viewFunction ?f */
            (set fn (try (lambda () (begin
                (set qmap (concat "SELECT ?f WHERE { " id " a ?t . ?t <https://launix.de/rdfop/schema#viewFunction> ?f }"))
                (set f nil)
                (define resultrow (lambda (o2) (set f (o2 "f"))))
                (define fm (parse_sparql "rdf" qmap))
                (eval fm)
                (if (nil? f) (concat "view_" t) (concat "view_" f))
            )) (lambda (e) (concat "view_" t))))
            (set handler (rdf_functions fn))
            (if (nil? handler) nil (begin
                (set printed true)
                (handler id req res)
            ))
        ))
    )))
    (if (not (nil? formula)) (eval formula))
    /* No legacy fallback: require schema-backed templates or view methods */
    (if (not printed)
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
