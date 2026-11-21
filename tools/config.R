# Note: Any variables prefixed with `.` are used for text
# replacement in the Makevars.in and Makevars.win.in

# check the packages MSRV first
source("tools/msrv.R")

# check the DEBUG environment variable
env_debug <- Sys.getenv("DEBUG")
is_debug <- env_debug != ""

if (is_debug) {
  message("Creating DEBUG build.")
}

# when DEBUG env var is present we use a `--debug` build
.profile <- ifelse(is_debug, "", "--release")
.clean_targets <- ifelse(is_debug, "", "$(TARGET_DIR)")

# CREDITOR_CARGO_CACHE names a directory that holds the cargo target
# directory and CARGO_HOME across installs, so CI can cache compiled
# dependencies. Both must stay fixed: cargo rebuilds every dependency
# when the registry sources move. Nothing is cleaned up afterwards.
cargo_cache = Sys.getenv("CREDITOR_CARGO_CACHE")
if (nzchar(cargo_cache)) {
  message("Using the cargo cache in ", cargo_cache, ".")
  .target_dir = file.path(cargo_cache, "target")
  .cargo_home = file.path(cargo_cache, "home")
  .clean_targets = ""
  .clean_cargo = ":"
} else {
  .target_dir = "./rust/target"
  .cargo_home = "$(CURDIR)/.cargo"
  .clean_cargo = "rm -Rf $(CARGOTMP)"
}

# We specify this target when building for webR
webr_target <- "wasm32-unknown-emscripten"

# here we check if the platform we are building for is webr
is_wasm <- identical(R.version$platform, webr_target)

# print to terminal to inform we are building for webr
if (is_wasm) {
  message("Building for WebR")
}

# we check if we are making a debug build or not
# if so, the LIBDIR environment variable becomes:
# LIBDIR = $(TARGET_DIR)/{wasm32-unknown-emscripten}/debug
# this will be used to fill out the LIBDIR env var for Makevars.in
target_libpath <- if (is_wasm) "wasm32-unknown-emscripten" else NULL
cfg <- if (is_debug) "debug" else "release"

# used to replace @LIBDIR@
.libdir <- paste(c(target_libpath, cfg), collapse = "/")

# use this to replace @TARGET@
# we specify the target _only_ on webR
# there may be use cases later where this can be adapted or expanded
.target <- ifelse(is_wasm, paste0("--target=", webr_target), "")

# add panic exports only for WASM builds
.panic_exports <- ifelse(
  is_wasm,
  "CARGO_PROFILE_DEV_PANIC=\"abort\" CARGO_PROFILE_RELEASE_PANIC=\"abort\" ",
  ""
)

# read in the Makevars.in file checking
is_windows <- .Platform[["OS.type"]] == "windows"

# if windows we replace in the Makevars.win.in
mv_fp <- ifelse(
  is_windows,
  "src/Makevars.win.in",
  "src/Makevars.in"
)

# set the output file
mv_ofp <- ifelse(
  is_windows,
  "src/Makevars.win",
  "src/Makevars"
)

# delete the existing Makevars{.win/.wasm}
if (file.exists(mv_ofp)) {
  message("Cleaning previous `", mv_ofp, "`.")
  invisible(file.remove(mv_ofp))
}

# read as a single string
mv_txt <- readLines(mv_fp)

# replace placeholder values
new_txt <- gsub("@PROFILE@", .profile, mv_txt) |>
  gsub("@CLEAN_TARGET@", .clean_targets, x = _) |>
  gsub("@LIBDIR@", .libdir, x = _) |>
  gsub("@TARGET@", .target, x = _) |>
  gsub("@PANIC_EXPORTS@", .panic_exports, x = _) |>
  gsub("@TARGET_DIR@", .target_dir, x = _, fixed = TRUE) |>
  gsub("@CARGO_HOME@", .cargo_home, x = _, fixed = TRUE) |>
  gsub("@CLEAN_CARGO@", .clean_cargo, x = _, fixed = TRUE)

message("Writing `", mv_ofp, "`.")
con <- file(mv_ofp, open = "wb")
writeLines(new_txt, con, sep = "\n")
close(con)

message("`tools/config.R` has finished.")
