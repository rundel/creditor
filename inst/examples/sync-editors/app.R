library(shiny)
library(creditor)

sides = c("alice", "bob")
peers = c(alice = 1, bob = 2)
colors = c(alice = "#2563eb", bob = "#d97706")

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

  // Timeline bubbles: a hover tooltip, and a click selects that edit.
  const tip = document.createElement('div');
  tip.className = 'bubble-tip';
  document.addEventListener('DOMContentLoaded', function() { document.body.appendChild(tip); });

  const bubble = function(e) { return e.target.closest ? e.target.closest('.bubble') : null; };

  document.addEventListener('mouseover', function(e) {
    const el = bubble(e);
    if (!el) return;
    tip.innerHTML = el.dataset.tip;
    tip.style.display = 'block';
    const box = el.getBoundingClientRect();
    const left = Math.min(
      Math.max(8, box.left + box.width / 2 - tip.offsetWidth / 2),
      window.innerWidth - tip.offsetWidth - 8
    );
    tip.style.left = left + 'px';
    tip.style.top = Math.max(8, box.top - tip.offsetHeight - 8) + 'px';
  });

  document.addEventListener('mouseout', function(e) {
    if (bubble(e)) tip.style.display = 'none';
  });

  document.addEventListener('click', function(e) {
    const el = bubble(e);
    if (el) Shiny.setInputValue('bubble', Number(el.dataset.step), {priority: 'event'});
  });

  // The timeline is redrawn on every edit. Keep it scrolled to the newest
  // bubble while the latest edit is selected, and where it was otherwise.
  let scrolled = 0;
  document.addEventListener('scroll', function(e) {
    if (e.target.classList && e.target.classList.contains('timeline-scroll')) {
      scrolled = e.target.scrollLeft;
    }
  }, true);

  $(document).on('shiny:value', function(e) {
    if (e.target.id !== 'timeline') return;
    tip.style.display = 'none';
    const keep = scrolled;
    setTimeout(function() {
      const el = document.querySelector('.timeline-scroll');
      if (!el) return;
      el.scrollLeft = el.dataset.follow === 'true' ? el.scrollWidth : keep;
    }, 0);
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
.timeline { display: flex; align-items: flex-start; }
.timeline-rows { flex: none; width: 4.5em; font-size: .875rem; font-weight: 600; }
.timeline-rows div { height: 32px; line-height: 32px; }
.timeline-scroll { flex: 1; overflow-x: auto; }
.timeline svg { display: block; }
.timeline .lane { stroke: var(--bs-border-color); stroke-width: 1; }
.timeline .axis { stroke: var(--bs-secondary-color); stroke-width: 1; }
.timeline text { fill: var(--bs-secondary-color); font-size: 11px; text-anchor: middle; }
.bubble { cursor: pointer; stroke: var(--bs-body-bg); stroke-width: 2; }
.bubble:hover { stroke: var(--bs-body-color); }
.bubble.selected { stroke: var(--bs-body-color); stroke-width: 3; }
.bubble-tip {
  display: none; position: fixed; z-index: 2000; max-width: 28em;
  padding: .4em .6em; border-radius: .375rem; font-size: .8125rem;
  background: #1f2937; color: #f9fafb; pointer-events: none;
  box-shadow: 0 2px 8px rgba(0, 0, 0, .25);
}
.bubble-tip .edit {
  font-family: ui-monospace, monospace; white-space: pre-wrap; overflow-wrap: anywhere;
}
.bubble-tip .added { color: #86efac; }
.bubble-tip .removed { color: #fca5a5; }
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
      tags$div(
        class = "d-flex gap-2",
        actionButton("prev", "Previous", class = "btn-sm"),
        actionButton("nxt", "Next", class = "btn-sm"),
        actionButton("restore", "Restore this version", class = "btn-sm")
      )
    ),
    uiOutput("timeline"),
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
    env$rev = 0
    env$frontiers = list(`0` = doc_frontiers(doc))
    env$shown = ""
    env
  })
  names(replicas) = sides

  # One entry per edit, recorded where the edit is made so that it is
  # attributed to the pane it came from even while the panes are syncing.
  timeline = reactiveVal(list())
  step = reactiveVal(0)

  # The text before an edit and the delta the edit produced, as runs of
  # kept, added, and removed text.
  edit_runs = function(old, delta) {
    pos = 1
    runs = list()
    add = function(type, text) {
      if (nzchar(text)) {
        runs[[length(runs) + 1]] <<- list(type = type, text = text)
      }
    }
    for (op in delta) {
      if (!is.null(op$retain)) {
        add("keep", substr(old, pos, pos + op$retain - 1))
        pos = pos + op$retain
      } else if (!is.null(op$delete)) {
        add("removed", substr(old, pos, pos + op$delete - 1))
        pos = pos + op$delete
      } else if (!is.null(op$insert)) {
        add("added", op$insert)
      }
    }
    add("keep", substr(old, pos, nchar(old)))
    runs
  }

  with_edit = function(side, code, label = NULL, time = Sys.time()) {
    r = replicas[[side]]
    before = doc_frontiers(r$doc)
    old = text_get(r$doc)
    code(r)
    after = doc_frontiers(r$doc)
    delta = doc_diff(r$doc, before, after)[[container_id(doc_text(r$doc))]]$delta
    if (length(delta) == 0) {
      return()
    }
    entries = isolate(timeline())
    n = length(entries)
    entries[[n + 1]] = list(
      side = side, time = time, label = label, runs = edit_runs(old, delta)
    )
    timeline(entries)
    if (isolate(step()) == n) {
      step(n + 1)
    }
  }

  apply_edit = function(edit) {
    with_edit(edit$side, function(r) {
      if (edit$base == r$rev) {
        text_update(r$doc, edit$text)
        doc_commit(r$doc)
        r$shown = edit$text
        r$frontiers[[as.character(r$rev)]] = doc_frontiers(r$doc)
      } else {
        # The browser edited an older revision than the server holds. Replay
        # the edit on a fork at that revision and merge it back, which is
        # exactly what Loro does for a remote replica.
        base = r$frontiers[[as.character(edit$base)]]
        fork = doc_fork(r$doc, at = base)
        text_update(fork, edit$text)
        doc_commit(fork)
        doc_import(r$doc, doc_export_updates(fork))
        r$shown = NA
      }
    })
  }

  sync = function(from, to) {
    doc_merge(to$doc, from$doc)
  }

  push = function(side) {
    r = replicas[[side]]
    text = text_get(r$doc)
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

  # Start from a short document with some history: a few edits from each
  # pane, two of them made concurrently before the panes next synced.
  seed = function(side, text, seconds_ago) {
    with_edit(side, time = Sys.time() - seconds_ago, function(r) {
      text_update(r$doc, text)
      doc_commit(r$doc)
    })
  }
  sync_both = function() {
    sync(replicas$alice, replicas$bob)
    sync(replicas$bob, replicas$alice)
  }
  seed("alice", "Team offsite\n", 240)
  sync_both()
  seed("bob", "Team offsite\n- Book the venue\n", 210)
  sync_both()
  seed("alice", "Team offsite\n- Book the venue\n- Send invitations\n", 180)
  sync_both()
  seed("bob", "Team offsite\n- Book the venue by Friday\n- Send invitations\n", 150)
  seed("alice", "Team offsite, June 12\n- Book the venue\n- Send invitations\n", 140)
  sync_both()
  seed("bob", paste0(text_get(replicas$bob$doc), "- Order lunch\n"), 90)
  sync_both()
  seed("alice", sub("Send invitations", "Send the invitations", text_get(replicas$alice$doc)), 60)
  sync_both()

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
  })

  for (side in sides) {
    local({
      s = side
      output[[paste0(s, "_status")]] = renderText({
        invalidateLater(1000)
        r = replicas[[s]]
        other = replicas[[setdiff(sides, s)]]
        state = if (identical(text_get(r$doc), text_get(other$doc))) "in sync" else "diverged"
        paste0(
          "peer ", doc_peer_id(r$doc), " | ",
          doc_change_count(r$doc), " changes, ",
          doc_op_count(r$doc), " ops | ", state
        )
      })
    })
  }

  observeEvent(input$bubble, step(input$bubble))
  observeEvent(input$prev, step(max(1, step() - 1)))
  observeEvent(input$nxt, step(min(length(timeline()), step() + 1)))

  selected = reactive({
    entries = timeline()
    req(length(entries) > 0, step() >= 1)
    k = min(step(), length(entries))
    list(k = k, entry = entries[[k]])
  })

  esc = htmltools::htmlEscape
  tip_html = function(entry) {
    shorten = function(text) {
      text = gsub("\n", "\u23ce", text)
      if (nchar(text) > 80) paste0(substr(text, 1, 80), "\u2026") else text
    }
    lines = vapply(
      Filter(function(run) run$type != "keep", entry$runs),
      function(run) {
        sign = if (run$type == "added") "+ " else "\u2212 "
        paste0("<div class=\"edit ", run$type, "\">", sign, esc(shorten(run$text)), "</div>")
      },
      character(1)
    )
    paste0(
      "<strong>", tools::toTitleCase(entry$side), "</strong> at ",
      format(entry$time, "%H:%M:%S"),
      if (!is.null(entry$label)) paste0(" (", esc(entry$label), ")"),
      paste(lines, collapse = "")
    )
  }

  # Bubbles are evenly spaced in the order the edits were made, one row
  # per pane, with the time of every few edits along the axis below.
  output$timeline = renderUI({
    entries = timeline()
    if (length(entries) == 0) {
      return(tags$p(class = "text-muted small mb-1", "Edits appear here as they are made."))
    }
    n = length(entries)
    gap = 26
    row_height = 32
    axis_y = row_height * length(sides) + 4
    x = (seq_len(n) - 0.5) * gap + 8
    y = (match(vapply(entries, `[[`, "", "side"), sides) - 0.5) * row_height
    width = n * gap + 40

    lanes = paste0(
      "<line class=\"lane\" x1=\"0\" x2=\"100%\" y1=\"",
      (seq_along(sides) - 0.5) * row_height, "\" y2=\"",
      (seq_along(sides) - 0.5) * row_height, "\"/>"
    )
    bubbles = vapply(seq_len(n), function(k) {
      entry = entries[[k]]
      paste0(
        "<circle class=\"bubble", if (k == step()) " selected", "\" cx=\"", x[k],
        "\" cy=\"", y[k], "\" r=\"", if (k == step()) 10 else 8,
        "\" fill=\"", colors[[entry$side]], "\" data-step=\"", k,
        "\" data-tip=\"", esc(tip_html(entry), attribute = TRUE), "\"/>"
      )
    }, character(1))
    labeled = seq(1, n, by = 3)
    ticks = paste0(
      "<line class=\"axis\" x1=\"", x[labeled], "\" x2=\"", x[labeled], "\" y1=\"", axis_y,
      "\" y2=\"", axis_y + 5, "\"/><text x=\"", pmax(x[labeled], 26), "\" y=\"", axis_y + 18,
      "\">", format(do.call(c, lapply(entries[labeled], `[[`, "time")), "%H:%M:%S"), "</text>"
    )
    svg = paste0(
      "<svg width=\"", width, "\" height=\"", axis_y + 24, "\" style=\"min-width: 100%\">",
      paste(lanes, collapse = ""),
      "<line class=\"axis\" x1=\"0\" x2=\"100%\" y1=\"", axis_y, "\" y2=\"", axis_y, "\"/>",
      paste(ticks, collapse = ""), paste(bubbles, collapse = ""), "</svg>"
    )
    tags$div(
      class = "timeline mb-2",
      tags$div(class = "timeline-rows", lapply(sides, function(side) {
        tags$div(style = paste0("color: ", colors[[side]]), tools::toTitleCase(side))
      })),
      tags$div(
        class = "timeline-scroll",
        `data-follow` = if (step() == n) "true" else "false",
        HTML(svg)
      )
    )
  })

  output$history_info = renderUI({
    s = selected()
    tags$p(
      class = "text-muted small mb-1",
      paste0(
        "Edit ", s$k, " of ", length(timeline()), ", made by ",
        tools::toTitleCase(s$entry$side), " at ", format(s$entry$time, "%H:%M:%S"), ". ",
        "Green text was added and red text removed by this edit."
      )
    )
  })

  # Built as one string: the panel uses pre-wrap, so the whitespace
  # htmltools puts between tags would show up as text.
  output$history_text = renderUI({
    s = selected()
    tag = c(keep = "", added = "ins", removed = "del")
    parts = vapply(s$entry$runs, function(run) {
      if (run$type == "keep") {
        return(esc(run$text))
      }
      paste0("<", tag[[run$type]], ">", esc(run$text), "</", tag[[run$type]], ">")
    }, character(1))
    tags$div(class = "history-text", HTML(paste(parts, collapse = "")))
  })

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
    kept = Filter(function(run) run$type != "removed", s$entry$runs)
    text = paste(vapply(kept, `[[`, "", "text"), collapse = "")
    with_edit(targets[1], label = paste("restored edit", s$k), function(r) {
      text_update(r$doc, text)
      doc_commit(r$doc, message = paste("Restore edit", s$k))
    })
  })
}

shinyApp(ui, server)
