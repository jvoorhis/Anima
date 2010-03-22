#ifndef __ANIMA_H__
#define __ANIMA_H__

#include <GLUT/glut.h>

typedef int (*render_callback)(void*, int, int);

extern "C" {
  int animate (render_callback, int, char**);
}

#endif // __ANIMA_H__
