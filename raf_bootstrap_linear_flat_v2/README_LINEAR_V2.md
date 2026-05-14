# RAFCODEPHI Bootstrap Linear V2

Esta versão corrige o erro estrutural:

- não começa com `x29/x30`;
- não abre frame antes do painel;
- ARM64 abre `x0` até `x30` em ordem;
- só depois usa `x0/x1/x2/x8` para syscall;
- ARM32 abre `r0` até `r12` e `r14`, mas não escreve `sp/r13` nem `pc/r15` em safe mode;
- x86_64 abre registradores em ordem lógica antes do syscall;
- tudo fica no mesmo diretório.

## Compilar

```bash
bash build_linear.sh
bash verify_linear.sh
bash link_linear.sh
./build/raf_linear_panel
```
