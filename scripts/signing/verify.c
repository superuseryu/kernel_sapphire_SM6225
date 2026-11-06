#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tweetnacl.h"
void randombytes(unsigned char *x, unsigned long long n){ (void)x;(void)n; abort(); }
static unsigned char *rd(const char *p, size_t *n){
  FILE *f = fopen(p,"rb"); if(!f) return 0;
  fseek(f,0,SEEK_END); long l = ftell(f); rewind(f);
  unsigned char *b = malloc(l+1);
  if(!b || fread(b,1,l,f)!=(size_t)l){ fclose(f); return 0; }
  fclose(f); *n = l; return b;
}
int main(int c, char **v){
  if(c!=4) return 2;
  size_t pn,mn,sn;
  unsigned char *pk=rd(v[1],&pn), *m=rd(v[2],&mn), *s=rd(v[3],&sn);
  if(!pk||!m||!s||pn!=32||sn!=64) return 1;
  unsigned char *sm=malloc(64+mn), *out=malloc(64+mn);
  unsigned long long ol;
  memcpy(sm,s,64); memcpy(sm+64,m,mn);
  return crypto_sign_open(out,&ol,sm,64+mn,pk)==0 ? 0 : 1;
}
