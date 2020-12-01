-- module to read mesh in native gmsh MSH2 format

local function getline(f)
   local s
   repeat
      s = f:read()
      assert(s, 'Unexpected EoF')
      s = s:gsub('#.*', '')
   until not(s:match('^%s*$'))
   return s
end

local function tokenize(s)
   local t = {}
   for w in s:gmatch('%S+') do
      table.insert(t, (assert(tonumber(w), 'Lexical error: '..w)))
   end
   return table.unpack(t)
end

local function gettoks(f)
   return tokenize(getline(f))
end

local function end_section(f, name)
   assert(getline(f) == '$End' .. name,
          'End of section ' .. name .. ' expected')
end

local function read_fmt(f)
   assert(getline(f) == '$MeshFormat', 'MeshFormat section expected')
   local fmt, ftype, dsize = gettoks(f)
   assert(fmt == 2.2 and ftype == 0 and dsize == 8, 'Invalid mesh format')
   end_section(f, 'MeshFormat')
end

local function read_nodes(M, f)
   local nnodes = gettoks(f)
   local nodes = {}
   local node_map = {}
   local max_n = 0
   for _ = 1, nnodes do
      local i, x, y, z = gettoks(f)
      nodes[i] = {x, y, z}
      if i > max_n then
         max_n = i
      end
   end
   end_section(f, 'Nodes')
   M.node_map = node_map
   M.nodes = nodes
   M.nnodes = max_n
end

-- FIXME: unmapped 1D/2D elts
local elemtable = {
   -- 1st order
   {1, 2, 1}, -- 2n line
   {2, 3, 2, n_corner = 3}, -- 3n tri
   {3, 4, 2, n_corner = 4}, -- 4n quad
   {4, 4, 3,
    type = 'TETRA4', map = false,
    sides = {
       { 1, 2, 4 },
       { 2, 3, 4 },
       { 1, 4, 3 },
       { 1, 3, 2 },
    },
   }, -- 4n tet
   {5, 8, 3,
    type = 'HEX8', map = false,
    sides = {
       { 1, 2, 6, 5 },
       { 2, 3, 7, 6 },
       { 3, 4, 8, 7 },
       { 1, 5, 8, 4 },
       { 1, 4, 3, 2 },
       { 5, 6, 7, 8 },
    },
   }, -- 8n hex
   {6, 6, 3,
    type = 'WEDGE6', map = false,
    sides = {
       { 1, 2, 5, 4 },
       { 2, 3, 6, 5 },
       { 1, 4, 6, 3 },
       { 1, 3, 2 },
       { 4, 5, 6 },
    },
   }, -- 6n prism
   {7, 5, 3,
    type = 'PYRAMID5', map = false,
    sides = {
       { 1, 2, 5 },
       { 2, 3, 5 },
       { 3, 4, 5 },
       { 1, 5, 4 },
       { 1, 4, 3, 2 },
    },
   }, -- 5n pyr (unsupported in CCX/CGX and old EXODUS II)
   -- 2nd order
   {8, 3, 1}, -- 3n line
   {9, 6, 2, n_corner = 3}, -- 6n tri
   {10, 9, 2}, -- 9n quad
   {11, 10, 3,
    type = 'TETRA10',
    map = {1, 2, 3, 4, 5, 6, 7, 8, 10, 9},
    sides = {
       { 1, 2, 4 },
       { 2, 3, 4 },
       { 1, 4, 3 },
       { 1, 3, 2 },
    },
   }, -- 10n tet
   {12, 27, 3}, -- 27n hex (unknown node ordering in EXODUS II model)
   {13, 18, 3}, -- 18n prism (unknown node ordering in EXODUS II model)
   {14, 14, 3}, -- 14n pyr (unknown node ordering in EXODUS II model)
   -- misc
   {15, 1, 0}, -- point
   -- 2nd serendipity
   {16, 8, 2, n_corner = 4}, -- 8n quad
   {17, 20, 3,
    type = 'HEX20',
    map = {1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 14, 10, 11, 13, 15, 16,
           17, 19, 20, 18},
    sides = {
       { 1, 2, 6, 5 },
       { 2, 3, 7, 6 },
       { 3, 4, 8, 7 },
       { 1, 5, 8, 4 },
       { 1, 4, 3, 2 },
       { 5, 6, 7, 8 },
    },
   }, -- 20n hex (NB: this is EXODUS II order, CCX/CGX has another one!)
   {18, 15, 3,
    type = 'WEDGE15',
    map = {1, 2, 3, 4, 5, 6, 7, 10, 8, 9, 11, 12, 13, 15, 14},
    sides = {
       { 1, 2, 5, 4 },
       { 2, 3, 6, 5 },
       { 1, 4, 6, 3 },
       { 1, 3, 2 },
       { 4, 5, 6 },
    },
   }, -- 15n prism (NB: this is EXODUS II order, CCX/CGX has another one!)
   {19, 13, 3,
    type = 'PYRAMID13',
    map = {1, 2, 3, 4, 5, 6, 9, 11, 7, 8, 10, 12, 13},
    sides = {
       { 1, 2, 5 },
       { 2, 3, 5 },
       { 3, 4, 5 },
       { 1, 5, 4 },
       { 1, 4, 3, 2 },
    },
   }, -- 13n pyr (unsupported in CCX/CGX and old EXODUS-II)
}

