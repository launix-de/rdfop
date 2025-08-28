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

(load_ttl "rdf" (load "example.ttl")) /* read example ttl file */

/* custom function for query execution */
(rdf_functions "execute_rdf" (lambda (req res) (begin
    (set bodyParts (req "bodyParts"))
    (set rdf (coalesce (if (nil? bodyParts) nil (bodyParts "rdf")) (((req "query")) "rdf")))
	(set print (res "print"))

	/* compile and execute rdf */
	(define formula (try (lambda () (parse_sparql "rdf" rdf)) (lambda (e) (print "Parser error: <b>" (htmlentities e) "</b>"))))
	/*(print "formula=" formula)*/
	(set print_header (once (lambda (o) (begin
		(print "<tr>")
		(map_assoc o (lambda (k v) (print "<th>" (htmlentities k) "</th>")))
		(print "</tr>")
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
		(print "</table></div>")
	))

	(print "<h3 class='mt-4'>RDF console</h3>")
	(print "<div class='card pad'>")
	(print "<form class='overlay-form' method='POST' action='rdf'>")
	(print "<textarea class='input w-100 h-30vh' name='rdf'>" (htmlentities rdf) "</textarea>")
	(print "<div class='mt-2'><button class='btn primary' type='submit'>Execute</button></div>")
	(print "</form>")
	(print "</div>")

)))

/* template scipt for subpage */
(watch "index.rdfhp" (lambda (content) (rdfop_route "/" "rdf" content watch)))
(watch "index.rdfhp" (lambda (content) (rdfop_route "/index" "rdf" content watch)))
(watch "explorer.rdfhp" (lambda (content) (rdfop_route "/explorer" "rdf" content watch)))
(watch "settings.rdfhp" (lambda (content) (rdfop_route "/settings" "rdf" content watch)))
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
