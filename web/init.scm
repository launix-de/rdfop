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
		(map_assoc o (lambda (k v) (begin (print "<td>") ((rdf_functions "render_link") v req res) (print "</td>"))))
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

/* rdfop_action(actionName, entityId, extraKey, extraVal, req, res)
   generic action dispatch — looks up rdfop:<actionName> on entity's type,
   executes RDFHP snippet with ?id=entityId and ?<extraKey>=extraVal */
(rdf_functions "rdfop_action" (lambda (action_name entity_id extra_key extra_val req res) (begin
    (set sparql_id (if (match (concat entity_id) (regex ":" _) true false) (concat "<" entity_id ">") entity_id))
    (set _rc (newsession))
    (try (lambda () (begin
        (define resultrow (lambda (o) (_rc "tpl" (o "?tpl"))))
        (eval (parse_sparql "rdf" (concat
            "SELECT ?tpl WHERE { " sparql_id " a ?type . ?type <https://launix.de/rdfop/schema#" action_name "> ?tpl } LIMIT 1"
        )))
    )) (lambda (e) nil))
    (if (not (nil? (_rc "tpl"))) (begin
        (set _q (newsession))
        (_q "id" entity_id)
        (if (not (nil? extra_key)) (_q extra_key extra_val))
        (set req (newsession))
        (req "query" _q)
        (set print (lambda (x) nil))
        (define resultrow (lambda (o) nil))
        (eval (_compile_tpl (concat "@PREFIX rdfop: <https://launix.de/rdfop/schema#> .\nPARAMETER ?id \"id\"\nPARAMETER ?" extra_key " \"" extra_key "\"\n" (_rc "tpl"))))
    ))
)))

/* render_link(value, req, res) — CALL render_link(?val, REQ, RES)
   renders typed entities as clickable links, plain values as text */
