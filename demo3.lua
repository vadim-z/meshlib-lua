function f1(a)
   print('F1 = ', a)
   return a
end

function f2(a, b)
   return a*b
end

function f3(a, b)
   return a^b
end

function ity(v)
   return (math.type(v) == 'integer') and 1 or 0
end

local tbl = {
   foo = 17.42,
}

function f4(s, n)
   return tbl[s]-n
end
