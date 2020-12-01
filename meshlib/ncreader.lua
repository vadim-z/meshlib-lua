-- Native support of NetCDF in Lua
-- Reader module

-- NetCDF constant namespace
local NC = {
   BYTE = 1,
   CHAR = 2,
   SHORT = 3,
   INT = 4,
   FLOAT = 5,
   DOUBLE = 6,

   DIMENSION = 10,
   VARIABLE = 11,
   ATTRIBUTE = 12,
}

-- File class
local NCReaderClass = {}

-- shortcuts
local sunpack = string.unpack
local spacksize = string.packsize

-- padding and alignment
local function pad4len(len)
   return 3 - (len-1)%4
end

-- format strings for types
local type_fmt = {
   [ NC.BYTE ] = '>b',
   [ NC.CHAR ] = '>c1', -- ???
   [ NC.SHORT ] = '>i2',
   [ NC.INT ] = '>i4',
   [ NC.FLOAT ] = '>f',
   [ NC.DOUBLE ] = '>d',
}

local type_sz = {}
for t, s in pairs(type_fmt) do
   type_sz[t] = spacksize(s)
end

-- read array of typed elements
local function read_typevals(f, typ, n, pad)
   local len = type_sz[typ]*n
   if pad then
      len = len + pad4len(len)
   end
   local bin = f:read(len)
   local arr = {}
   local pos = 1
   for k = 1, n do
      arr[k], pos = sunpack(type_fmt[typ], bin, pos)
   end
   return arr
end

-- block for creating netCDF file and writing the header
do
   -- read 4-byte signed integer
   local function read_i4(f)
      return (sunpack('>i4', f:read(4)))
   end

   -- read 4-aligned variable length string
   local function read_vls(f)
      local len = read_i4(f)
      -- read padded string and extract substring
      return f:read(len + pad4len(len)):sub(1, len)
   end

   -- read value by format
   local function read_val(f, fmt, sz)
      return (sunpack(fmt,f:read(sz)))
   end

   -- Elements of NetCDF-1/2 format
   -- FIXME: names of vars, dims and atts are not checked according to specification

   -- private functions
   -- read dim_list object
   local function read_dim_list(self)
      local f = self.f
      local dim_list = { map = {} }
      self.dim_list = dim_list

      local tag = read_i4(f)
      local ndims = read_i4(f)
      if tag == 0 then
         -- No dimensions
         return
      end
      assert(tag == NC.DIMENSION, 'Expected dimensions list')

      -- read and process the dimensions
      local fixed = true -- are all dimensions fixed?

      for kdim = 1, ndims do
         local dim_name = read_vls(f)
         local dim_size = read_i4(f)

         assert(dim_size >= 0, 'Invalid dimension ' .. dim_name)
         local rec = dim_size == 0
         assert(fixed or not rec,
                'More than one record dimension is not supported in classic NetCDF')
         fixed = fixed and not rec

         if rec then
            dim_list.rec_dim = kdim
         end
         local dim = { name = dim_name, size = dim_size }
         dim_list[kdim] = dim
         dim_list.map[dim_name] = dim
      end

      self.dim_list = dim_list
   end

   -- read (local) att_list object
   local function read_local_att_list(f)
      local att_list = { map = {} }

      local tag = read_i4(f)
      local natts = read_i4(f)
      if tag == 0 then
         -- No attributes
         return att_list
      end
      assert(tag == NC.ATTRIBUTE, 'Expected attributes list')

      -- read and process the attributes
      for katt = 1, natts do
         local att_name = read_vls(f)
         local att_type = read_i4(f)
         local att
         if att_type == NC.CHAR then
            -- read character attribute as string
            att = { string = read_vls(f) }
         else
            -- read as array
            local size = read_i4(f)
            att = read_typevals(f, att_type, size, true)
            att.name = att_name
         end

         att.name = att_name
         att.type = att_type
         att_list[katt] = att
         att_list.map[att_name] = att
      end

      return att_list
   end

   -- read att_list object
   local function read_att_list(self)
      self.att_list = read_local_att_list(self.f)
   end

   -- read var_list object
   local function read_var_list(self)
      local f = self.f
      local var_list = { map = {} }
      self.var_list = var_list

      local tag = read_i4(f)
      local nvars = read_i4(f)
      if tag == 0 then
         -- No variables
         return
      end
      assert(tag == NC.VARIABLE, 'Expected variables list')

      local n_rec_vars = 0 -- do we need to pack records? count record vars
      local rec_size = 0 -- total size of one record
      local packed_rec_size = 0

      for kvar = 1, nvars do
         -- read the variable
         local var_name = read_vls(f)
         local var_rank = read_i4(f)
         local var_dims = read_typevals(f, NC.INT, var_rank, false)
         local var_att_list = read_local_att_list(f)
         local var_type = read_i4(f)
         local var_vsize = read_i4(f)
         local var_begin = read_val(f, self.offset_fmt, self.offset_size)
         local var = {
            name = var_name,
            rank = var_rank,
            dims = var_dims,
            atts = var_att_list,
            type = var_type,
            vsize = var_vsize,
            begin = var_begin
         }

         -- process the variable
         local n_items = 1
         local n_items_s = 1
         local len_s
         for kdim = 1, var_rank do
            -- increment
            local dim_ix = var_dims[kdim] + 1
            var_dims[kdim] = dim_ix
            local locrec = dim_ix == self.dim_list.rec_dim
            if kdim == 1 then
               -- is the variable record ?
               -- determine from the 1st dimension
               var.rec = locrec
            else
               assert(not locrec,
                      'Only the first dimension can be unlimited for variable '
                         .. var_name)
            end

            -- take the dimension into account
            if kdim > 1 or not locrec then
               n_items = n_items * self.dim_list[dim_ix].size
               if var_type == NC.CHAR then
                  if kdim < var_rank then
                     -- item is a number, or a string
                     -- string is written as one item
                     -- so we may exclude the last dimension for
                     -- character variables specified as
                     -- (an array of) strings
                     n_items_s = n_items
                  else
                     len_s = self.dim_list[dim_ix].size
                  end
               end
            end
         end -- loop over dimensions

         var.n_items = n_items
         var.n_items_s = n_items_s
         var.len_s = len_s
         var.real_vsize = n_items * type_sz[var_type]

         if var.rec then
            -- record
            n_rec_vars = n_rec_vars + 1
            rec_size = rec_size + var_vsize
            -- in case there's only one record var
            packed_rec_size = var.real_vsize
         end

         -- store var
         var_list[kvar] = var
         var_list.map[var_name] = var
      end

      -- pack records?
      if n_rec_vars == 1 then
         -- pack record variables
         rec_size = packed_rec_size
      end

      -- store results
      self.var_list = var_list
      self.rec_size = rec_size
   end

   -- read header; set important flags
   local function read_hdr(self)
      local f = self.f
      local sgn = f:read(4)

      if sgn == 'CDF\1' then
         self.offset_size = 4
         self.offset_fmt = '> i4'
      elseif sgn == 'CDF\2' then
         self.offset_size = 8
         self.offset_fmt = '> i8'
      else
         error('Unsupported netCDF format')
      end

      -- initialize number of records
      self.num_recs = read_i4(f)
      if self.num_recs < 0 then
         -- streaming mode
         self.num_recs = math.maxinteger
      end

      -- read dimensions, attributes, variables
      read_dim_list(self)
      read_att_list(self)
      read_var_list(self)
   end

   -- public method: open netCDF file, read the header
   function NCReaderClass:open(fname)
      self.f = assert(io.open(fname, 'rb'))
      read_hdr(self)
   end
