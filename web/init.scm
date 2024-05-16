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
(createtable "rdf" "rdf" '('("column" "s" "text" '() "") '("column" "p" "text" '() "") '("column" "o" "text" '() "") '("unique" "u" '("s" "p" "o"))) '() true)

(load_ttl "rdf" (load "example.ttl")) /* read example ttl file */

/* handcraftet main page */
(rdfop_routes "/" (lambda (req res) (begin
	(print "request " req)
	((res "header") "Content-Type" "text/html")
	((res "status") 200)
	((res "print") "<h1>Welcome</h1>Go to <a href='example'>Example page</a>")
)))

/* template scipt for subpage */
(rdfop_route "/example" "rdf" (load "example.rdfhp"))


(serve 3443 http_handler)
(print "")
(print "listening on http://localhost:3443")
(print "")

