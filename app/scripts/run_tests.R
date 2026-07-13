# run_tests.R -- run the testthat suite for the model core / ensemble.
# Usage (from the app/ directory):  Rscript scripts/run_tests.R
suppressMessages(library(testthat))

# Resolve the app/ directory: prefer APP_DIR env, else assume CWD is app/.
app_dir <- Sys.getenv("APP_DIR", unset = getwd())
if (!dir.exists(file.path(app_dir, "R"))) {
  stop("Run from the app/ directory (or set APP_DIR). R/ not found under: ", app_dir)
}
Sys.setenv(APP_R_DIR = normalizePath(file.path(app_dir, "R")))

res <- test_dir(file.path(app_dir, "tests", "testthat"),
                reporter = "summary", stop_on_failure = FALSE)
df <- as.data.frame(res)
fails <- sum(df$failed) + sum(df$error)
cat(sprintf("\n=== %d test blocks, %d failed/errored ===\n", nrow(df), fails))
quit(status = if (fails > 0) 1L else 0L)