(set _render_link_tpl (parse_rdfhp "rdf" "
PARAMETER ?value \"value\"
SELECT ?t WHERE { ?value a ?t }
BEGIN
?><a href='#' data-rdfop-params='{&quot;id&quot;:<?rdf PRINT JSON ?value ?>}' onclick='event.preventDefault();rdfopOverlay(this)'><?rdf PRINT HTML ?value ?></a><?rdf
ELSE
PRINT HTML ?value
END
" (lambda (fn cb) nil)))
(rdf_functions "render_link" (lambda (value req res) (begin
    (set _q (newsession))
    (_q "value" value)
    (set req (newsession))
    (req "query" _q)
    (set print (res "print"))
    (eval _render_link_tpl)
)))

/* === Component rendering ===
   render_component(component_iri, req, res)
     — the core: looks up template by component IRI, renders with req params
   render_object(id, req, res)
     — convenience: finds type of id, looks up component via mode predicate,
       then delegates to render_component
   RDFHP usage: CALL render_object("main", REQ, RES)
*/

/* render_component: render a specific EditorComponent by its IRI */
(rdf_functions "render_component" (lambda (comp_iri req res) (begin
    (set print (res "print"))
    (set sparql_comp (if (match (concat comp_iri) (regex ":" _) true false) (concat "<" comp_iri ">") comp_iri))
    (set _rc (newsession))
    (try (lambda () (begin
        (define resultrow (lambda (o) (_rc "tpl" (o "?tpl"))))
        (eval (parse_sparql "rdf" (concat
            "SELECT ?tpl WHERE { " sparql_comp " <https://launix.de/rdfop/schema#componentTemplate> ?tpl }"
        )))
    )) (lambda (e) nil))
    (if (not (nil? (_rc "tpl")))
        (render_rdfhp_template (_rc "tpl") comp_iri req res)
        (print "<div class='empty'>Component not found: " (htmlentities comp_iri) "</div>")
    )
)))

/* render_object: resolve type + mode predicate → component, then render */
(rdf_functions "render_object" (lambda (id req res) (begin
    (set print (res "print"))
    (set mode (coalesce (try (lambda () ((req "query") "mode")) (lambda (e) nil)) "view"))
    (set sparql_id (if (match (concat id) (regex ":" _) true false) (concat "<" id ">") id))
    (set _rc (newsession))

    /* find component: ?type <mode_predicate> ?component where id a ?type */
    (set mode_pred (concat "<https://launix.de/rdfop/schema#" mode ">"))
    (try (lambda () (begin
        (define resultrow (lambda (o) (_rc "comp" (o "?comp"))))
        (eval (parse_sparql "rdf" (concat
            "SELECT ?comp WHERE { " sparql_id " a ?type . ?type " mode_pred " ?comp }"
        )))
    )) (lambda (e) nil))

    (if (not (nil? (_rc "comp"))) (begin
        /* build wrapped req with id + original params */
        (set _q (newsession))
        (try (lambda () (map_assoc (req "query") (lambda (k v) (_q k v)))) (lambda (e) nil))
        (_q "id" id)
        (_q "mode" mode)
        (set wrapped_req (newsession))
        (wrapped_req "query" _q)
        (wrapped_req "method" (try (lambda () (req "method")) (lambda (e) "GET")))
        (wrapped_req "body" (try (lambda () (req "body")) (lambda (e) (lambda () ""))))
        (wrapped_req "bodyParts" (try (lambda () (req "bodyParts")) (lambda (e) (lambda () '()))))
        ((rdf_functions "render_component") (_rc "comp") wrapped_req res)
    )
        (print "<div class='empty'>No component for " (htmlentities id) " mode=" (htmlentities mode) "</div>")
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
    (set comp (try (lambda () ((req "query") "comp")) (lambda (e) nil)))
    (if comp
        ((rdf_functions "render_component") comp req res)
        ((rdf_functions "render_object") ((req "query") "id") req res)
    )
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
        (set sparql_parent (if (match (concat parent_id) (regex ":" _) true false) (concat "<" parent_id ">") parent_id))
        /* order = unix timestamp so new items sort to the end */
        (set order (format_date (now) "%Y%m%d%H%i%s"))
        /* base triples: type, parent, order */
        (set base_ttl (concat
            "<" new_id "> a <" node_type "> .\n"
            "<" new_id "> <https://launix.de/rdfop/schema#parent> " sparql_parent " .\n"
            "<" new_id "> <https://launix.de/rdfop/schema#order> \"" order "\" .\n"
        ))
        /* look up initTemplate from the EntityType */
        (set _it (newsession))
        (try (lambda () (begin
            (define resultrow (lambda (o) (_it "tpl" (o "?tpl"))))
            (eval (parse_sparql "rdf" (concat "SELECT ?tpl WHERE { <" node_type "> <https://launix.de/rdfop/schema#initTemplate> ?tpl }")))
        )) (lambda (e) nil))
        /* expand initTemplate: replace $ID with new_id, generate UUIDs for _:blanks */
        (set extra_ttl (if (nil? (_it "tpl")) "" (replace (_it "tpl") "$ID" (concat "<" new_id ">"))))
        (try (lambda () (load_ttl "rdf" (concat base_ttl extra_ttl))) (lambda (e) (begin ((res "status") 500) ((res "print") (concat "error: " e)))))
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

/* POST /rdfop-delete — deletes a node and its children recursively */
(rdfop_routes "/rdfop-delete" (lambda (req res) (begin
    ((res "header") "Content-Type" "text/plain")
    (set body_raw (try (lambda () ((req "body"))) (lambda (e) "")))
    (set bp (newsession))
    (map (split body_raw "&") (lambda (pair) (begin
        (set parts (split pair "="))
        (set k (urldecode (replace (car parts) "+" " ")))
        (set v (urldecode (replace (coalesce (car (cdr parts)) "") "+" " ")))
        (bp k v)
    )))
    (set node_id (bp "id"))
    (if (nil? node_id) (begin ((res "status") 400) ((res "print") "missing id"))
    (begin
        /* recursive delete: collect all triples where node is subject, then recurse into children */
        (set _del (newsession))
        (_del "delete_node" (lambda (id) (begin
            (set sparql_id (if (match (concat id) (regex ":" _) true false) (concat "<" id ">") id))
            /* find and delete children first */
            (set _ch (newsession))
            (_ch "children" '())
            (try (lambda () (begin
                (define resultrow (lambda (o) (_ch "children" (cons (o "?child") (_ch "children")))))
                (eval (parse_sparql "rdf" (concat "SELECT ?child WHERE { " sparql_id " <https://launix.de/rdfop/schema#children> ?child }")))
            )) (lambda (e) nil))
            (map (_ch "children") (lambda (child) ((_del "delete_node") child)))
            /* delete all triples where this node is subject */
            (scan "rdf" "rdf" '("s") (lambda (s) (equal? s id)) '("$update") (lambda ($update) ($update)) (lambda (a b) b) nil)
            /* delete parent's children link to this node */
            (scan "rdf" "rdf" '("p" "o") (lambda (p o) (and (equal? p "https://launix.de/rdfop/schema#children") (equal? o id))) '("$update") (lambda ($update) ($update)) (lambda (a b) b) nil)
        )))
        ((_del "delete_node") node_id)
        ((res "status") 200)
        ((res "print") "ok")
    ))
)))

/* _dispatch_action: shared by HTTP router and rdfop_action rdf_function
   returns true if action was found+executed, false otherwise */
(define _dispatch_action (lambda (action id query_params res) (begin
    (set sparql_id (if (match (concat id) (regex ":" _) true false) (concat "<" id ">") id))
    (set _rc (newsession))
    (try (lambda () (begin
        (define resultrow (lambda (o) (_rc "tpl" (o "?tpl"))))
        (eval (parse_sparql "rdf" (concat
            "SELECT ?tpl WHERE { <https://launix.de/rdfop/schema#" action "> a <https://launix.de/rdfop/schema#Method> . " sparql_id " a ?type . ?type <https://launix.de/rdfop/schema#" action "> ?tpl } LIMIT 1"
        )))
    )) (lambda (e) nil))
    (if (nil? (_rc "tpl")) false (begin
        (set _q (newsession))
        (_q "id" id)
        (if (not (nil? query_params)) (try (lambda () (map_assoc query_params (lambda (k v) (_q k v)))) (lambda (e) nil)))
        (set req (newsession))
        (req "query" _q)
        (set print (if (nil? res) (lambda (x) nil) (res "print")))
        (define resultrow (lambda (o) nil))
        (eval (_compile_tpl (concat "@PREFIX rdfop: <https://launix.de/rdfop/schema#> .\n@PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#> .\nPARAMETER ?id \"id\"\n" (_rc "tpl"))))
        true
    ))
)))

/* rdfop_action(actionName, entityId, key1, val1, key2, val2, ...)
   internal action dispatch — callable from RDFHP via CALL */
(rdf_functions "rdfop_action" (lambda args (begin
    (set action_name (car args))
    (set entity_id (car (cdr args)))
    (set rest (cdr (cdr args)))
    /* build params from key-value pairs */
    (set _params (newsession))
    (define _parse_pairs (lambda (lst) (match lst
        (cons k (cons v tail)) (begin (_params k v) (_parse_pairs tail))
        '() nil
    )))
    (_parse_pairs rest)
    (_dispatch_action action_name entity_id _params nil)
)))

/* /{action}/{id} — generic HTTP action dispatch */
(define http_handler (begin
    (set _old_handler http_handler)
    (lambda (req res) (begin
        (set path (req "path"))
        (match path (regex "^/([a-zA-Z][a-zA-Z0-9_]*)/(.+)" _ action id) (begin
            (set id (urldecode id))
            /* view: special case — wrap in page template */
            (if (equal? action "view") (begin
                (set _q (newsession))
                (try (lambda () (map_assoc (req "query") (lambda (k v) (_q k v)))) (lambda (e) nil))
                (_q "id" id)
                (set wrapped_req (newsession))
                (wrapped_req "query" _q)
                (wrapped_req "method" (req "method"))
                (wrapped_req "path" (req "path"))
                (wrapped_req "body" (try (lambda () (req "body")) (lambda (e) (lambda () ""))))
                (wrapped_req "bodyParts" (try (lambda () (req "bodyParts")) (lambda (e) (lambda () '()))))
                (set handler (rdfop_routes "/view"))
                (if handler (handler wrapped_req res) (_old_handler req res))
            ) (begin
                /* other actions: dispatch via _dispatch_action */
                ((res "header") "Content-Type" "text/plain")
                (if (_dispatch_action action id (req "query") res) (begin
                    ((res "status") 200)
                    ((res "print") "ok")
                ) (begin
                    ((res "status") 404)
                    ((res "print") (concat "action not found: " action " for " id))
                ))
            ))
        ) (_old_handler req res))
    ))
))

/* / redirects to /view/main */
(rdfop_routes "/" (lambda (req res) (begin
    ((res "header") "Location" "/view/main")
    ((res "status") 302)
)))
(watch "index.rdfhp" (lambda (content) (rdfop_route "/view" "rdf" content watch)))
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
