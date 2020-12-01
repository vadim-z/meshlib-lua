#include<stdio.h>
#include<stdarg.h>
#include<math.h>
#include<assert.h>
#include"lua.h"
#include"lauxlib.h"
#include"lualib.h"
#include"meshlib.h"

static lua_State *L_st;

int meshlib_init(char *libpath) {
  char psep;
  int err;

  /* Init Lua */
  L_st = luaL_newstate();
  luaL_openlibs(L_st);

  /* Push library path and append startup file name */
  lua_pushstring(L_st, libpath);
  lua_getglobal(L_st, "package");
  lua_getfield(L_st, -1, "config");
  psep = *(lua_tostring(L_st, -1));
  lua_pop(L_st, 2);
  lua_pushlstring(L_st, &psep, 1);
  lua_pushliteral(L_st, "meshlib");
  lua_pushlstring(L_st, &psep, 1);
  lua_pushliteral(L_st, "cstart.lua");
  lua_concat(L_st, 5);

  /* Load startup file */
  err = luaL_loadfile(L_st, lua_tostring(L_st, -1));
  if (err == LUA_OK) {
    lua_pushstring(L_st, libpath);
    /* Execute startup file */
    err = lua_pcall(L_st, 1, 0, 0);
  }
  if (err != LUA_OK) {
    fprintf(stderr, "Failed to load Lua library: %s\n", lua_tostring(L_st, -1));
    /* Pop error */
    lua_pop(L_st, 1);
  }
  /* Pop filename */
  lua_pop(L_st, 1);

  if (err == LUA_OK) {
    int t;
    /* Push and check mesh object */
    assert(lua_gettop(L_st) == 0);
    t = lua_getglobal(L_st, "mesh");
    assert(t == LUA_TTABLE);
  }
  return err;
}

void meshlib_close(void) {
  lua_close(L_st);
}

/* Convenience macros */

#define METHOD(m) { int t; /* Check mesh object */ assert(lua_gettop(L_st) == 1); \
    t = lua_getfield(L_st, -1, m);	\
    assert(t == LUA_TFUNCTION); \
    lua_pushvalue(L_st, 1); /* Self */ }

#define CKINT() assert(lua_isinteger(L_st, -1))

#define CKDOUBLE() assert(lua_isnumber(L_st, -1))

#define ERR() { fprintf(stderr, "Error in %s line %d: %s\n", __FILE__, __LINE__, \
			lua_tostring(L_st, -1)); /* Pop error */ lua_pop(L_st, 1); }

#define END() { assert(lua_gettop(L_st) == 1); return err; }


int mesh_init(char *mesh_file_name,
	      double Rf_ex, double Rcl_in, 
	      int phys_pel, int phys_clad,
	      int phys_surf_pel, int phys_surf_clad) {
  int err;

  METHOD("init");
  lua_pushstring(L_st, mesh_file_name);
  lua_pushnumber(L_st, Rf_ex);
  lua_pushnumber(L_st, Rcl_in);
  lua_pushinteger(L_st, phys_pel);
  lua_pushinteger(L_st, phys_clad);
  lua_pushinteger(L_st, phys_surf_pel);
  lua_pushinteger(L_st, phys_surf_clad);
  
  err = lua_pcall(L_st, 8, 0, 0);
  if (err != LUA_OK) {
    ERR();
  }

  END();
}

int mesh_nnodes(int phys, int *nnodes) {
  int err;

  METHOD("nnodes");
  lua_pushinteger(L_st, phys);
  
  err = lua_pcall(L_st, 2, 1, 0);
  if (err == LUA_OK) {
    /* Get and pop result */
    CKINT();
    *nnodes = lua_tointeger(L_st, -1);
    lua_pop(L_st, 1);
  } else {
    ERR();
  }

  END();
}

int mesh_node_coords(int phys, int node, double coord[3]) {
  int err, k;

  METHOD("node_coords");
  lua_pushinteger(L_st, phys);
  lua_pushinteger(L_st, node);
  
  err = lua_pcall(L_st, 3, 1, 0);
  if (err == LUA_OK) {
    /* Check coordinate table */
    assert(lua_istable(L_st, -1));
    assert(lua_rawlen(L_st, -1) == 3);
    /* Get and pop result */
    for (k = 0; k < 3; k++) {
      int t = lua_rawgeti(L_st, -1, k+1);
      assert(t == LUA_TNUMBER);
      coord[k] = lua_tonumber(L_st, -1);
      lua_pop(L_st, 1);
    }
    lua_pop(L_st, 1);
  } else {
    ERR();
  }

  END();
}

int mesh_ntwins(int *ntwins) {
  int err;

  METHOD("ntwins");
  
  err = lua_pcall(L_st, 1, 1, 0);
  if (err == LUA_OK) {
    /* Get and pop result */
    CKINT();
    *ntwins = lua_tointeger(L_st, -1);
    lua_pop(L_st, 1);
  } else {
    ERR();
  }

  END();
}

