This is a resubmission.

## Corrected problems

-   I have added "aut" to Mike Pall's Authors entry in DESCRIPTION following feedback from CRAN, and created a CITATION which explicitly includes luajit.org. I e-mailed Mike Pall to ask him if he was happy with these as acknowledgement of his contribution to the package, and he replied saying yes. 

-   All NOTEs, WARNINGs, and "additional issues" that were previously flagged by CRAN have been resolved, except for the NOTE below due to GNU make being a system requirement. I have verified this using rhub::check_with_sanitizers(), which mimics UBsan builds, and with the standard GitHub Actions "R CMD check" on macos-latest-release, windows-latest-release, ubuntu-latest-devel, ubuntu-latest-release, and ubuntu-latest-oldrel-1. 

## Remaining issues

0 errors \| 0 warnings \| 1 note

-   NOTE: GNU make is a SystemRequirements.

    *Justification*: This package wraps the LuaJIT compiler, which requires GNU make to build. The build system for LuaJIT is very complex, so it would be prohibitively difficult to get around this requirement.