end

-- block for reading values from netCDF files
do

   -- private functions

   -- read array of zero-padded strings
   -- padding removed
   local function read_zstrings(f, n, len_s, pad)
      local len = n*len_s
      if pad then
         len = len + pad4len(len)
      end
      local bin = f:read(len)
      local arr = {}
      local pos = 1
      for k = 1, n do
         local newpos = pos + len_s
         local s = bin:sub(pos, newpos-1)
         pos = newpos
         -- remove trailing nulls
         arr[k] = s:match('^.*[^\0]') or ''
      end
      return arr
   end

   -- read block of data given variable and record index
   local function read_data(self, var, irec, as_array)
      local f = self.f

      -- find offset and seek
      local offs = var.begin
      if var.rec then
         assert(irec and irec <= self.num_recs,
                'Index of record missing or invalid when reading record variable')
         -- add required number of records
         offs = offs + (irec-1)*self.rec_size
      end
      self.f:seek('set', offs)

      local rank = var.rank

      -- type/rank correspondence:
      -- */0 <--> scalar data
      -- char/1 <--> string
      -- */>0 <--> flat table

      -- no padding in read because we fseek anyway

      -- scalar cases
      if rank == 0 or var.rec and rank == 1 then
         -- read scalar
         -- by definition, character rank-1 records go there too
         assert(var.n_items == 1,
                'Internal error: bad number of items for scalar variable')
         return read_typevals(f, var.type, 1, false)[1]
      elseif (rank == 1 or var.rec and rank == 2)
      and var.type == NC.CHAR and not as_array then
         -- read string as 'scalar':
         -- rank-1 fixed variable or rank-2 record
         -- remove trailing null chars, see writer module
         assert(var.n_items_s == 1,
                'Internal error: bad number of items for scalar variable')
         return read_zstrings(f, 1, var.len_s, false)[1]
      elseif var.type == NC.CHAR and not as_array then
         -- flat array of strings,
         -- fixed of rank > 1 or record of rank > 2
         return read_zstrings(f, var.n_items_s, var.len_s, false)
      else
         -- flat array of typed values
         return read_typevals(f, var.type, var.n_items, false)
      end
   end

   -- public method: read a fixed or record variable from netCDF file
   -- nrec may be missing in case of fixed variable
   function NCReaderClass:read_var(name, irec, as_array)
      local var = self.var_list.map[name]
      assert(var, 'Unknown variable ' .. name)
      return read_data(self, var, irec, as_array)
   end

   -- public method: read every fixed/record variable from netCDF file
   -- all character arrays are read as strings
   -- give irec to read record variables for that record,
   -- omit or give nil or false to read all fixed variables
   function NCReaderClass:read_vars(irec)
      local arr = {}
      for _, var in ipairs(self.var_list) do
         if not var.rec == not irec then
            arr[var.name] = read_data(self, var, irec, false)
         end
      end

      return arr
   end

end

-- public method: close netCDF file
function NCReaderClass:close()
   self.f:close()
end

-- constructor
local function NCReader()
   return setmetatable({}, { __index = NCReaderClass } )
end

return {
   NC = NC,
   NCReader = NCReader,
}
