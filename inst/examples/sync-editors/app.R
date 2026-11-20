library(shiny)
library(creditor)

sides = c("alice", "bob")
peers = c(alice = 1, bob = 2)

pane_ui = function(side) {
  bslib::card(
    bslib::card_header(
      class = "d-flex justify-content-between align-items-center",
      tags$strong(tools::toTitleCase(side)),
      checkboxInput(paste0(side, "_online"), "Online", value = TRUE, width = "auto")
    ),
    tags$textarea(
      id = paste0(side, "_text"),
      class = "form-control editor",
      `data-side` = side,
      `data-rev` = "0",
      rows = 12,
      spellcheck = "false"
    ),
    bslib::card_footer(textOutput(paste0(side, "_status"), inline = TRUE))
  )
}

editor_js = "
(function() {
  const dirty = {};

  document.addEventListener('input', function(e) {
    if (e.target.classList.contains('editor')) dirty[e.target.dataset.side] = true;
  });

  function send(el) {
    dirty[el.dataset.side] = false;
    Shiny.setInputValue('edit', {
      side: el.dataset.side, text: el.value, base: Number(el.dataset.rev)
    }, {priority: 'event'});
  }

  setInterval(function() {
    document.querySelectorAll('textarea.editor').forEach(function(el) {
      if (dirty[el.dataset.side]) send(el);
    });
  }, 1000);

  // Keep the caret in place when the server replaces the text: shift it by
  // the change in length when the edit happened before it.
  function setText(el, text) {
    const old = el.value;
    let pre = 0;
    while (pre < old.length && pre < text.length && old[pre] === text[pre]) pre++;
    let suf = 0;
    while (suf < old.length - pre && suf < text.length - pre &&
           old[old.length - 1 - suf] === text[text.length - 1 - suf]) suf++;
    const shift = function(pos) {
      if (pos <= pre) return pos;
      if (pos >= old.length - suf) return pos + text.length - old.length;
      return text.length - suf;
    };
    const start = shift(el.selectionStart), end = shift(el.selectionEnd);
    el.value = text;
    if (document.activeElement === el) el.setSelectionRange(start, end);
  }

  Shiny.addCustomMessageHandler('set_text', function(msg) {
    const el = document.getElementById(msg.side + '_text');
    // Unsent local edits win: send them against the old revision and let
    // the server merge them and push the result.
    if (dirty[msg.side]) { send(el); return; }
    setText(el, msg.text);
    el.dataset.rev = msg.rev;
  });
})();
"