local function read_elems(M, f)
   local nelems = gettoks(f)
   local elems = {}
   local elem_map = {}
   local vol_el = { imap = {} }
   local vol_n = { imap = {} }
   local surf_n = { imap = {} }
   local side_tree = {}
   local surf_ss = { imap = {} }
   local max_el = 0

   local function marked_set(sets, mark)
      -- exists?
      local set = sets.imap[mark]
      if not set then
         table.insert(sets, { id = mark } )
         set = #sets
         sets.imap[mark] = set
      end
      return sets[set]
   end

   local function find_min_node_ofs(list, list_ofs, len)
      local node = list[list_ofs+1]
      local ofs = 0
      len = len or #list-list_ofs
      for k = 2, len do
         if list[list_ofs+k] < node then
            ofs = k-1
            node = list[list_ofs+k]
         end
      end
      return ofs
   end

   local function make_ssets()
      --construct sidesets

      -- iterate over elements
      for kel = 1, max_el do
         local el = elems[kel]
         if el then
            -- iterate over sides
            for ks = 1, #el.sides do
               local side = el.sides[ks]
               -- fetch nodes, find rotation offset
               local side_nodes = {}
               local nnodes = #side
               for kn = 1, nnodes do
                  side_nodes[kn] = el[side[kn]]
               end
               local ofs = find_min_node_ofs(side_nodes, 0)

               -- traverse prefix tree
               local sptr, kn = side_tree, 0
               while sptr and kn < nnodes do
                  local node = assert(side_nodes[1 + (kn + ofs) % nnodes])
                  sptr = sptr[node]
                  kn = kn+1
               end

               local phy = sptr and sptr[0]

               if phy then
                  -- identified side

                  -- insert side set
                  local sset = marked_set(surf_ss, phy)
                  table.insert(sset, { el = kel, side = ks } )
               end

            end
         end
      end
   end

   for _ = 1, nelems do
      local ls = {gettoks(f)}
      -- parse element description
      local i = ls[1]
      if i > max_el then
         max_el = i
      end
      local t = ls[2]
      local ntags = ls[3]
      assert(ntags >= 2, 'Invalid number of tags for element ' .. i)
      local phy = ls[4]
      local geom = ls[5]
      local nix = 3 + ntags

      -- parse nodes
      local elty = elemtable[t]
      assert(elty, 'Unknown element type ' .. t)

      -- use geometric ID for unphysical elements (?)
      if phy == 0 then
         phy = geom
      end

      if elty[3] == 3 then
         -- 3D element, register, add element to set, add nodes to set
         local el = {}
         elems[i] = el
         elem_map[i] = true

         el.id = phy
         el.type = assert(elty.type,
                          'Element type unsupported in the model ' .. t)
         el.sides = elty.sides

         -- mark volume element set
         local nset = marked_set(vol_el, phy)
         nset[i] = true

         -- mark nodes in volume node set
         nset = marked_set(vol_n, phy)

         -- proceed with nodes
         local nnodes = elty[2]

         for kn = 1, nnodes do
            local node
            if not elty.map then
               node = ls[nix+kn]
            else
               -- map node index
               node = ls[nix + elty.map[kn] ]
            end
            el[kn] = node
            nset[node] = true
            M.node_map[node] = true
         end
      elseif elty[3] == 2 then
         -- 2D element, add nodes to set

         -- mark nodes in surface node set
         local nset = marked_set(surf_n, phy)

         -- proceed with nodes
         local nnodes = elty[2]

         for kn = 1, nnodes do
            local node = ls[nix+kn]
            nset[node] = true
            M.node_map[node] = true
         end

         -- record element side
         -- identify side by ordered corner nodes
         -- rotate side so node with minimal number is the 1st
         local ncorn = elty.n_corner
         local ofs = find_min_node_ofs(ls, nix, ncorn)

         -- store side
         -- local pointer to prefix-tree
         local sptr = side_tree
         for kn = 0, ncorn-1 do
            local node = ls[nix + 1 + (kn + ofs) % ncorn]
            local sptr_new = sptr[node] or {}
            sptr[node] = sptr_new
            sptr = sptr_new
         end
         assert(not sptr[0], 'Overlapping surface elements')
         sptr[0] = phy
      end
      -- ignore 1D, 0D elements
   end

   end_section(f, 'Elements')

   make_ssets()

   M.elems = elems
   M.nelems = max_el
   M.elem_map = elem_map
   M.vol_n = vol_n
   M.vol_el = vol_el
   M.surf_n = surf_n
   M.surf_ss = surf_ss

end

local function skip_section(f, name)
   local ename = '$End' .. string.sub(name, 2)
   local l = name
   while l ~= ename do
      l = getline(f)
   end
end

local function read_msh2(fname)
   local f = assert(io.open(fname, 'r'))
   read_fmt(f)
   local mesh = {}
   local stage = 0

   while stage ~= 2 do
      local l = getline(f)
      if l == '$Nodes' and stage == 0 then
         read_nodes(mesh, f)
         stage = stage + 1
      elseif l == '$Elements' and stage == 1 then
         read_elems(mesh, f)
         stage = stage + 1
      else
         skip_section(f, l)
      end
   end
   f:close()

   return mesh
end

return {
   read_msh2 = read_msh2,
}
