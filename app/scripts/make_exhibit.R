# =============================================================================
# make_exhibit.R -- precompute the n_eff-ceiling exhibit and bundle it as an
# .rds so Tab 3 (Reliability) never opens blank (handoff Sec. 4 Tab 3).
# Brier vs n at rho in {0, 0.1, 0.3, 0.5}, with the analytic omniscient Brier.
#
# Usage (from the app/ directory):  Rscript scripts/make_exhibit.R
# =============================================================================

app_dir <- Sys.getenv("APP_DIR", unset = getwd())
R_dir   <- file.path(app_dir, "R")
source(file.path(R_dir, "theme.R"))
source(file.path(R_dir, "core_model.R"))
source(file.path(R_dir, "core_ensemble.R"))

ns   <- c(25, 50, 100, 200, 400, 800)
rhos <- c(0, 0.1, 0.3, 0.5)
R    <- 200

rows <- list()
for (rho in rhos) {
  p <- pm_default_params(); p$rho <- rho
  sw <- sweep_1d(p, "n", as.integer(ns), R = R, seed = 4242, metrics = c("B"))
  sw$rho <- rho
  rows[[length(rows) + 1]] <- sw[, c("rho", "value", "B", "B_lo", "B_hi", "B_omn")]
  message(sprintf("rho=%.1f done", rho))
}
df <- do.call(rbind, rows)
names(df)[names(df) == "value"] <- "n"

out_dir <- file.path(app_dir, "data")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
saveRDS(list(data = df, ns = ns, rhos = rhos, R = R),
        file.path(out_dir, "neff_exhibit.rds"))
message("wrote ", file.path(out_dir, "neff_exhibit.rds"))
