#ifndef RAF_ABI_LINEAR_H
#define RAF_ABI_LINEAR_H

/*
 * raf_abi_linear.h
 *
 * V2: painel linear de registradores.
 *
 * Regra:
 *   primeiro abre o painel da ISA;
 *   depois usa syscall;
 *   sem prologo x29/x30 antes do painel;
 *   sem stack frame;
 *   sem chamar subrotina antes de abrir os registradores.
 */

#if defined(__aarch64__)
  #define RAF_ARCH_ARM64 1
  #define RAF_REG_PANEL "X0-X30"
  #define RAF_SYS_WRITE 64
  #define RAF_SYS_EXIT  93
#elif defined(__arm__)
  #define RAF_ARCH_ARM32 1
  #define RAF_REG_PANEL "R0-R15"
  #define RAF_SYS_WRITE 4
  #define RAF_SYS_EXIT  1
#elif defined(__x86_64__)
  #define RAF_ARCH_X86_64 1
  #define RAF_REG_PANEL "RAX-R15"
  #define RAF_SYS_WRITE 1
  #define RAF_SYS_EXIT  60
#elif defined(__i386__)
  #define RAF_ARCH_X86 1
  #define RAF_REG_PANEL "EAX-EDI"
  #define RAF_SYS_WRITE 4
  #define RAF_SYS_EXIT  1
#else
  #define RAF_ARCH_UNKNOWN 1
  #define RAF_REG_PANEL "UNKNOWN"
  #define RAF_SYS_WRITE 0
  #define RAF_SYS_EXIT  0
#endif

#define RAF_FD_STDOUT 1

#endif
