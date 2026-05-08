#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static uint32_t crc32_tab[256];
static void crc32_init(void){
  for(uint32_t i=0;i<256;i++){uint32_t c=i;for(int j=0;j<8;j++) c=(c&1)?(0xEDB88320u^(c>>1)):(c>>1);crc32_tab[i]=c;}
}
static uint32_t crc32_calc(const uint8_t* d, uint32_t n){uint32_t c=0xFFFFFFFFu;for(uint32_t i=0;i<n;i++) c=crc32_tab[(c^d[i])&0xFFu]^(c>>8);return c^0xFFFFFFFFu;}
static void le16(uint8_t* p,uint16_t v){p[0]=v&255;p[1]=(v>>8)&255;}
static void le32(uint8_t* p,uint32_t v){p[0]=v&255;p[1]=(v>>8)&255;p[2]=(v>>16)&255;p[3]=(v>>24)&255;}
static int w(int fd,const void*buf,size_t n){return write(fd,buf,n)==(ssize_t)n?0:-1;}

typedef struct{const char*name;const uint8_t*data;uint32_t size;uint32_t crc;uint32_t off;}E;
static uint8_t sh_buf[4096], pkg_buf[4096], busybox_buf[4096], proot_buf[4096], motd_buf[4096];
static int load_file(const char* path, uint8_t* out, uint32_t* n){
  int fd=open(path,O_RDONLY);
  if(fd<0) return -1;
  ssize_t r=read(fd,out,4096);
  close(fd);
  if(r<=0||r>=4096) return -1;
  *n=(uint32_t)r;
  return 0;
}

static const char* env_or(const char* key, const char* fallback){
  const char* value=getenv(key);
  return (value && value[0]) ? value : fallback;
}

int main(int argc,char**argv){
  if(argc!=3) return 2;
  const char* out=argv[1]; const char* abi=argv[2];
  const char* package_name=env_or("TERMUX_BOOTSTRAP_PACKAGE_NAME", "com.termux.rafacodephi");
  const char* page_size=env_or("TERMUX_BOOTSTRAP_PAGE_SIZE", "16384");
  const char* min_api=(strcmp(abi,"arm")==0) ? "28" : env_or("TERMUX_BOOTSTRAP_MIN_API", "21");
  static char info[512];
  int info_n=snprintf(info,sizeof(info),
    "TERMUX_PACKAGE_NAME=%s\nTERMUX_ARCH=%s\nTERMUX_PAGE_SIZE=%s\nTERMUX_MIN_API=%s\nRAFCODEPHI_BOOTSTRAP=local-ci\n",
    package_name,abi,page_size,min_api);
  if(info_n<=0 || info_n>=(int)sizeof(info)) return 11;
  static const uint8_t symlinks[]="sh\342\206\220bin/termux-shell\n";
  uint32_t sh_n=0,pkg_n=0,busybox_n=0,proot_n=0,motd_n=0;
  if(load_file("bootstrap_src/common/bin/sh", sh_buf, &sh_n)!=0) return 8;
  if(load_file("bootstrap_src/common/bin/pkg", pkg_buf, &pkg_n)!=0) return 9;
  if(load_file("bootstrap_src/common/bin/busybox", busybox_buf, &busybox_n)!=0) return 12;
  if(load_file("bootstrap_src/common/bin/proot", proot_buf, &proot_n)!=0) return 13;
  if(load_file("bootstrap_src/common/etc/motd", motd_buf, &motd_n)!=0) return 10;
  E e[7]={{"BOOTSTRAP_INFO",(uint8_t*)info,(uint32_t)info_n,0,0},{"SYMLINKS.txt",symlinks,(uint32_t)(sizeof(symlinks)-1),0,0},{"bin/sh",sh_buf,sh_n,0,0},{"bin/pkg",pkg_buf,pkg_n,0,0},{"bin/busybox",busybox_buf,busybox_n,0,0},{"bin/proot",proot_buf,proot_n,0,0},{"etc/motd",motd_buf,motd_n,0,0}};
  crc32_init(); for(int i=0;i<7;i++) e[i].crc=crc32_calc(e[i].data,e[i].size);
  int fd=open(out,O_CREAT|O_TRUNC|O_WRONLY,0644); if(fd<0) return 3;
  uint32_t off=0;
  for(int i=0;i<7;i++){
    uint8_t h[30]; memset(h,0,sizeof(h)); le32(h,0x04034b50); le16(h+4,20); le16(h+8,0); le16(h+10,0); le32(h+14,e[i].crc); le32(h+18,e[i].size); le32(h+22,e[i].size); le16(h+26,(uint16_t)strlen(e[i].name));
    e[i].off=off; if(w(fd,h,30)||w(fd,e[i].name,strlen(e[i].name))||w(fd,e[i].data,e[i].size)){close(fd);return 4;} off += 30 + (uint32_t)strlen(e[i].name)+e[i].size;
  }
  uint32_t cdir_off=off;
  for(int i=0;i<7;i++){
    uint8_t c[46]; memset(c,0,sizeof(c)); le32(c,0x02014b50); le16(c+4,20); le16(c+6,20); le32(c+16,e[i].crc); le32(c+20,e[i].size); le32(c+24,e[i].size); le16(c+28,(uint16_t)strlen(e[i].name)); le32(c+42,e[i].off);
    if(w(fd,c,46)||w(fd,e[i].name,strlen(e[i].name))){close(fd);return 5;} off += 46 + (uint32_t)strlen(e[i].name);
  }
  uint32_t cdir_sz=off-cdir_off;
  uint8_t z[22]; memset(z,0,sizeof(z)); le32(z,0x06054b50); le16(z+8,7); le16(z+10,7); le32(z+12,cdir_sz); le32(z+16,cdir_off);
  if(w(fd,z,22)){close(fd);return 6;}
  close(fd); return 0;
}
