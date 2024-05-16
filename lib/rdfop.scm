/*
Copyright (C) 2024  Carl-Philip Hänsch

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

(import "rdfop-parser.scm")

(define rdfop_routes (newsession)) /* the list of all routes */
/* call this function to register a new template under the specified path */
(define rdfop_route (lambda (path schema template) (begin
	/* compile template */
	(define formula (parse_rdfhp schema template))

	(define handle_query (lambda (req res) (begin
		/* check for password */
		((res "header") "Content-Type" "text/html")
		((res "status") 200)
		(print "RDFOP query: " req)

		(define print (res "print"))

		(eval formula)
	)))
	(rdfop_routes path handle_query) /* register to router */
	(print "registered router: " path)
)))

(define http_handler (begin
	(set old_handler (coalesce http_handler handler_404))

	/* simple router for all handlers */
	(lambda (req res) (begin
		/* hooked our additional paths to it */
		(set handler (rdfop_routes (req "path")))
		(if (nil? handler) (old_handler req res) (handler req res))
	))
))
