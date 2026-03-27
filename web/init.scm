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

/* schema: watch + hot-reload with rdfop:include support */
(set schema_file (arg "schema" "../components.ttl"))
(set _schema_dir (path schema_file "..")) /* directory containing the schema file */
(set _include_watchers (newsession)) /* map: filename -> old ttl content */
(set _include_unwatch (newsession)) /* map: filename -> unwatch callback */

/* startup cleanup: schema triples persist in the DB across restarts, so clear them
   before reloading the current component set */
(define _clear_schema_triples (lambda () (begin
    (scan "rdf" "rdf"
        '("s")
        (lambda (s) (regexp_test s "^https://launix.de/rdfop/schema#"))
        '("$update")
        (lambda ($update) ($update))
        (lambda (a b) b)
        nil
    )
)))

/* deploy a file watcher: watch file, on change delete old triples + insert new */
(define _deploy_include_watcher (lambda (filename) (begin
    (set filepath (path _schema_dir filename))
    (if (not (nil? (_include_watchers filename))) nil /* already watching */
        (begin
            (_include_watchers filename "")
            (_include_unwatch filename (watch filepath (lambda (content) (begin
                (set old (_include_watchers filename))
                (if (and (not (nil? old)) (not (equal? old "")))
                    (try (lambda () (delete_ttl "rdf" old)) (lambda (e) (print "include delete error (" filename "): " e)))
                )
                (try (lambda () (begin (load_ttl "rdf" content) (_include_watchers filename content) (print filename " reloaded")))
                     (lambda (e) (print filename " load error: " e)))
            ))))
            (print "watching " filename)
        )
    )
)))

/* remove a watcher: delete its triples from the store */
(define _remove_include (lambda (filename) (begin
    (set unwatch (_include_unwatch filename))
    (if (not (nil? unwatch))
        (try (lambda () (unwatch)) (lambda (e) (print "include unwatch error (" filename "): " e)))
    )
    (set old (_include_watchers filename))
    (if (and (not (nil? old)) (not (equal? old "")))
        (try (lambda () (delete_ttl "rdf" old)) (lambda (e) (print "include remove error (" filename "): " e)))
    )
    (_include_watchers filename nil)
    (_include_unwatch filename nil)
    (print "unwatched " filename)
)))

/* load the main schema file (components.ttl) with watch + hot-reload */
(set _schema_old (newsession))
(_clear_schema_triples)
(watch schema_file (lambda (content) (begin
    (set old (_schema_old "ttl"))
    (if (not (nil? old))
        (try (lambda () (delete_ttl "rdf" old)) (lambda (e) (print "schema delete error: " e)))
    )
    (try (lambda () (begin (load_ttl "rdf" content) (_schema_old "ttl" content) (print schema_file " reloaded")))
         (lambda (e) (print schema_file " load error: " e)))
    /* scan for rdfop:include triples and deploy watchers */
    (scan "rdf" "rdf" '("p" "o") (lambda (p o) (equal? p "https://launix.de/rdfop/schema#include")) '("o") (lambda (o) (_deploy_include_watcher o)) (lambda (a b) b) nil)
)))

/* triggers: manage include watchers at runtime */
(droptrigger "rdf" "rdfop_include_insert" true)
(createtrigger "rdf" "rdf" "rdfop_include_insert" "after_insert" "" (lambda (old new)
    (if (equal? (new "p") "https://launix.de/rdfop/schema#include")
        (_deploy_include_watcher (new "o"))
    )
) false)

(droptrigger "rdf" "rdfop_include_delete" true)
(createtrigger "rdf" "rdf" "rdfop_include_delete" "after_delete" "" (lambda (old new)
    (if (equal? (old "p") "https://launix.de/rdfop/schema#include")
        (_remove_include (old "o"))
    )
) false)

(droptrigger "rdf" "rdfop_include_update" true)
(createtrigger "rdf" "rdf" "rdfop_include_update" "after_update" "" (lambda (old new)
    (begin
        (if (equal? (old "p") "https://launix.de/rdfop/schema#include")
            (_remove_include (old "o"))
        )
        (if (equal? (new "p") "https://launix.de/rdfop/schema#include")
            (_deploy_include_watcher (new "o"))
        )
    )
) false)

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

/* emit aggregated component assets directly from the RDF store.
   This avoids RDFHP SELECT loop artefacts like stray literal "nil" output
   inside <style>/<script> blocks. */
