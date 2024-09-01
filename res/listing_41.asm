; ========================================================================
;
; (C) Copyright 2023 by Molly Rocket, Inc., All Rights Reserved.
;
; This software is provided 'as-is', without any express or implied
; warranty. In no event will the authors be held liable for any damages
; arising from the use of this software.
;
; Please see https://computerenhance.com for further information
;
; ========================================================================

; ========================================================================
; LISTING 41
; ========================================================================

bits 16

; -------- add
; mem to reg
add bx, [bx+si]
add bx, [bp]

; imm to reg
add si, 2
add bp, 2
add cx, 8

; mem to reg
add bx, [bp + 0]
add cx, [bx + 2]
add bh, [bp + si + 4]
add di, [bp + di + 6]

; reg to mem
add [bx+si], bx
add [bp], bx
add [bp + 0], bx
add [bx + 2], cx
add [bp + si + 4], bh
add [bp + di + 6], di

; imm to mem (size specifier on mem)
add byte [bx], 34
add word [bp + si + 1000], 29

; mem to accumulator
add ax, [bp]
add al, [bx + si]

; reg to accumulator
add ax, bx
add al, ah

; imm to accumulator
add ax, 1000
add al, -30
add al, 9

; -------- sub
; mem to reg
sub bx, [bx+si]
sub bx, [bp]

; imm to reg
sub si, 2
sub bp, 2
sub cx, 8

; mem to reg
sub bx, [bp + 0]
sub cx, [bx + 2]
sub bh, [bp + si + 4]
sub di, [bp + di + 6]

; reg to mem
sub [bx+si], bx
sub [bp], bx
sub [bp + 0], bx
sub [bx + 2], cx
sub [bp + si + 4], bh
sub [bp + di + 6], di

; imm to mem (size specifier on mem)
sub byte [bx], 34
sub word [bx + di], 29

; mem to accumulator
sub ax, [bp]
sub al, [bx + si]

; reg to accumulator
sub ax, bx
sub al, ah

; imm to accumulator
sub ax, 1000
sub al, -30
sub al, 9

; -------- cmp
; mem to reg
cmp bx, [bx+si]
cmp bx, [bp]

; imm to reg
cmp si, 2
cmp bp, 2
cmp cx, 8

; mem to reg
cmp bx, [bp + 0]
cmp cx, [bx + 2]
cmp bh, [bp + si + 4]
cmp di, [bp + di + 6]

; reg to mem
cmp [bx+si], bx
cmp [bp], bx
cmp [bp + 0], bx
cmp [bx + 2], cx
cmp [bp + si + 4], bh
cmp [bp + di + 6], di

; imm to mem (size specifier on mem)
cmp byte [bx], 34
cmp word [4834], 29

; mem to accumulator
cmp ax, [bp]
cmp al, [bx + si]

; reg to accumulator
cmp ax, bx
cmp al, ah

; imm to accumulator
cmp ax, 1000
cmp al, -30
cmp al, 9

; -------- jumps
;test_label0:
;jnz test_label1
;jnz test_label0
;test_label1:
;jnz test_label0
;jnz test_label1
;
;label:
;je label
;jl label
;jle label
;jb label
;jbe label
;jp label
;jo label
;js label
;jne label
;jnl label
;jg label
;jnb label
;ja label
;jnp label
;jno label
;jns label
;loop label
;loopz label
;loopnz label
;jcxz label
