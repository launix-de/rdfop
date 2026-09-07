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
    (scan nil (table "rdf" "rdf")
        '(369435906932736)
        '()
        '("s")
        (lambda (s) (regexp_test s "^https://launix.de/rdfop/schema#"))
        '("$update")
        (lambda (acc $update) (begin ($update) acc))
        nil
    )
)))

/* memcp's current delete_ttl helper emits scan_boundary calls that are not
   available in every RDF runtime build. Keep RDFOP deletes functional with a
   full table scan until the shared RDF planner provides that primitive. */
(define _rdfop_delete_ttl (lambda (schema ttl) (begin
    (set triples (parse_ttl_triples schema ttl))
    (map triples (lambda (triple) (match triple '(subj pred obj)
        (scan nil (table schema "rdf") '(369435906932736) '()
            '("s" "p" "o")
            (lambda (s p o) (and (equal? s subj) (equal? p pred) (equal? o obj)))
            '("$update")
            (lambda (acc $update) (begin ($update) acc))
            nil)
    )))
    nil
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
                    (try (lambda () (_rdfop_delete_ttl "rdf" old)) (lambda (e) (print "include delete error (" filename "): " e)))
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
        (try (lambda () (_rdfop_delete_ttl "rdf" old)) (lambda (e) (print "include remove error (" filename "): " e)))
    )
    (_include_watchers filename nil)
    (_include_unwatch filename nil)
    (print "unwatched " filename)
)))

/* load the main schema file (components.ttl) with watch + hot-reload */
(set _schema_old (newsession))
/* Persist multiline triggers across restarts. Remove the previous generation
   before deleting schema triples so include-delete callbacks cannot recurse
   into the cleanup scan. */
