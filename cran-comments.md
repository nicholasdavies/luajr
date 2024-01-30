## Corrected problems

I was asked to correct problems identified by CRAN by 2024-02-11. I have corrected these problems as follows:

-   Fixed a 'Warning' for r-oldrel-windows-x86_64 about unnamed structs/unions.

-   Fixed an 'Additional issue' for M1mac about enums in LuaJIT defining values outside the int (but within the uint32_t) range, as identified by the flag -Wpedantic.

## Remaining issues

0 errors \| 0 warnings \| 1 note

-   NOTE: GNU make is a SystemRequirements.

    *Justification*: This package wraps the LuaJIT compiler, which requires GNU make to build. The build system for LuaJIT is very complex, so it would be prohibitively difficult to get around this requirement.

-   'Additional issues' for the UBSAN builds.

    *Justification*: These issues arise from code in the LuaJIT compiler which this package wraps. These seem to be false positives triggered by the extensive low-level memory handling done by the LuaJIT compiler.