(define _emit_component_asset (lambda (predicate req res) (begin
    (set print (res "print"))
    (scan "rdf" "rdf"
        '("p" "o")
        (lambda (p o)
            (and
                (equal? p predicate)
                (not (nil? o))
                (not (equal? o "nil"))
            )
        )
        '("o")
        (lambda (o) (begin
            (print o)
            (print "\n")
        ))
        (lambda (a b) b)
        nil
    )
)))
(rdf_functions "emit_component_css" (lambda (req res)
    (_emit_component_asset "https://launix.de/rdfop/schema#css" req res)
))
(rdf_functions "emit_component_js" (lambda (req res)
    (_emit_component_asset "https://launix.de/rdfop/schema#js" req res)
))

(define _parse_urlencoded_body (lambda (body_raw) (begin
    (set bp (newsession))
    (if (not (nil? body_raw)) (map (split body_raw "&") (lambda (pair) (begin
        (set parts (split pair "="))
        (set k (urldecode (replace (car parts) "+" " ")))
        (set v (urldecode (replace (coalesce (car (cdr parts)) "") "+" " ")))
        (bp k v)
    ))))
    bp
)))

(define _rdf_ref (lambda (id)
    (if (or (nil? id) (equal? id "")) nil
        (if (match (concat id) (regex ":" _) true false) (concat "<" id ">") id)
    )
))

(define _query_single_value (lambda (sparql var_name) (begin
    (set _one (newsession))
    (try (lambda () (begin
        (define resultrow (lambda (row) (_one "v" (row var_name))))
        (eval (parse_sparql "rdf" sparql))
    )) (lambda (e) nil))
    (_one "v")
)))

(define _selector_assign_server (lambda (selector_id next_id prev_id) (begin
    (set sid (_rdf_ref selector_id))
    (set del_ttl "")
    (set ins_ttl "")
    (if (and (not (nil? sid)) (not (nil? prev_id))) (begin
        (set del_ttl (concat del_ttl sid " <https://launix.de/rdfop/schema#selectedNode> " (_rdf_ref prev_id) " .\n"))
        (set del_ttl (concat del_ttl sid " <https://launix.de/rdfop/schema#children> " (_rdf_ref prev_id) " .\n"))
    ))
    (if (and (not (nil? sid)) (not (nil? next_id))) (begin
        (set ins_ttl (concat ins_ttl sid " <https://launix.de/rdfop/schema#selectedNode> " (_rdf_ref next_id) " .\n"))
        (set ins_ttl (concat ins_ttl sid " <https://launix.de/rdfop/schema#children> " (_rdf_ref next_id) " .\n"))
    ))
    (if (not (equal? del_ttl "")) (delete_ttl "rdf" del_ttl))
    (if (not (equal? ins_ttl "")) (load_ttl "rdf" ins_ttl))
)))

(define _find_parent_by_child (lambda (child_id)
    (_query_single_value (concat "SELECT ?parent WHERE { ?parent <https://launix.de/rdfop/schema#children> " (_rdf_ref child_id) " } LIMIT 1") "?parent")
))

