# INITIAL SETUP

# Readme and docs
usethis::use_readme_md() # or rmd
usethis::use_news_md()
usethis::use_roxygen_md()
usethis::use_package_doc()
usethis::use_mit_license()
usethis::use_cran_comments()
devtools::document() # delete NAMESPACE before first time

# Set up git
usethis::git_vaccinate()
usethis::use_git()
usethis::use_github()
usethis::use_github_action()

# Web site
usethis::use_pkgdown_github_pages()

# Testing
usethis::use_testthat()
# usethis::use_coverage() # requires changing compilation flag for LuaJIT

# Add 'local' directory
dir.create("./local")
usethis::write_union("./.Rbuildignore", "^local$")


# ADDING ELEMENTS
# Import package
# usethis::use_package("rlang")

# Add vignette
usethis::use_vignette("luajr")


# BUILD CYCLE
devtools::document()
devtools::build_vignettes()
# devtools::build_readme()
pkgdown::build_site()

devtools::build(vignettes = TRUE)
devtools::install(build_vignettes = TRUE)


# RELEASE CYCLE
devtools::check(remote = TRUE, manual = TRUE)
devtools::check_win_devel()

usethis::use_version('minor') # patch, minor, or major

# CRAN
devtools::submit_cran()

# After accepted
git push
usethis::use_github_release()
usethis::use_dev_version()
git push
Finish blog post, share on social media, etc.
Add link to blog post in pkgdown news menu

# What else is missing from here?
# Rcpp
