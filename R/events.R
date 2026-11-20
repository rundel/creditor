#' Subscribe to changes
#'
#' @description
#' Subscriptions call an R function when a document changes.
#'
#' * `doc_subscribe()` calls `callback(event)` for every committed
#'   change, whether made locally, imported from another replica, or
#'   caused by a checkout. With `container`, only changes to that
#'   container and the containers nested inside it are reported.
#' * `doc_subscribe_local_updates()` calls `callback(bytes)` after each
#'   local commit with the update it produced: a raw vector that another
#'   replica can pass to [`doc_import()`]. This is the building block for
#'   live synchronization.
#' * `doc_subscribe_first_commit()` calls `callback(peer)` the first
#'   time this document commits a local change under a given peer id,
#'   which is a natural moment to record who that peer is (for example
#'   in a map of authors). It fires again if the document's peer id
#'   changes, but not for peers whose changes are imported.
#' * `doc_subscribe_peer_id()` calls `callback(peer)` with the new peer
#'   id whenever this document's own peer id changes.
#' * `unsubscribe()` stops a subscription.
#'
#' @section Events:
#' An `event` is a list with:
#'
#' * `by`: what caused the change: `"local"`, `"import"`, or
#'   `"checkout"`.
#' * `origin`: the origin label of the commit, usually `""`.
#' * `diff`: the changes, in the format returned by [`doc_diff()`].
#'
#' @section Timing:
#' Changes are reported when they are committed, not when each edit is
#' made, so call [`doc_commit()`] to flush pending edits. Callbacks run
#' after the creditor function that committed or imported the change has
#' finished its work, just before it returns, so a callback can safely
#' read or edit the document. Events are delivered in the order they
#' occurred: if a callback itself commits a change, the resulting event
#' is delivered after the callbacks for the current event have run. An
#' error in a callback is reported as a warning and does not interrupt
#' the function that triggered it.
#'
#' A subscription stays active until `unsubscribe()` is called, even if
#' the object returned here is discarded and even after its document is
#' no longer referenced, so unsubscribe when you are done. A document
#' that is dropped with uncommitted edits commits them as it is freed,
#' which can deliver one last event to a subscription left on it.
#'
#' @param doc A [`loro_doc`].
#' @param callback A function of one argument.
#' @param container A container handle to limit the subscription to, or
#'   `NULL` for the whole document.
#' @param subscription An object returned by one of the subscribe
#'   functions.
#'
#' @return The subscribe functions return a subscription object. `unsubscribe()` returns `NULL` invisibly.
#'
#' @examples
#' a = loro_doc()
#' b = loro_doc()
#'
#' sync = doc_subscribe_local_updates(a, function(bytes) doc_import(b, bytes))
#' watch = doc_subscribe(b, function(event) {
#'   cat("b changed by", event$by, "\n")
#' })
#'
#' text_insert(doc_text(a), 1, "Hello")
#' doc_commit(a)
#' text_get(doc_text(b))
#'
#' unsubscribe(sync)
#' unsubscribe(watch)
#'
#' @name subscribe
NULL

the = new.env(parent = emptyenv())
the$subscriptions = list()
the$next_id = 0L
the$pending = list()
the$delivering = FALSE

loro_subscription = S7::new_class(
  "loro_subscription",
  package = "creditor",
  properties = list(id = S7::class_character)
)

register_subscription = function(ptr, callback) {
  the$next_id = the$next_id + 1L
  id = as.character(the$next_id)
  the$subscriptions[[id]] = list(ptr = ptr, callback = callback)
  loro_subscription(id = id)
}

# Events are moved from the Rust queues onto one R-side FIFO and delivered
# from there. A callback that commits calls deliver_events() again; that
# nested call only adds to the FIFO and returns, leaving the outer loop to
# deliver in order. Delivering from inside the nested call would run the
# new event's callbacks ahead of events that were queued before it.
#
# An event leaves the FIFO only when its callback is about to run, so if
# delivery is interrupted (a warning escalated to an error, or a user
# interrupt) the remaining events are kept for the next call.
deliver_events = function() {
  if (loro_events_pending_impl()) {
    for (id in names(the$subscriptions)) {
      entry = the$subscriptions[[id]]
      for (event in loro_subscription_take_impl(entry$ptr)) {
        the$pending[[length(the$pending) + 1L]] = list(id = id, event = event)
      }
    }
  }
  if (the$delivering || length(the$pending) == 0L) {
    return(invisible())
  }
  the$delivering = TRUE
  on.exit(assign("delivering", FALSE, envir = the))
  while (length(the$pending) > 0L) {
    item = the$pending[[1L]]
    the$pending[[1L]] = NULL
    entry = the$subscriptions[[item$id]]
    if (is.null(entry)) {
      next
    }
    tryCatch(
      entry$callback(item$event),
      error = function(cnd) {
        cli::cli_warn(
          c("A subscription callback failed.", x = conditionMessage(cnd)),
          call = NULL
        )
      }
    )
  }
  invisible()
}

check_callback = function(callback, call = rlang::caller_env()) {
  if (!is.function(callback)) {
    cli::cli_abort("{.arg callback} must be a function.", call = call)
  }
  callback
}

#' @rdname subscribe
#' @export
doc_subscribe = function(doc, callback, container = NULL) {
  check_doc(doc)
  check_callback(callback)
  ptr = if (is.null(container)) {
    loro_doc_subscribe_impl(doc@ptr)
  } else {
    check_container(container, loro_container, "container")
    loro_doc_subscribe_container_impl(doc@ptr, container@ptr)
  }
  register_subscription(ptr, callback)
}

#' @rdname subscribe
#' @export
doc_subscribe_local_updates = function(doc, callback) {
  check_doc(doc)
  check_callback(callback)
  register_subscription(loro_doc_subscribe_local_updates_impl(doc@ptr), callback)
}

#' @rdname subscribe
#' @export
doc_subscribe_first_commit = function(doc, callback) {
  check_doc(doc)
  check_callback(callback)
  register_subscription(loro_doc_subscribe_first_commit_impl(doc@ptr), callback)
}

#' @rdname subscribe
#' @export
doc_subscribe_peer_id = function(doc, callback) {
  check_doc(doc)
  check_callback(callback)
  register_subscription(loro_doc_subscribe_peer_id_impl(doc@ptr), callback)
}

#' @rdname subscribe
#' @export
unsubscribe = function(subscription) {
  if (!S7::S7_inherits(subscription, loro_subscription)) {
    cli::cli_abort("{.arg subscription} must be a {.cls loro_subscription}.")
  }
  entry = the$subscriptions[[subscription@id]]
  if (!is.null(entry)) {
    loro_subscription_cancel_impl(entry$ptr)
    the$subscriptions[[subscription@id]] = NULL
    the$pending = Filter(function(item) item$id != subscription@id, the$pending)
  }
  invisible()
}
