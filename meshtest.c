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
  int res, nnodes, ntwins, node1, node2, nnodes_set, nels, nodes[10];
  double coo[3];
  const double cooref[3] = { 4.290000, 0.000000, 5.275000 };
  const int nodesref[10] = { 5832, 5838, 1161, 5840, 6317, 
			     6357, 6350, 6358, 6349, 6348 };
  res = meshlib_init(".");
  CHECK(res == 0);
  res = mesh_init("fclad.msh", 1.0, 1.1, 1, 2, 5, 11);
  CHECK(res == 0);
  res = mesh_nnodes(2, &nnodes);
  CHECK(res == 0 && nnodes == 17900);
  res = mesh_node_coords(2, 10, coo);
  CHECK(res == 0 && dist(coo, cooref) < 1.e-10);
  res = mesh_ntwins(&ntwins);
  CHECK(res == 0 && ntwins == 2729);
  res = mesh_twin_pair(7, &node1, &node2);
  CHECK(res == 0 && node1 == 107 && node2 == 15178);
  res = mesh_nnodes_set(2, MESH_surf, 13, &nnodes_set);
  CHECK(res == 0 && nnodes_set == 481);
  res = mesh_node_set(2, MESH_surf, 13, 17, &node1);
  CHECK(res == 0 && node1 == 199);
  res = mesh_nels(2, &nels);
  CHECK(res == 0 && nels == 10321);
  res = mesh_el_tet10(2, 71, nodes);
  CHECK(res == 0 && cmp_nodes(nodes, nodesref));
  meshlib_close();
  fprintf(stderr, "All tests passed.\n");
  return 0;
}