(droptrigger "rdf" "rdfop_include_insert" true)
(droptrigger "rdf" "rdfop_include_delete" true)
(droptrigger "rdf" "rdfop_include_update" true)
(_clear_schema_triples)
(watch schema_file (lambda (content) (begin
    (set old (_schema_old "ttl"))
    (if (not (nil? old))
        (try (lambda () (_rdfop_delete_ttl "rdf" old)) (lambda (e) (print "schema delete error: " e)))
    )
    (try (lambda () (begin (load_ttl "rdf" content) (_schema_old "ttl" content) (print schema_file " reloaded")))
         (lambda (e) (print schema_file " load error: " e)))
    /* scan for rdfop:include triples and deploy watchers */
    (scan nil (table "rdf" "rdf") '(369435906932736) '()
        '("p" "o") (lambda (p o) (equal? p "https://launix.de/rdfop/schema#include"))
        '("o") (lambda (acc o) (begin (_deploy_include_watcher o) acc)) nil)
)))

/* triggers: manage include watchers at runtime */
(droptrigger "rdf" "rdfop_include_insert" true)
(createtrigger (table "rdf" "rdf") "rdfop_include_insert" "after_insert" "" "" (lambda (old new)
    (if (equal? (new "p") "https://launix.de/rdfop/schema#include")
        (_deploy_include_watcher (new "o"))
    )
) false)

(droptrigger "rdf" "rdfop_include_delete" true)
(createtrigger (table "rdf" "rdf") "rdfop_include_delete" "after_delete" "" "" (lambda (old new)
    (if (equal? (old "p") "https://launix.de/rdfop/schema#include")
        (_remove_include (old "o"))
    )
) false)

(droptrigger "rdf" "rdfop_include_update" true)
(createtrigger (table "rdf" "rdf") "rdfop_include_update" "after_update" "" "" (lambda (old new)
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
    (set rdfParam (_assoc_get_value q "rdf"))
    (set rdfBody (_assoc_get_value bodyParts "rdf"))
    (set rdf (coalesce rdfParam rdfBody "SELECT ?s, ?p, ?o WHERE {?s ?p ?o}"))
	(set print (res "print"))

	/* compile and execute rdf */
    (define formula (try (lambda () (parse_sparql "rdf" rdf)) (lambda (e) (print "<div class='error'>Parser error: <b>" (htmlentities e) "</b></div>"))))
	/*(print "formula=" formula)*/
	(set state (newsession))
	(set print_header (once (lambda (row) (begin
		(state "printed" true)
		(print "<thead><tr>")
		(map_assoc row (lambda (k v) (print "<th>" (htmlentities k) "</th>")))
		(print "</tr></thead><tbody>")
	))))

	(define resultrow (lambda (row) (begin
		(print_header row)
		(print "<tr>")
		(map_assoc row (lambda (k v) (begin
			(print "<td>")
			((rdf_functions "render_link") v req res)
			(print "</td>")
		)))
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

	(define _assoc_get_value (lambda (assoc key) (begin
		(set source (try (lambda () (assoc)) (lambda (e) assoc)))
		(try (lambda () (reduce_assoc source (lambda (acc k v) (if (equal? k key) v acc)) nil)) (lambda (e) nil))
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
?><a href='/view/<?rdf PRINT URL ?value ?>' data-rdfop-id='<?rdf PRINT HTML ?value ?>' draggable='true' onclick='event.preventDefault();rdfopOverlay(this)' ondragstart='rdfopDragStartLink(event,this,{kind:&quot;component&quot;})' ondragend='if(!window.__rdfopDragSession||!window.__rdfopDragSession.dropped)rdfopDragClear()'><?rdf PRINT HTML ?value ?></a><?rdf
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

/* Generic RDFHP primitives for actions which need one atomic SPARQL update.
   Keeping the update in the shared planner avoids mutating storage from inside
   an RDFHP SELECT callback. */
(rdf_functions "rdf_term" (lambda (value) (begin
    (set text (concat value))
    (if (regexp_test text "[<>{}\\\"\\r\\n\\t ]")
        (error "rdf_term: invalid resource identifier")
        (if (match text (regex "_:" _) true false)
            text
            (if (match text (regex ":" _) true false) (concat "<" text ">") text)
        )
    )
)))
(rdf_functions "rdf_update" (lambda (query req res) (begin
    (set formula (parse_sparql "rdf" (concat query)))
    (eval formula)
    nil
)))

/* emit aggregated component assets directly from the RDF store.
   This avoids RDFHP SELECT loop artefacts like stray literal "nil" output
   inside <style>/<script> blocks. */
(define _emit_component_asset (lambda (predicate req res) (begin
    (set print (res "print"))
    (scan nil (table "rdf" "rdf")
        '(369435906932736)
        '()
        '("p" "o")
        (lambda (p o)
            (and
                (equal? p predicate)
                (not (nil? o))
                (not (equal? o "nil"))
            )
        )
        '("o")
        (lambda (acc o) (begin
            (print o)
            (print "\n")
            acc
        ))
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
    (set ins_ttl "")
    (if (and (not (nil? sid)) (not (nil? prev_id))) (begin
        (set prev_ref (_rdf_ref prev_id))
        (eval (parse_sparql "rdf" (concat
            "DELETE { " sid " <https://launix.de/rdfop/schema#selectedNode> " prev_ref " . "
            sid " <https://launix.de/rdfop/schema#children> " prev_ref " . } WHERE { "
            sid " <https://launix.de/rdfop/schema#selectedNode> " prev_ref " . "
            sid " <https://launix.de/rdfop/schema#children> " prev_ref " . }"
        )))
    ))
    (if (and (not (nil? sid)) (not (nil? next_id))) (begin
        (set ins_ttl (concat ins_ttl sid " <https://launix.de/rdfop/schema#selectedNode> " (_rdf_ref next_id) " .\n"))
        (set ins_ttl (concat ins_ttl sid " <https://launix.de/rdfop/schema#children> " (_rdf_ref next_id) " .\n"))
    ))
    (if (not (equal? ins_ttl "")) (load_ttl "rdf" ins_ttl))
)))

(define _find_parent_by_child (lambda (child_id)
    (_query_single_value (concat "SELECT ?parent WHERE { ?parent <https://launix.de/rdfop/schema#children> " (_rdf_ref child_id) " } LIMIT 1") "?parent")
))

(define _selector_remove_content_server (lambda (selector_id content_id parent_id) (begin
    (if (nil? parent_id)
        (begin
            (set _params (newsession))
            (_params "child" content_id)
            (_dispatch_action "onChildRemoved" selector_id _params nil)
        )
        (begin
            (_selector_assign_server selector_id nil content_id)
            (set _params (newsession))
            (_params "child" selector_id)
            (_dispatch_action "onChildRemoved" parent_id _params nil)
        )
    )
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

    /* Prefer direct bindings on the entity itself, then fall back to its type. */
    (set mode_pred (concat "<https://launix.de/rdfop/schema#" mode ">"))
    (try (lambda () (begin
        (define resultrow (lambda (row) (_rc "comp" (row "?comp"))))
        (eval (parse_sparql "rdf" (concat
            "SELECT ?comp WHERE { " sparql_id " " mode_pred " ?comp } LIMIT 1"
        )))
    )) (lambda (e) nil))
    (if (nil? (_rc "comp"))
        (begin
            (try (lambda () (begin
                (define resultrow (lambda (row) (_rc "comp" (row "?comp"))))
                (eval (parse_sparql "rdf" (concat
                    "SELECT ?comp WHERE { " sparql_id " a ?type . ?type " mode_pred " ?comp } LIMIT 1"
                )))
            )) (lambda (e) nil))
            nil
        )
        nil
    )

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
(rdfop_routes "/rdfop-query-json" (lambda (req res) (begin
    ((res "header") "Content-Type" "application/x-ndjson")
    (set q (req "query"))
    (set bodyParts (req "bodyParts"))
    (set rdfParam (_assoc_get_value q "rdf"))
    (set rdfBody (_assoc_get_value bodyParts "rdf"))
    (set rdf (coalesce rdfParam rdfBody "SELECT ?s, ?p, ?o WHERE {?s ?p ?o}"))
    (define formula (try (lambda () (parse_sparql "rdf" rdf)) (lambda (e) nil)))
    (if (nil? formula)
        (begin
            ((res "status") 400)
            ((res "print") "Parser error")
        )
        (begin
          ((res "status") 200)
          (try
            (lambda () (begin
                (define resultrow (res "jsonl"))
                (eval formula)
            ))
            (lambda (e) (begin
                ((res "status") 400)
                ((res "print") (htmlentities e))
            ))
          )
        )
    )
)))

/* GET /rdfop-playwright-tests — exposes embedded Playwright tests from the RDF store */
(rdfop_routes "/rdfop-playwright-tests" (lambda (req res) (begin
    ((res "header") "Content-Type" "application/x-ndjson")
    ((res "status") 200)
    (define resultrow (res "jsonl"))
    (eval (parse_sparql "rdf" (concat
        "SELECT ?id, ?label, ?target, ?ord, ?code WHERE { "
        "?id a <https://launix.de/rdfop/schema#PlaywrightTest> . "
        "?id <http://www.w3.org/2000/01/rdf-schema#label> ?label . "
        "?id <https://launix.de/rdfop/schema#testFor> ?target . "
        "?id <https://launix.de/rdfop/schema#order> ?ord . "
        "?id <https://launix.de/rdfop/schema#playwright> ?code }"
    )))
)))

/* POST /rdfop-source-cleanup — server-side cleanup of the drag source.
   This is used by receivers so moves also work across windows/contexts. */
(rdfop_routes "/rdfop-source-cleanup" (lambda (req res) (begin
    ((res "header") "Content-Type" "text/plain")
    (set bp (_parse_urlencoded_body (try (lambda () ((req "body"))) (lambda (e) ""))))
    (set source_kind (bp "sourceKind"))
    (set selector_id (bp "sourceSelectorId"))
    (set parent_id (bp "sourceParentId"))
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
                    (_selector_remove_content_server selector_id content_id parent_id)
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
                ) (_selector_remove_content_server child_id content_id tab_id))
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

/* POST /rdfop-create-entity — create a standalone instance of an EntityType.
   Unlike /rdfop-create this does not attach the entity to a component tree. */
(rdfop_routes "/rdfop-create-entity" (lambda (req res) (begin
    ((res "header") "Content-Type" "text/plain")
    (set body_raw (try (lambda () ((req "body"))) (lambda (e) "")))
    (set bp (newsession))
    (map (split body_raw "&") (lambda (pair) (begin
        (set parts (split pair "="))
        (set k (urldecode (replace (car parts) "+" " ")))
        (set v (urldecode (replace (coalesce (car (cdr parts)) "") "+" " ")))
        (bp k v)
    )))
    (set node_type (bp "type"))
    (if (nil? node_type) (begin
        ((res "status") 400)
        ((res "print") "missing type")
    ) (begin
        (set new_id (concat "urn:uuid:" (uuid)))
        (set _it (newsession))
        (try (lambda () (begin
            (define resultrow (lambda (o) (_it "tpl" (o "?tpl"))))
            (eval (parse_sparql "rdf" (concat "SELECT ?tpl WHERE { <" node_type "> <https://launix.de/rdfop/schema#initTemplate> ?tpl } LIMIT 1")))
        )) (lambda (e) nil))
        (set base_ttl (concat "<" new_id "> a <" node_type "> .\n"))
        (set extra_ttl (if (nil? (_it "tpl")) "" (replace (_it "tpl") "$ID" (concat "<" new_id ">"))))
        (set _create_entity_state (newsession))
        (_create_entity_state "ok" true)
        (try (lambda () (load_ttl "rdf" (concat base_ttl extra_ttl))) (lambda (e) (begin
            (_create_entity_state "ok" false)
            ((res "status") 500)
            ((res "print") (concat "error: " e))
        )))
        (if (_create_entity_state "ok") (begin
            ((res "status") 200)
            ((res "print") new_id)
        ))
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
    (set _save_state (newsession))
    (_save_state "ok" true)
    (_save_state "error" "")
    /* DELETE triples */
    (if (and (not (nil? del_ttl)) (not (equal? del_ttl "")))
        (try (lambda () (_rdfop_delete_ttl "rdf" del_ttl)) (lambda (e) (begin
            (_save_state "ok" false)
            (_save_state "error" (concat e))
            (print "rdfop delete error: " e)
        )))
    )
    /* INSERT triples only after a successful delete. */
    (if (and (_save_state "ok") (not (nil? ins_ttl)) (not (equal? ins_ttl "")))
        (try (lambda () (load_ttl "rdf" ins_ttl)) (lambda (e) (begin
            (_save_state "ok" false)
            (_save_state "error" (concat e))
            (print "rdfop insert error: " e)
        )))
    )
    (if (_save_state "ok") (begin
        ((res "status") 200)
        ((res "print") "ok")
    ) (begin
        ((res "status") 500)
        ((res "print") (concat "error: " (_save_state "error")))
    ))
)))

(define _rdfop_table_configuration_locked (lambda (id) (begin
    (set locked (_query_single_value (concat
        "SELECT ?locked WHERE { " (_rdf_ref id)
        " <https://launix.de/rdfop/schema#configurationLocked> ?locked } LIMIT 1"
    ) "?locked"))
    (or (equal? locked "true") (equal? locked "1"))
)))

/* POST /rdfop-table-config-save — table configuration writes with a
   server-side lock check. Runtime data edits continue to use /rdfop-save. */
(rdfop_routes "/rdfop-table-config-save" (lambda (req res) (begin
    ((res "header") "Content-Type" "text/plain")
    (set bp (_parse_urlencoded_body (try (lambda () ((req "body"))) (lambda (e) ""))))
    (set table_id (bp "id"))
    (set del_ttl (bp "delete"))
    (set ins_ttl (bp "insert"))
    (if (or (nil? table_id) (equal? table_id "")) (begin
        ((res "status") 400)
        ((res "print") "missing table id")
    ) (if (_rdfop_table_configuration_locked table_id) (begin
        ((res "status") 403)
        ((res "print") "Table configuration is locked.")
    ) (begin
        (set _table_save_state (newsession))
        (_table_save_state "ok" true)
        (_table_save_state "error" "")
        (if (and (not (nil? del_ttl)) (not (equal? del_ttl "")))
            (try (lambda () (_rdfop_delete_ttl "rdf" del_ttl)) (lambda (e) (begin
                (_table_save_state "ok" false)
                (_table_save_state "error" (concat e))
            )))
        )
        (if (and (_table_save_state "ok") (not (nil? ins_ttl)) (not (equal? ins_ttl "")))
            (try (lambda () (load_ttl "rdf" ins_ttl)) (lambda (e) (begin
                (_table_save_state "ok" false)
                (_table_save_state "error" (concat e))
            )))
        )
        (if (_table_save_state "ok") (begin
            ((res "status") 200)
            ((res "print") "ok")
        ) (begin
            ((res "status") 500)
            ((res "print") (concat "error: " (_table_save_state "error")))
        ))
    )))
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
            (scan nil (table "rdf" "rdf") '(369435906932736) '()
                '("s") (lambda (s) (equal? s id))
                '("$update") (lambda (acc $update) (begin ($update) acc)) nil)
            /* delete parent's children link to this node */
            (scan nil (table "rdf" "rdf") '(369435906932736) '()
                '("p" "o") (lambda (p o) (and (equal? p "https://launix.de/rdfop/schema#children") (equal? o id)))
                '("$update") (lambda (acc $update) (begin ($update) acc)) nil)
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
            "SELECT ?tpl WHERE { <https://launix.de/rdfop/schema#" action "> a <https://launix.de/rdfop/schema#Method> . " sparql_id " <https://launix.de/rdfop/schema#" action "> ?tpl } LIMIT 1"
        )))
    )) (lambda (e) nil))
    (if (nil? (_rc "tpl"))
        (begin
            (try (lambda () (begin
                (define resultrow (lambda (o) (_rc "tpl" (o "?tpl"))))
                (eval (parse_sparql "rdf" (concat
                    "SELECT ?tpl WHERE { <https://launix.de/rdfop/schema#" action "> a <https://launix.de/rdfop/schema#Method> . " sparql_id " a ?type . ?type <https://launix.de/rdfop/schema#" action "> ?tpl } LIMIT 1"
                )))
            )) (lambda (e) nil))
            nil
        )
        nil
    )
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



(set rdfop_port (arg "api-port" "3443"))
(serve rdfop_port http_handler)
(print "")
(print "listening on http://localhost:" rdfop_port)
(print "")