editor_css = "
textarea.editor { font-family: ui-monospace, monospace; resize: vertical; }
.history-text {
  font-family: ui-monospace, monospace; white-space: pre-wrap;
  min-height: 6em; padding: .75em; border-radius: .375rem;
  background: var(--bs-tertiary-bg);
}
.history-text ins { background: #c8f7c5; color: #14532d; text-decoration: none; }
.history-text del { background: #fbd0d0; color: #7f1d1d; }
"

ui = bslib::page_fillable(
  title = "creditor: synchronized editors",
  tags$head(tags$style(editor_css), tags$script(HTML(editor_js))),
  h4("Two replicas of one Loro document"),
  p(
    "Each pane is its own replica. Edits are sent once a second and",
    "exchanged while both panes are online; take one offline, edit both,",
    "and bring it back to watch the concurrent edits merge."
  ),
  bslib::layout_columns(pane_ui("alice"), pane_ui("bob")),
  bslib::card(
    bslib::card_header(
      class = "d-flex justify-content-between align-items-center",
      tags$strong("History"),
      actionButton("restore", "Restore this version", class = "btn-sm")
    ),
    sliderInput(
      "step", NULL, min = 1, max = 1, value = 1, step = 1, width = "100%",
      animate = animationOptions(interval = 500)
    ),
    uiOutput("history_info"),
    uiOutput("history_text")
  )
)

server = function(input, output, session) {
  replicas = lapply(sides, function(side) {
    doc = loro_doc(peers[[side]])
    doc_record_timestamps(doc)
    env = new.env()
    env$doc = doc
    env$text = doc_text(doc, "body")
    env$rev = 0
    env$frontiers = list(`0` = doc_frontiers(doc))
    env$shown = ""
    env
  })
  names(replicas) = sides

  # An observer replica that imports from both panes whether or not they are
  # online, so the timeline shows every edit as soon as it is made.
  hist = loro_doc(99)
  hist_text = doc_text(hist, "body")
  timeline = reactiveVal(list())

  apply_edit = function(edit) {
    r = replicas[[edit$side]]
    if (edit$base == r$rev) {
      text_update(r$text, edit$text)
      doc_commit(r$doc)
      r$shown = edit$text
      r$frontiers[[as.character(r$rev)]] = doc_frontiers(r$doc)
    } else {
      # The browser edited an older revision than the server holds. Replay
      # the edit on a fork at that revision and merge it back, which is
      # exactly what Loro does for a remote replica.
      base = r$frontiers[[as.character(edit$base)]]
      fork = doc_fork(r$doc, at = base)
      text_update(doc_text(fork, "body"), edit$text)
      doc_commit(fork)
      doc_import(r$doc, doc_export_updates(fork))
      r$shown = NA
    }
  }

  sync = function(from, to) {
    doc_import(to$doc, doc_export_updates(from$doc, from = doc_version(to$doc)))
  }

  push = function(side) {
    r = replicas[[side]]
    text = text_get(r$text)
    if (identical(text, r$shown)) {
      return()
    }
    r$rev = r$rev + 1
    r$frontiers[[as.character(r$rev)]] = doc_frontiers(r$doc)
    if (length(r$frontiers) > 50) {
      r$frontiers = utils::tail(r$frontiers, 50)
    }
    r$shown = text
    session$sendCustomMessage("set_text", list(side = side, text = text, rev = r$rev))
  }

  record = function() {
    before = doc_frontiers(hist)
    for (side in sides) {
      r = replicas[[side]]
      doc_import(hist, doc_export_updates(r$doc, from = doc_version(hist)))
    }
    after = doc_frontiers(hist)
    if (!identical(unclass(before), unclass(after))) {
      entries = timeline()
      entries[[length(entries) + 1]] = list(time = Sys.time(), frontiers = after)
      timeline(entries)
      n = length(entries)
      step = isolate(input$step)
      following = is.null(step) || step >= n - 1
      updateSliderInput(session, "step", max = n, value = if (following) n else step)
    }
  }

  observeEvent(input$edit, apply_edit(input$edit))

  online = reactive(c(alice = isTRUE(input$alice_online), bob = isTRUE(input$bob_online)))

  observe({
    invalidateLater(1000)
    if (all(isolate(online()))) {
      sync(replicas$alice, replicas$bob)
      sync(replicas$bob, replicas$alice)
    }
    for (side in sides) {
      push(side)
    }
    record()
  })

  for (side in sides) {
    local({
      s = side
      output[[paste0(s, "_status")]] = renderText({
        invalidateLater(1000)
        r = replicas[[s]]
        other = replicas[[setdiff(sides, s)]]
        state = if (identical(text_get(r$text), text_get(other$text))) "in sync" else "diverged"
        paste0(
          "peer ", doc_peer_id(r$doc), " | ",
          doc_change_count(r$doc), " changes, ",
          doc_op_count(r$doc), " ops | ", state
        )
      })
    })
  }

  text_at = function(frontiers) {
    doc_checkout(hist, frontiers)
    on.exit(doc_checkout(hist))
    text_get(hist_text)
  }

  selected = reactive({
    entries = timeline()
    req(length(entries) > 0, input$step)
    k = min(input$step, length(entries))
    entry = entries[[k]]
    prev = if (k > 1) entries[[k - 1]]$frontiers else NULL
    list(k = k, entry = entry, prev = prev)
  })

  output$history_info = renderUI({
    s = selected()
    tags$p(
      class = "text-muted small mb-1",
      paste0(
        "Version ", s$k, " of ", length(timeline()), ", recorded ",
        format(s$entry$time, "%H:%M:%S"), ". ",
        "Green text was added and red text removed since the previous version."
      )
    )
  })

  output$history_text = renderUI({
    s = selected()
    tags$div(class = "history-text", diff_html(s$prev, s$entry$frontiers))
  })

  # Built as one string: the panel uses pre-wrap, so the whitespace
  # htmltools puts between tags would show up as text.
  diff_html = function(from, to) {
    esc = htmltools::htmlEscape
    if (is.null(from)) {
      return(HTML(paste0("<ins>", esc(text_at(to)), "</ins>")))
    }
    old = text_at(from)
    delta = doc_diff(hist, from, to)[[container_id(hist_text)]]$delta
    pos = 1
    out = character()
    for (op in delta) {
      if (!is.null(op$retain)) {
        out = c(out, esc(substr(old, pos, pos + op$retain - 1)))
        pos = pos + op$retain
      } else if (!is.null(op$delete)) {
        out = c(out, paste0("<del>", esc(substr(old, pos, pos + op$delete - 1)), "</del>"))
        pos = pos + op$delete
      } else if (!is.null(op$insert)) {
        out = c(out, paste0("<ins>", esc(op$insert), "</ins>"))
      }
    }
    if (pos <= nchar(old)) {
      out = c(out, esc(substr(old, pos, nchar(old))))
    }
    HTML(paste(out, collapse = ""))
  }

  # Restoring adds new changes to whichever replicas are online, so the
  # older text comes back as an ordinary edit that syncs and stays in the
  # history.
  observeEvent(input$restore, {
    s = selected()
    targets = sides[online()]
    if (length(targets) == 0) {
      showNotification("Both panes are offline.", type = "warning")
      return()
    }
    r = replicas[[targets[1]]]
    text_update(r$text, text_at(s$entry$frontiers))
    doc_commit(r$doc, message = paste("Restore version", s$k))
  })
}

shinyApp(ui, server)
