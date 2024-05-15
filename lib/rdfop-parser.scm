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

(define rdfhp_statement (parser (or
	(parser '((define loop_header rdf_select) (atom "BEGIN" true) (define loop_body rdfhp_program) (atom "END" true)) '("loop" loop_header loop_body))
	(parser (define select rdf_select) '("select" select))
	(parser '((atom "PRINT" true) (define format (regex "[a-zA-Z0-9_]+")) (define value rdf_expression)) '("print" format value))
)))
(define rdfhp_program (parser (* rdfhp_statement)))

(define rdfhp_filters '("RAW" concat /* TODO: HTML, JSON, SQL */))

(define parse_rdfhp (lambda (schema template) (begin
	/* TODO: parse RDFHP header with parameters */
	(match (ttl_header template) '("prefixes" definitions "rest" body) (begin
		(define compile (lambda (program context) (match program
			(cons '("print" format value) rest) '('begin '('print '((coalesce (rdfhp_filters (toUpper format)) (error "print: unknown format filter: " format)) (rdf_replace_context value context))) (compile rest context))
			'() nil
		)))
		/*(rdf_queryplan (schema query context)*/
		(print "program=" (rdfhp_program body))
		(print "compiled=" (compile (rdfhp_program body) '()))
		(compile (rdfhp_program body) '())
	) (error "could not parse template " template)))
)))