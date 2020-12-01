#include<stdio.h>
#include<stdlib.h>
#include<math.h>
#include"meshlib.h"

#define CHECK(cond) if (!(cond)) {					\
    fprintf(stderr, "Check failed in %s line %d\n", __FILE__, __LINE__); exit(1); } \
  else fprintf(stderr, "Check passed in %s line %d\n", __FILE__, __LINE__)

int main(void) {
  int res;
  double val;
  res = meshlib_init(".");
  CHECK(res == 0);
  res = mesh_func_init("demo3.lua");
  CHECK(res == 0);
  res = mesh_func_call("f1", "d", &val, 10.0);
  CHECK(res == 0 && val == 10.0);
  res = mesh_func_call("f2", "d", &val, 10.0);
  CHECK(res != 0);
  res = mesh_func_call("f2", "id", &val, 3, 10.5);
  CHECK(res == 0 && val == 31.5);
  res = mesh_func_call("f3", "i_d", &val, -2, 2.0);
  CHECK(res == 0 && val == 4);
  /* Subtyping test */
  res = mesh_func_call("ity", "d", &val, 1.5);
  CHECK(res == 0 && val == 0);
  res = mesh_func_call("ity", "i", &val, 2);
  CHECK(res == 0 && val == 1);
  /* String parameters */
  res = mesh_func_call("f4", "cd", &val, "foo", 5.0);
  CHECK(res == 0 && val == 12.42);
  meshlib_close();
  fprintf(stderr, "All tests passed.\n");
  return 0;
}
