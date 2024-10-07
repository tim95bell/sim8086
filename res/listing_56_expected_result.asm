
mov bx, 1000 ; Clocks: +4 = 4 | bx:0x0->0x3e8 ip:0x0->0x3
mov bp, 2000 ; Clocks: +4 = 8 | bp:0x0->0x7d0 ip:0x3->0x6
mov si, 3000 ; Clocks: +4 = 12 | si:0x0->0xbb8 ip:0x6->0x9
mov di, 4000 ; Clocks: +4 = 16 | di:0x0->0xfa0 ip:0x9->0xc
mov cx, bx ; Clocks: +2 = 18 | cx:0x0->0x3e8 ip:0xc->0xe
mov dx, 12 ; Clocks: +4 = 22 | dx:0x0->0xc ip:0xe->0x11
mov dx, [+1000] ; Clocks: +14 = 36 (8 + 6ea) | dx:0xc->0x0 ip:0x11->0x15
mov cx, [bx] ; Clocks: +13 = 49 (8 + 5ea) | cx:0x3e8->0x0 ip:0x15->0x17
mov cx, [bp] ; Clocks: +13 = 62 (8 + 5ea) | ip:0x17->0x1a
mov word [si], cx ; Clocks: +14 = 76 (9 + 5ea) | ip:0x1a->0x1c
mov word [di], cx ; Clocks: +14 = 90 (9 + 5ea) | ip:0x1c->0x1e
mov cx, [bx+1000] ; Clocks: +17 = 107 (8 + 9ea) | ip:0x1e->0x22
mov cx, [bp+1000] ; Clocks: +17 = 124 (8 + 9ea) | ip:0x22->0x26
mov word [si+1000], cx ; Clocks: +18 = 142 (9 + 9ea) | ip:0x26->0x2a
mov word [di+1000], cx ; Clocks: +18 = 160 (9 + 9ea) | ip:0x2a->0x2e
add cx, dx ; Clocks: +3 = 163 | ip:0x2e->0x30 flags:->PZ
add word [di+1000], cx ; Clocks: +25 = 188 (16 + 9ea) | ip:0x30->0x34
add dx, 50 ; Clocks: +4 = 192 | dx:0x0->0x32 ip:0x34->0x37 flags:PZ->

; Final registers:
;      bx: 0x03e8 (1000)
;      dx: 0x0032 (50)
;      bp: 0x07d0 (2000)
;      si: 0x0bb8 (3000)
;      di: 0x0fa0 (4000)
;      ip: 0x0037 (55)
