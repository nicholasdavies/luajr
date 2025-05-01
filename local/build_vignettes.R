tools::buildVignettes(dir = ".", tangle=TRUE)
dir.create("inst/doc")
file.copy(dir("vignettes", full.names=TRUE), "inst/doc", overwrite=TRUE)
