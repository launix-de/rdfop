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

/* load base schema + example data */
(try (lambda () (load_ttl "rdf" (load "schema.ttl"))) (lambda (e) (print "")))
(load_ttl "rdf" (load "example.ttl")) /* read example ttl file */

/* custom function for query execution */
(rdf_functions "execute_rdf" (lambda (req res) (begin
    (set q (req "query"))
    (set bodyParts (req "bodyParts"))
    (set rdf (coalesce (if (nil? q) nil (q "rdf")) (if (nil? bodyParts) nil (bodyParts "rdf"))))
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
        /* Try mapping via RDF: t viewFunction ?f */
        (set fn (try (lambda () (begin
            (set qmap (concat "SELECT ?f WHERE { " t " viewFunction ?f }"))
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
    )))
    (if (not (nil? formula)) (eval formula))
    /* Fallback: raw HTML if html property is present */
    (if (not printed) (begin
        (set q2 (concat "SELECT ?h WHERE { " id " html ?h }"))
        (define formula2 (try (lambda () (parse_sparql "rdf" q2)) (lambda (e) nil)))
        (define resultrow (lambda (o) (begin (set printed true) (if (nil? (o "h")) (print "") (print (o "h"))))))
        (if (not (nil? formula2)) (eval formula2))
    ))
    (if (not printed)
        (print "<div class='empty'>Component not found or no view method.</div>")
    )
)))

/* View method: HTMLView(html) — renders raw HTML content */
(rdf_functions "view_HTMLView" (lambda (id req res) (begin
    (set print (res "print"))
    (set q (concat "SELECT ?h WHERE { " id " html ?h }"))
    (define formula (try (lambda () (parse_sparql "rdf" q)) (lambda (e) (begin (print "<div class='error'>Parser error: <b>" (htmlentities e) "</b></div>") nil))))
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
                    /* robust import: allow multiple statements separated by ".\n" */
                    (set s (replace ttl "\r\n" "\n"))
                    (set parts (split s ".\n"))
                    (define import_part (lambda (p) (if (or (nil? p) (equal? p "")) true (load_ttl "rdf" (concat p ".\n")))))
                    (map parts import_part)
                    (print "<div class='card pad' style='border-left:4px solid #059669'>Imported TTL successfully.</div>")
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
