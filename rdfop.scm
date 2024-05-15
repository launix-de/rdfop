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

(define rdfop_routes (newsession))
(define rdfop_route (lambda (path template) (begin
	/* TODO: compile template */

	(define handle_query (lambda (req res) (begin
		/* check for password */
		((res "header") "Content-Type" "text/html")
		((res "status") 200)
		(print "RDFOP query: " req)
		(define formula (parse_sparql schema query))
		(define resultrow (res "jsonl"))
		(define session (newsession))

		(eval formula)
	)))
	(rdfop_routes path handle_query) /* register to router */
)))

(define http_handler (begin
	(set old_handler http_handler)

	/* simple router for all handlers */
	(lambda (req res) (begin
		/* hooked our additional paths to it */
		(set handler (rdfop_routes (req "path")))
		(if handler (handler req res) (old_handler req res))
	))
))
