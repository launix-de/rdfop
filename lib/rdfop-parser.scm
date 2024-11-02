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

(set rdf_include_cache (newsession)) /* in this variable we store the compiled contents of all include files */

(set rdf_functions (newsession)) /* store custom functions here */

/* syntax definition */
(define rdfhp_expression (parser (or
	(parser (atom "REQ" true) 'req)
	(parser (atom "RES" true) 'res)
	rdf_expression
)))
(define rdfhp_statement (parser (or
	(parser '((atom "PARAMETER" true) (define param rdf_variable) (define value rdfhp_expression)) '("param" param value))
	(parser '((define loop_header rdf_select) (atom "BEGIN" true) (define loop_body rdfhp_program) (atom "ELSE" true) (define loop_else rdfhp_program) (atom "END" true)) '("loop" loop_header loop_body loop_else))
	(parser '((define loop_header rdf_select) (atom "BEGIN" true) (define loop_body rdfhp_program) (atom "END" true)) '("loop" loop_header loop_body))
	(parser (define select rdf_select) '("select" select))
	(parser '((atom "PRINT" true) (define format (regex "[a-zA-Z0-9_]+")) (define value rdfhp_expression)) '("print" format value))
	(parser '((atom "?>" true) (define value (regex "(?:[^<]+|<[^?])*")) (or (atom "<?rdf" false) $)) '("print" "RAW" value))
	(parser '((atom "INCLUDE" true) (define filename rdfhp_expression)) '("include" filename))
	(parser '((atom "CALL" true) (define func rdf_constant) "(" (define args (* rdfhp_expression ",")) ")") '("call" func args))
	(parser '((define param rdf_variable) "=" (atom "CALL" true) (define func rdf_constant) "(" (define args (* rdfhp_expression ",")) ")") '("setcall" param func args))
)))
(define rdfhp_program (parser '((define statements (* rdfhp_statement)) (atom "")) statements "^(?:/\\*.*?\\*/|--[^\r\n]*[\r\n]|--[^\r\n]*$|[\r\n\t ]+)+"))

(define rdfhp_filters '(
	"RAW" concat
	"URL" urlencode
	"HTML" htmlentities
	"JSON" json_encode
	"JSONO" json_encode_assoc
	/* TODO: SQL */))

/* compiler */
(define parse_rdfhp (lambda (schema template watch) (begin
	/* TODO: parse RDFHP header with parameters */
	(match (ttl_header template) '("prefixes" definitions "rest" body) (begin
		(define compile (lambda (program context) (match program
			(cons '("param" '('get_var sym) value) rest) '('!begin '('set sym '('('req "query") (rdf_replace_ctx value context))) (compile rest (append context sym sym)))
			(cons '("print" format value) rest) '('!begin '('print '((coalesce (rdfhp_filters (toUpper format)) (error "print: unknown format filter: " format)) (rdf_replace_ctx value context))) (compile rest context))
			(cons '("select" query) rest) '('!begin '('set 'o '('once '('lambda '('f) '('f)))) (rdf_queryplan schema query definitions context (lambda (cols context) '('o '('lambda '() (compile rest context))))))
			(cons '("loop" query body) rest) '('begin '('set 'm '('mutex)) (rdf_queryplan schema query definitions context (lambda (cols context) '('m '('lambda '() (compile body context))))) (compile rest context))
			(cons '("loop" query body else) rest) '('begin '('set 'm '('mutex)) '('set 'o '('once '('lambda '('result) '('if 'result (compile else context))))) (rdf_queryplan schema query definitions context (lambda (cols context) '('!begin '('o false) '('m '('lambda '() (compile body context)))))) '('o true) (compile rest context))
			(cons '("include" filename) rest) (!begin (watch filename (lambda (content) (rdf_include_cache filename (parse_rdfhp schema content watch)))) '('begin '('eval '(rdf_include_cache filename)) (compile rest context)))
			(cons '("call" func args) rest) (if (nil? (rdf_functions func)) (error "unknown function: " func) '('begin (merge '((rdf_functions func)) args) (compile rest context)))
			(cons '("setcall" sym func args) rest) (if (nil? (rdf_functions func)) (error "unknown function: " func) '('begin '('set sym (merge '((rdf_functions func)) args)) (compile rest context)))
			(cons unknown rest) (error "unknown rdfhp statement: " unknown)
			'() nil
		)))
		/*(rdf_queryplan (schema query context)*/
		(print "program=" (rdfhp_program body))
		(print "compiled=" (compile (rdfhp_program body) '()))
		'('begin '('set 'definitions (cons 'list definitions)) (compile (rdfhp_program body) '()))
	) (error "could not parse template " template)))
)))
