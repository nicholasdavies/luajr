## R CMD check results

0 errors \| 0 warnings \| 1 note

Days since last release: 2

This is a quick re-release to fix some potential bugs unearthed by ASAN checks
on CRAN, and some build errors that were isolated to the fedora build flavours 
on CRAN. I have added ASAN checks to my pre-submission checks to catch any 
future errors early.

win-builder checks are currently indicating www.lua.org is timing out. The web
site indeed appears to be down at this very moment, but this is likely to be
temporary.
