#ifndef LZSS_H
#define LZSS_H

int lzss_encode(char *s,size_t ssize,char *d,size_t dsize);
void lzss_decode(char *s,size_t ssize,char *d,size_t dsize);

#endif // LZSS_H
