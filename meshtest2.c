#include<stdio.h>
#include<stdlib.h>
#include<math.h>
#include"meshlib.h"

double dist(const double x[3], const double y[3]) {
  double sum = 0.0;
  int k;
  for (k = 0; k < 3; k++) {
    sum = sum + (x[k]-y[k])*(x[k]-y[k]);
  }
  return sqrt(sum);
}

int cmp_nodes(const int n1[10], const int n2[10]) {
  int l = 1;
  int k;
  for (k = 0; k < 10; k++) {
    l = l && (n1[k] == n2[k]);
  }
  return l;
}

#define CHECK(cond) if (!(cond)) {					\
    fprintf(stderr, "Check failed in %s line %d\n", __FILE__, __LINE__); exit(1); } \
  else fprintf(stderr, "Check passed in %s line %d\n", __FILE__, __LINE__)

int main(void) {
  int res, nnodes, ntwins, node1, nnodes_set, nels, nodes[10];
  double coo[3];
  const double cooref[3] = { 3.900000, 0.000000, 5.275000 };
  const int nodesref[10] = { 30188, 30194, 8987, 30196, 30673, 
			     30713, 30706, 30714, 30705, 30704 };
  res = meshlib_init(".");
  CHECK(res == 0);
  res = mesh_init("fclad.msh", 0.0, 0.0, MESH_NOPART, MESH_NOPART,
		  MESH_NOPART, MESH_NOPART);
  CHECK(res == 0);
  res = mesh_nnodes(MESH_NOPART, &nnodes);
  CHECK(res == 0 && nnodes == 50884);
  res = mesh_node_coords(MESH_NOPART, 116, coo);
  CHECK(res == 0 && dist(coo, cooref) < 1.e-10);
  res = mesh_ntwins(&ntwins);
  CHECK(res == 0 && ntwins == 0);
  res = mesh_nnodes_set(MESH_NOPART, MESH_surf, 13, &nnodes_set);
  CHECK(res == 0 && nnodes_set == 1489);
  res = mesh_node_set(MESH_NOPART, MESH_surf, 13, 17, &node1);
  CHECK(res == 0 && node1 == 239);
  res = mesh_nels(MESH_NOPART, &nels);
  CHECK(res == 0 && nels == 33164);
  res = mesh_el_tet10(MESH_NOPART, 11678, nodes);
  CHECK(res == 0 && cmp_nodes(nodes, nodesref));
  meshlib_close();
  fprintf(stderr, "All tests passed.\n");
  return 0;
}
