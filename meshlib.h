#ifndef __MESHLIB_H
#define __MESHLIB_H

#define MESH_NOPART -1

typedef enum {
  MESH_surf = 1,
  MESH_vol = 2
} mesh_dom;

int meshlib_init(const char *libpath);
void meshlib_close(void);

int mesh_init(const char *mesh_file_name, double Rf_ex, double Rcl_in, 
		int phys_pel, int phys_clad,
		int phys_surf_pel, int phys_surf_clad);
/* Get nodes */
int mesh_nnodes(int phys, int *nnodes);
int mesh_node_coords(int phys, int node, double coord[3]);
int mesh_ntwins(int *ntwins);
int mesh_twin_pair(int ktwin, int *ktwin1, int *ktwin2);
int mesh_nnodes_set(int phys, mesh_dom dom_kind, int id_set, int *nnodes);
int mesh_node_set(int phys, mesh_dom dom_kind, int id_set, int knode, int *nnode);

/* Get elements */
int mesh_nels(int phys, int *nels);
int mesh_el_tet10(int phys, int kel, int nodes[10]);

/* Call external functions */
int mesh_func_init(const char *func_file_name);
int mesh_func_call(const char *func_name, const char *params, double *res, ...);

#endif
