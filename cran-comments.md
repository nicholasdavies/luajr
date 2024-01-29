## Resolved issues (2)

This release fixes a 'Warning' for r-oldrel-windows-x86_64:

-   Resolved an R CMD check warning about unnamed structs/unions.

This release also fixes an 'Additional issue' for M1mac:

-   Resolved an R CMD check warning about enums in LuaJIT defining values outside the int (but within the uint32_t) range, as identified by the flag -Wpedantic.

## Remaining R CMD check issues (1)

0 errors \| 0 warnings \| 1 note

-   Note 1

    checking for GNU extensions in Makefiles ... NOTE

    GNU make is a SystemRequirements.

    *Justification*: This package wraps the LuaJIT compiler, which requires GNU make to build. The build system for LuaJIT is very complex, so it would be prohibitively difficult to get around this requirement.

## Remaining 'additional issues' (1)

There are several 'additional issues' for the UBSAN builds, arising from code in the LuaJIT compiler which this package wraps. These seem to be false positives triggered by the extensive low-level memory handling of LuaJIT.