int mesh_twin_pair(int ktwin, int *ktwin1, int *ktwin2) {
  int err;

  METHOD("twin_pair");
  lua_pushinteger(L_st, ktwin);
  
  err = lua_pcall(L_st, 2, 2, 0);
  if (err == LUA_OK) {
    /* Get and pop result */
    CKINT();
    *ktwin2 = lua_tointeger(L_st, -1);
    lua_pop(L_st, 1);
    CKINT();
    *ktwin1 = lua_tointeger(L_st, -1);
    lua_pop(L_st, 1);
  } else {
    ERR();
  }

  END();
}

int mesh_nnodes_set(int phys, mesh_dom dom_kind, int id_set, int *nnodes) {
  int err;

  METHOD("nnodes_set");
  lua_pushinteger(L_st, phys);
  lua_pushinteger(L_st, dom_kind);
  lua_pushinteger(L_st, id_set);
  
  err = lua_pcall(L_st, 4, 1, 0);
  if (err == LUA_OK) {
    /* Get and pop result */
    CKINT();
    *nnodes = lua_tointeger(L_st, -1);
    lua_pop(L_st, 1);
  } else {
    ERR();
  }

  END();
}

int mesh_node_set(int phys, mesh_dom dom_kind, int id_set, int knode, int *nnode) {
  int err;

  METHOD("node_set");
  lua_pushinteger(L_st, phys);
  lua_pushinteger(L_st, dom_kind);
  lua_pushinteger(L_st, id_set);
  lua_pushinteger(L_st, knode);
  
  err = lua_pcall(L_st, 5, 1, 0);
  if (err == LUA_OK) {
    /* Get and pop result */
    CKINT();
    *nnode = lua_tointeger(L_st, -1);
    lua_pop(L_st, 1);
  } else {
    ERR();
  }

  END();
}

int mesh_nels(int phys, int *nels) {
  int err;

  METHOD("nels");
  lua_pushinteger(L_st, phys);
  
  err = lua_pcall(L_st, 2, 1, 0);
  if (err == LUA_OK) {
    /* Get and pop result */
    CKINT();
    *nels = lua_tointeger(L_st, -1);
    lua_pop(L_st, 1);
  } else {
    ERR();
  }

  END();
}

int mesh_el_tet10(int phys, int kel, int nodes[10]) {
  int err, k;

  METHOD("el_tet10");
  lua_pushinteger(L_st, phys);
  lua_pushinteger(L_st, kel);
  
  err = lua_pcall(L_st, 3, 1, 0);
  if (err == LUA_OK) {
    /* Check element table */
    assert(lua_istable(L_st, -1));
    assert(lua_rawlen(L_st, -1) == 10);
    /* Get and pop result */
    for (k = 0; k < 10; k++) {
      lua_rawgeti(L_st, -1, k+1);
      CKINT();
      nodes[k] = lua_tointeger(L_st, -1);
      lua_pop(L_st, 1);
    }
    lua_pop(L_st, 1);
  } else {
    ERR();
  }

  END();
}

int mesh_func_init(char *func_file_name) {
  int err;

  METHOD("func_init");
  lua_pushstring(L_st, func_file_name);

  err = lua_pcall(L_st, 2, 0, 0);
  if (err != LUA_OK) {
    ERR();
  }

  END();
}

int mesh_func_call(char *func_name, char *params, double *res, ...) {
  va_list aptr;
  int nargs, err;

  va_start(aptr, res);
  METHOD("func_call");

  lua_pushstring(L_st, func_name);

  nargs = 2; /* self, name */
  while (*params) {
    switch (*params) {
    case 'i':
      lua_pushinteger(L_st, va_arg(aptr, int));
      nargs++;
      break;
    case 'd':
      lua_pushnumber(L_st, va_arg(aptr, double));
      nargs++;
      break;
    case 'c':
      lua_pushstring(L_st, va_arg(aptr, char *));
      nargs++;
      break;
    default:
      /* Ignore unknown type of parameter */
      break;
    }
    params++;
  }

  err = lua_pcall(L_st, nargs, 1, 0);
  if (err == LUA_OK) {
    /* Get and pop result */
    if (lua_isnumber(L_st, -1)) {
      *res = lua_tonumber(L_st, -1);
    } else {
      fprintf(stderr, "Function %s returned %s instead of number\n",
	      func_name, luaL_typename(L_st, -1));
#ifdef NAN
      *res = NAN;
      /* If NAN is undefined, do nothing */
#endif
    }
    /* Pop value */
    lua_pop(L_st, 1);
  } else {
    ERR();
  }

  va_end(aptr);
  END();
}
