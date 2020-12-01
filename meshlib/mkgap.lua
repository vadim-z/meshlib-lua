-- find node/el sets by ids
local function find_id(sets, id)
   local k = 1
   while k <= #sets and sets[k].id ~= id do
      k = k+1
   end
   -- false if not found
   return (k <= #sets) and k
end

-- return list corresponding to ids
local function sets_by_ids(sets, ids)
   local list = {}
   for k, id in ipairs(ids) do
      list[k] = assert(find_id(sets, id),
                       'id not found: ' .. id)
   end

   return list
end

-- identify nodes belonging to both domains
-- add twin nodes to the list
local function add_twin_map(mesh, k_last, twin_map, vn1, vn2)
   for k = 1, mesh.nnodes do
      if mesh.vol_n[vn1][k] and mesh.vol_n[vn2][k] and not twin_map[k] then
         -- make new twin of this node
         k_last = k_last + 1
         twin_map[k] = k_last
      end
   end
   return k_last
end

-- calculate set of points which belong to domain 1 or 2 (any volume inside)
-- but not their interface
local function domain_set(mesh, vns, twin_map)
   local dset = {}
   for _, kvol in ipairs(vns) do
      for node, _ in pairs(mesh.vol_n[kvol]) do
         if node ~= 'id' then
            dset[node] = true
         end
      end
   end
   -- subtract interface
   for node, _ in pairs(twin_map) do
      dset[node] = nil
   end

   return dset
end

-- find which surface belongs to which domain (and which belongs the both)
local function classify_surfaces(mesh, dset1, dset2)
   local sflags = {}
   for k, surf in ipairs(mesh.surf_n) do
      local l1, l2 = false, false
      for node, _ in pairs(surf) do
         l1 = l1 or dset1[node]
         l2 = l2 or dset2[node]
      end
      sflags[k] = { l1, l2 }
   end

   return sflags
end

local function update_sets(mesh, twin_map, vn2, ve2, sflags, surf1, surf2)
   for k, ktwin in pairs(twin_map) do
      -- copy node
      local node = {}
      mesh.nodes[ktwin] = node
      for kc, vc in ipairs(mesh.nodes[k]) do
         node[kc] = vc
      end

      -- change volume node set references
      if mesh.vol_n[vn2][k] then
         mesh.vol_n[vn2][k] = nil
         mesh.vol_n[vn2][ktwin] = true
      end
   end

   -- fix elements
   for k = 1, mesh.nelems do
      if mesh.vol_el[ve2][k] then
         local el = mesh.elems[k]
         -- replace all nodes in the twin list by twins
         for kn, node in ipairs(el) do
            local twin = twin_map[node]
            if twin then
               el[kn] = twin
            end
         end
      end
   end

   -- update surfaces
   for knode, ktwin in pairs(twin_map) do
      for ksurf, surf in ipairs(mesh.surf_n) do
         local sfl = sflags[ksurf]
         if surf[knode] and sfl[2] then
            -- need to add twin to the surface
            surf[ktwin] = true
            if not sfl[1] then
               -- need to remove original node
               surf[knode] = nil
            end
         end
      end
   end

   -- add original nodes and twins to new surfaces if required
   for k, ktwin in pairs(twin_map) do
      if surf1 then
         mesh.surf_n[surf1][k] = true
      end
      if surf2 then
         mesh.surf_n[surf2][ktwin] = true
      end
   end
end

-- dilate all nodes belonging to domain list in XY-plane by fac
local function dilate_nodes_xy(mesh, vlist, fac)
   local marked = {}

   for _, kvol in ipairs(vlist) do
      -- iterate over all nodes in volume node set
      for node, _ in pairs(mesh.vol_n[kvol]) do
         if node ~= 'id' and not marked[node] then
            -- do not dilate twice
            marked[node] = true

            mesh.nodes[node][1] = mesh.nodes[node][1]*fac
            mesh.nodes[node][2] = mesh.nodes[node][2]*fac
         end
      end
   end
end

local function twin_lists(twin_map, n)
   local tw1, tw2 = {}, {}
   for k = 1, n do
      local ktwin = twin_map[k]
      if ktwin then
         tw1[#tw1+1] = k
         tw2[#tw2+1] = ktwin
      end
   end
   return tw1, tw2
end

local function mkgap(mesh, id_list1, id_list2, fac)
   local surf1, surf2 = nil, nil

   local function surf_id(id)
      local surf = find_id(mesh.surf_n, id)
      if not surf then
         -- insert new surface node set and get index
         table.insert(mesh.surf_n, { id = id })
      -- surface node sets index
         surf = #mesh.surf_n
      end
      return surf
   end

   if id_list1.surf_id then
      surf1 = surf_id(id_list1.surf_id)
   end

   if id_list2.surf_id then
      surf2 = surf_id(id_list2.surf_id)
   end

   -- volume node sets
   local vn1s = sets_by_ids(mesh.vol_n, id_list1)
   local vn2s = sets_by_ids(mesh.vol_n, id_list2)
   -- volume element sets
   local ve2s = sets_by_ids(mesh.vol_el, id_list2)

   local k_last, twin_map = mesh.nnodes, {}

   for k = 1, #id_list1 do
      k_last = add_twin_map(mesh, k_last, twin_map, vn1s[k], vn2s[k])
   end

   -- calculate domain sets
   local dset1 = domain_set(mesh, vn1s, twin_map)
   local dset2 = domain_set(mesh, vn2s, twin_map)

   -- classify surfaces
   local sflags = classify_surfaces(mesh, dset1, dset2)

   -- update number of nodes
   mesh.nnodes = k_last

   for k = 1, #id_list1 do
      update_sets(mesh, twin_map, vn2s[k], ve2s[k], sflags, surf1, surf2)
   end

   dilate_nodes_xy(mesh, vn2s, fac)

   mesh.twin1, mesh.twin2 = twin_lists(twin_map, mesh.nnodes)
end

return {
   mkgap = mkgap,
}
