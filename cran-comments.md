## R CMD check results

0 errors \| 0 warnings \| 1 note

NOTE:
  Maintainer: ‘Nicholas Davies <nicholas.davies@lshtm.ac.uk>’
  Days since last update: 1


This is a bugfix release; there was a severe performance regression on ARM64 
platforms in recent releases of LuaJIT. This has now been corrected. I consider 
this update critical since the bug caused an approx. 30-fold slowdown of Lua 
code on ARM64, which includes all recent Apple computers. Apologies for not
catching it in time for the previous update.
