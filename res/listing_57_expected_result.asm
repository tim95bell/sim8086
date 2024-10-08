
mov bx, 1000 ; Clocks: +4 = 4 | bx:0x0->0x3e8 ip:0x0->0x3
mov bp, 2000 ; Clocks: +4 = 8 | bp:0x0->0x7d0 ip:0x3->0x6
mov si, 3000 ; Clocks: +4 = 12 | si:0x0->0xbb8 ip:0x6->0x9
mov di, 4000 ; Clocks: +4 = 16 | di:0x0->0xfa0 ip:0x9->0xc
mov cx, [bp+di] ; Clocks: +15 = 31 (8 + 7ea) | ip:0xc->0xe
mov word [bx+si], cx ; Clocks: +16 = 47 (9 + 7ea) | ip:0xe->0x10
mov cx, [bp+si] ; Clocks: +16 = 63 (8 + 8ea) | ip:0x10->0x12
mov word [bx+di], cx ; Clocks: +17 = 80 (9 + 8ea) | ip:0x12->0x14
mov cx, [bp+di+1000] ; Clocks: +19 = 99 (8 + 11ea) | ip:0x14->0x18
mov word [bx+si+1000], cx ; Clocks: +20 = 119 (9 + 11ea) | ip:0x18->0x1c
mov cx, [bp+si+1000] ; Clocks: +20 = 139 (8 + 12ea) | ip:0x1c->0x20
mov word [bx+di+1000], cx ; Clocks: +21 = 160 (9 + 12ea) | ip:0x20->0x24
add dx, [bp+si+1000] ; Clocks: +21 = 181 (9 + 12ea) | ip:0x24->0x28 flags:->PZ
add word [bp+si], 76 ; Clocks: +25 = 206 (17 + 8ea) | ip:0x28->0x2b flags:PZ->
add dx, [bp+si+1001] ; Clocks: +25 = 231 (9 + 12ea + 4p) | ip:0x2b->0x2f flags:->PZ
add word [di+999], dx ; Clocks: +33 = 264 (16 + 9ea + 8p) | ip:0x2f->0x33 flags:PZ->P
add word [bp+si], 75 ; Clocks: +25 = 289 (17 + 8ea) | ip:0x33->0x36 flags:P->A

; Final registers:
;      bx: 0x03e8 (1000)
;      bp: 0x07d0 (2000)
;      si: 0x0bb8 (3000)
;      di: 0x0fa0 (4000)
;      ip: 0x0036 (54)
;   flags: A
