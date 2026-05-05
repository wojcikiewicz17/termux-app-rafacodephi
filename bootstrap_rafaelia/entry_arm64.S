.text
.global _raf_start
.type _raf_start, %function
_raf_start:
    bl raf_bootstrap_entry
1:  b 1b