(define _selector_remove_content_server (lambda (selector_id content_id) (begin
    (_selector_assign_server selector_id nil content_id)
    (set parent_id (_find_parent_by_child selector_id))
    (if (not (nil? parent_id)) (begin
        (set _params (newsession))
        (_params "child" selector_id)
        (_dispatch_action "onChildRemoved" parent_id _params nil)
    ))
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
        (define resultrow (lambda (row) (_rc "tpl" (row "?tpl"))))
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
        (define resultrow (lambda (row) (_rc "comp" (row "?comp"))))
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

/* GET /rdfop-playwright-tests — exposes embedded Playwright tests from the RDF store */
(rdfop_routes "/rdfop-playwright-tests" (lambda (req res) (begin
    ((res "header") "Content-Type" "application/json")
    ((res "status") 200)
    (define _playwright_test_prop (lambda (id prop) (begin
        (set _value (newsession))
        (try (lambda () (begin
            (define resultrow (lambda (o) (_value "v" (o "?v"))))
            (eval (parse_sparql "rdf" (concat
                "SELECT ?v WHERE { <" id "> <" prop "> ?v } LIMIT 1"
            )))
        )) (lambda (e) nil))
        (_value "v")
    )))
    (set _first (newsession))
    (_first "v" true)
    ((res "print") "[")
    (define resultrow (lambda (o) (begin
        (set test_id (o "?id"))
        (set label (coalesce (_playwright_test_prop test_id "http://www.w3.org/2000/01/rdf-schema#label") test_id))
        (set target (_playwright_test_prop test_id "https://launix.de/rdfop/schema#testFor"))
        (set ord (coalesce (_playwright_test_prop test_id "https://launix.de/rdfop/schema#order") ""))
        (set code (_playwright_test_prop test_id "https://launix.de/rdfop/schema#playwright"))
        (if (_first "v") (_first "v" false) ((res "print") ","))
        ((res "print") "{"
            "\"id\":" (json_encode test_id) ","
            "\"label\":" (json_encode label) ","
            "\"for\":" (json_encode target) ","
            "\"order\":" (json_encode ord) ","
            "\"code\":" (json_encode code)
        "}")
    )))
    (eval (parse_sparql "rdf" "SELECT ?id WHERE { ?id a <https://launix.de/rdfop/schema#PlaywrightTest> }"))
    ((res "print") "]")
)))

/* POST /rdfop-source-cleanup — server-side cleanup of the drag source.
   This is used by receivers so moves also work across windows/contexts. */
(rdfop_routes "/rdfop-source-cleanup" (lambda (req res) (begin
    ((res "header") "Content-Type" "text/plain")
    (set bp (_parse_urlencoded_body (try (lambda () ((req "body"))) (lambda (e) ""))))
    (set source_kind (bp "sourceKind"))
    (set selector_id (bp "sourceSelectorId"))
    (set tab_id (bp "sourceTabId"))
    (set child_id (bp "sourceChildId"))
    (set content_id (bp "sourceContentId"))
    (set replacement_id (bp "replacementId"))
    (set leave_source_palette (or (equal? (bp "leaveSourcePalette") "true") (equal? (bp "leaveSourcePalette") "1")))
    (if (equal? source_kind "selector") (begin
        (if (or (nil? selector_id) (nil? content_id)) (begin
            ((res "status") 400)
            ((res "print") "missing selector source")
        ) (begin
            (if leave_source_palette
                (_selector_assign_server selector_id nil content_id)
                (if (and (not (nil? replacement_id)) (not (equal? replacement_id content_id)))
                    (_selector_assign_server selector_id replacement_id content_id)
                    (_selector_remove_content_server selector_id content_id)
                )
            )
            ((res "status") 200)
            ((res "print") "ok")
        ))
    ) (if (equal? source_kind "tab") (begin
        (if (or (nil? tab_id) (nil? child_id) (nil? content_id)) (begin
            ((res "status") 400)
            ((res "print") "missing tab source")
        ) (begin
            (if (and leave_source_palette (not (equal? child_id content_id)))
                (_selector_assign_server child_id nil content_id)
                (if (equal? child_id content_id) (begin
                    (set _params (newsession))
                    (_params "child" child_id)
                    (_dispatch_action "onChildRemoved" tab_id _params nil)
                ) (_selector_remove_content_server child_id content_id))
            )
            ((res "status") 200)
            ((res "print") "ok")
        ))
    ) (begin
        ((res "status") 400)
        ((res "print") "missing or unknown sourceKind")
    )))
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
        /* order = max(existing sibling order) + 1 so new items append at the end */
        (set _order_max (newsession))
        (_order_max "n" 0)
        (try (lambda () (begin
            (define resultrow (lambda (row) (begin
                (set ord_raw (row "?ord"))
                (set ord_num (try (lambda () (simplify ord_raw)) (lambda (e) nil)))
                (if (and (not (nil? ord_num)) (> ord_num (_order_max "n")))
                    (_order_max "n" ord_num)
                )
            )))
            (eval (parse_sparql "rdf" (concat
                "SELECT ?ord WHERE { "
                /* RDFOP planner gap: scan rdfop:order first, then join back to the parent. */
                "?child <https://launix.de/rdfop/schema#order> ?ord . "
                sparql_parent " <https://launix.de/rdfop/schema#children> ?child }"
            )))
        )) (lambda (e) nil))
        (set order (simplify (+ (_order_max "n") 1)))
        /* base triples: type, children link from parent, order */
        (set base_ttl (concat
            "<" new_id "> a <" node_type "> .\n"
            sparql_parent " <https://launix.de/rdfop/schema#children> <" new_id "> .\n"
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
