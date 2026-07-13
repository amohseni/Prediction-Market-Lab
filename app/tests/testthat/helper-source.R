# helper-source.R -- testthat sources helper*.R before the tests. Point it at
# the app's R/ directory and load the model core + ensemble metrics so every
# test file can call the pure functions. Works whether tests are run from the
# app/ root, the tests/testthat dir, or via scripts/run_tests.R.
.find_R_dir <- function() {
  cands <- c(
    Sys.getenv("APP_R_DIR", unset = NA),
    file.path(getwd(), "R"),
    file.path(getwd(), "..", "..", "R"),
    file.path(dirname(getwd()), "R")
  )
  for (d in cands) {
    if (!is.na(d) && dir.exists(d) && file.exists(file.path(d, "core_model.R"))) {
      return(normalizePath(d))
    }
  }
  stop("Could not locate app/R directory for tests")
}
.R_DIR <- .find_R_dir()
source(file.path(.R_DIR, "theme.R"))
source(file.path(.R_DIR, "core_model.R"))
if (file.exists(file.path(.R_DIR, "core_ensemble.R"))) {
  source(file.path(.R_DIR, "core_ensemble.R"))
}
