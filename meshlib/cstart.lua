local libpath = ... or '.'
local psep = package.config:sub(1,1)
package.path = package.path .. 
   string.format(';%s%s?.lua;%s%s?%sinit.lua', libpath, psep, libpath, psep, psep)
mesh = require('meshlib'):mesh()
