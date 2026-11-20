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
    Code
      print(delta, format = "list")
    Output
      <loro_delta>
      List of 2
       $ :List of 2
        ..$ insert    : chr "Read"
        ..$ attributes:List of 1
        .. ..$ bold: logi TRUE
       $ :List of 1
        ..$ insert: chr " the docs"

