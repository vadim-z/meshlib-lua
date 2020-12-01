local R = require('meshlib.read_msh2')
local U = require('meshlib.utils')
local gap = require('meshlib.mkgap')

local function init_mesh_FEM(M, MF)
   -- node_number -> vol_set_number*local_number
   MF.inv_nodes_local = {}
   -- local_number -> node_number
   MF.nodes_local = {}

   -- split nodes
   for kv = 1, #M.vol_n do
      local nodes_loc = {}
      MF.nodes_local[kv] = nodes_loc
      for kn = 1, M.nnodes do
         if M.vol_n[kv][kn] then
            table.insert(nodes_loc, kn)
            assert(not MF.inv_nodes_local[kn],
                   string.format('Node %u found in multiple volumes', kn))
            MF.inv_nodes_local[kn] = { vol_n = kv, node = #nodes_loc }
         end
      end
   end

   -- lists of surface nodes
   MF.nodes_lists = {}
   MF.nodes_lists.surf = {}
   for ks = 1, #M.surf_n do
      MF.nodes_lists.surf[ks] = {}
      for kv = 1, #M.vol_n do
         MF.nodes_lists.surf[ks][kv] = {}
      end
      for kn = 1, M.nnodes do
         if M.surf_n[ks][kn] then
            local node_loc = MF.inv_nodes_local[kn]
            table.insert(MF.nodes_lists.surf[ks][node_loc.vol_n],
                         node_loc.node)
         end
      end
   end

   -- lists of volume nodes
   MF.nodes_lists.vol = {}
   for kv = 1, #M.vol_n do
      MF.nodes_lists.vol[kv] = {}
      MF.nodes_lists.vol[kv][kv] = {}
      for kn = 1, #MF.nodes_local[kv] do
         table.insert(MF.nodes_lists.vol[kv][kv], kn)
      end
   end

   MF.els_local = {}

   -- split elements
   for kv = 1, #M.vol_el do
      local els_loc = {}
      MF.els_local[kv] = els_loc
      for ke = 1, M.nelems do
         if M.vol_el[kv][ke] then
            table.insert(els_loc, ke)
         end
      end
   end
end

-- function to make FEM mesh without partitioning
local function init_mesh_FEM_nopart(M, MF)
   -- node_number -> vol_set_number*local_number
   MF.inv_nodes_local = {}
   -- local_number -> node_number
   MF.nodes_local = {}

   -- add nodes, don't split
   local kv = -1
   local nodes_loc = {}
   MF.nodes_local[kv] = nodes_loc
   for kn = 1, M.nnodes do
      table.insert(nodes_loc, kn)
      MF.inv_nodes_local[kn] = { vol_n = kv, node = #nodes_loc }
   end

   -- lists of surface nodes
   MF.nodes_lists = {}
   MF.nodes_lists.surf = {}
   for ks = 1, #M.surf_n do
      MF.nodes_lists.surf[ks] = {}
      MF.nodes_lists.surf[ks][kv] = {}
      for kn = 1, M.nnodes do
         if M.surf_n[ks][kn] then
            table.insert(MF.nodes_lists.surf[ks][kv], kn)
         end
      end
   end

   -- lists of volume nodes
   MF.nodes_lists.vol = {}
   for kvl = 1, #M.vol_n do
      MF.nodes_lists.vol[kvl] = {}
      MF.nodes_lists.vol[kvl][kv] = {}
      for kn = 1, M.nnodes do
         if M.vol_n[kvl][kn] then
            table.insert(MF.nodes_lists.vol[kvl][kv], kn)
         end
      end
   end

   MF.els_local = {}

   -- add elements, don't split
   local els_loc = {}
   MF.els_local[kv] = els_loc
   for ke = 1, M.nelems do
      table.insert(els_loc, ke)
   end
end

local mesh_class = {}

-- void mesh_init(char *mesh_file_name,
--     double Rf_ex, double Rcl_in,
--     int phys_pel, int phys_clad,
--     int phys_surf_pel, int phys_surf_clad);
function mesh_class:init(mesh_file_name, Rf_ex, Rcl_in,
                         phys_pel, phys_clad,
                         phys_surf_pel, phys_surf_clad)
   self.mesh = R.read_msh2(mesh_file_name)
   U.compress_mesh(self.mesh)
   self.mesh_FEM = {}
   local part = phys_pel >= 0 and phys_clad >= 0 and
      phys_surf_pel >= 0 and phys_surf_clad >= 0

   if part then
      gap.mkgap(self.mesh,
                {phys_pel, surf_id = phys_surf_pel},
                {phys_clad, surf_id = phys_surf_clad},
                Rcl_in/Rf_ex)
      init_mesh_FEM(self.mesh, self.mesh_FEM)
   else
      self.mesh.twin1, self.mesh.twin2 = {}, {}
      init_mesh_FEM_nopart(self.mesh, self.mesh_FEM)
   end
end

local dom_def = {
   {
      list_tag = 'surf',
      imap_tag = 'surf_n',
      name = 'Surface',
   },
   {
      list_tag = 'vol',
      imap_tag = 'vol_n',
      name = 'Volume',
   }
}

local function ckdom(self, dom_kind, dom_id)
   local def = assert(dom_def[dom_kind], 'Invalid domain kind: ' .. dom_kind)

   local phys = assert(self.mesh[def.imap_tag].imap[dom_id],
                       ('%s physical not found: %u'):format(def.name, dom_id))
   return phys, def.list_tag
end

local function ckphys(self, phys)
   -- special exception
   return (phys < 0 and phys) or ckdom(self, 2, phys)
end

-- int mesh_nnodes(int phys, int *nnodes);
function mesh_class:nnodes(phys)
   return #self.mesh_FEM.nodes_local[ckphys(self, phys)]
end

-- int mesh_node_coords(int phys, int node, double coord[3]);
function mesh_class:node_coords(phys, lnode)
   -- nodes are numbered from 0
   local knode = self.mesh_FEM.nodes_local[ckphys(self, phys)][lnode+1]
   local coords = assert(self.mesh.nodes[knode],
                       string.format('Node %u phys %u not found',
                                     lnode, phys))
   assert(phys < 0 or self.mesh.vol_n[ckphys(self, phys)][knode])
   return coords
end

-- int mesh_ntwins(int *ntwins);
function mesh_class:ntwins()
   return #self.mesh.twin1
end

-- int mesh_twin_pair(int ktwin, int *ktwin1, int *ktwin2);
function mesh_class:twin_pair(ktwin)
   local t1 = self.mesh_FEM.inv_nodes_local[self.mesh.twin1[ktwin+1]]
   local t2 = self.mesh_FEM.inv_nodes_local[self.mesh.twin2[ktwin+1]]
   assert(t1 and t2, 'Twin not found: ' .. ktwin)
   assert(t1.vol_n == 1 and t2.vol_n == 2)
   return t1.node-1, t2.node-1
end

local function dom_to_nset(self, phys, dom_kind, dom_id)
   local phys_dom, tag = ckdom(self, dom_kind, dom_id)
   return self.mesh_FEM.nodes_lists[tag][phys_dom][ckphys(self, phys)]
end

-- int mesh_nnodes_set(int phys, int dom_kind, int id_set, int *nnodes);
function mesh_class:nnodes_set(phys, dom_kind, dom_id)
   return #(dom_to_nset(self, phys, dom_kind, dom_id))
end

-- int mesh_node_set(int phys, int dom_kind, int id_set, int knode, int *nnode);
function mesh_class:node_set(phys, dom_kind, dom_id, knode)
   return assert(dom_to_nset(self, phys, dom_kind, dom_id)[knode+1],
                 string.format('Node %u kind %u id %u phys %u not found',
                               knode, dom_kind, dom_id, phys)) - 1
end

local function ckphyse(self, phys)
   return (phys < 0 and phys) or
      assert(self.mesh.vol_el.imap[phys],
             'Physical not found: ' .. phys)
end

-- int mesh_nels(int phys, int *nels);
function mesh_class:nels(phys)
   return #self.mesh_FEM.els_local[ckphyse(self, phys)]
end

local Z88_node_map = {
   1, 2, 3, 4, 5, 6, 7, 9, 10, 8
}

-- int mesh_el_tet10(int phys, int kel, int nodes[10]);
function mesh_class:el_tet10(phys, loc_el)
      -- elements are numbered from 0
   local kel = self.mesh_FEM.els_local[ckphyse(self, phys)][loc_el+1]
   local el = assert(self.mesh.elems[kel],
                     string.format('Elt %u phys %u not found',
                                   loc_el, phys))
   assert(el.type == 'TETRA10', 'Incorrect element type')
   assert(phys < 0 or el.id == phys)
   local r = {}
   for k = 1, #Z88_node_map do
      local kn = el[Z88_node_map[k]]
      local node_loc = self.mesh_FEM.inv_nodes_local[kn]
      assert(node_loc and (phys < 0 or node_loc.vol_n == ckphys(self, phys)))
      r[k] = node_loc.node - 1
   end
   return r
end

-- external functions
-- int mesh_func_init(char *fname)
function mesh_class:func_init(fname)
   local env = setmetatable({}, { __index = _G })
   assert(loadfile(fname, 't', env))()
   self.func_env = env
end

-- int mesh_func_call(char *func_fname, char *params, double *res, ...)
function mesh_class:func_call(func_file_name, ...)
   local f = assert((self.func_env or {})[func_file_name])
   return f(...)
end

local function mesh()
   return setmetatable({}, { __index = mesh_class } )
end

return {
   mesh = mesh,
}
