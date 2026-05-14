# Verify linear bootstrap

Objects OK.

build/00_raf_start_linear_panel.o:
0000000000000000 T raf_start_linear_panel
0000000000000000 T raf_write_stdout_leaf
build/02_raf_q16_leaf.o:
000000000000000f T raf_fraf_step_leaf
0000000000000000 T raf_q16_mul_leaf
build/03_raf_hex_blob.o:
0000000000000000 R raf_hex_blob_begin
000000000000003c R raf_hex_blob_end
