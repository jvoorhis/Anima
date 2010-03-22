#include "anima.h"
#include <iostream>
#include <GLUT/glut.h>
using namespace std;

void renderScene(void);
void resizeWindow(int, int);

static render_callback cb;
static int width, height;
static void *buffer;

extern "C" {

int
animate (render_callback c, int argc, char **argv)
{
  cb = c;
  width = 320;
  height = 320;
  buffer = malloc(4 * 4 * width * height);
  
  glutInit(&argc, argv);
  glutInitDisplayMode(GLUT_DOUBLE | GLUT_RGBA);
  glutInitWindowPosition(100, 100);
  glutInitWindowSize(320, 320);
  glutCreateWindow("Anima");
  glutDisplayFunc(renderScene);
  glutIdleFunc(renderScene);
  glutReshapeFunc(resizeWindow);
  glutMainLoop();
  return 0;
}

} // extern "C"

void
renderScene (void)
{
  glClearColor(0.0, 0.0, 0.0, 1.0);
  glClear(GL_COLOR_BUFFER_BIT);
  cb(buffer, width, height);
  glDrawPixels(width, height, GL_RGBA, GL_FLOAT, buffer);
  glutSwapBuffers();
}

void
resizeWindow (int w, int h)
{
  if (0 == h) { h = 1; } // avoid dividing by zero
  float ratio = 1.0 * w / h;
  
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity();
  
  glViewport(0, 0, w, h);
  
  gluPerspective(45,ratio,1,1000);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity();
  gluLookAt(0.0, 0.0, 5.0,
            0.0, 0.0, -1.0,
            0.0f, 1.0f, 0.0f);
}
