# a delta prints as markdown

    Code
      text_delta(doc)
    Output
      <loro_delta>
      **Read** the [docs](https://loro.dev)

---

    Code
      text_delta(loro_doc())
    Output
      <loro_delta> (empty)

# a delta prints in the format asked for

    Code
      print(delta, format = "html")
    Output
      <loro_delta>
      <strong>Read</strong> the docs

# printing notes left-out marks instead of warning

    Code
      print(delta)
    Output
      <loro_delta>
      **a**b
      (not shown: author; print with format = "html" to see it)
    Code
      print(delta, format = "html")
    Output
      <loro_delta>
      <strong>a</strong><span data-author="cr">b</span>

