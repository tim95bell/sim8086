
bits 16

mov [bx - 12], byte 43
mov [bx - 256], byte 43
mov [65535], byte 43

mov ah, [13]
mov al, [13]
mov ax, [13]

mov ah, [1050]
mov al, [1050]
mov ax, [1050]

mov [13], ah
mov [13], al
mov [13], ax

mov [1050], ah
mov [1050], al
mov [1050], ax

mov [4], byte 34
mov [4], word 1049
mov [1134], byte 27
mov [1134], word 1234

mov [bx + si], byte 47
mov [bx + di], byte 47
mov [bp + si], byte 47
mov [bp + di], byte 47
mov [si], byte 47
mov [di], byte 47
mov [234], byte 47
mov [2134], byte 47
mov [bx], byte 47

mov [bx + si], word 1323
mov [bx + di], word 1323
mov [bp + si], word 1323
mov [bp + di], word 1323
mov [si], word 1323
mov [di], word 1323
mov [234], word 1323
mov [2134], word 1323
mov [bx], word 1323

mov [bx + si + 57], byte 47
mov [bx + di + 57], byte 47
mov [bp + si + 57], byte 47
mov [bp + di + 57], byte 47
mov [si + 57], byte 47
mov [di + 57], byte 47
mov [bp + 57], byte 47
mov [bx + 57], byte 47

mov [bx + si + 57], word 1323
mov [bx + di + 57], word 1323
mov [bp + si + 57], word 1323
mov [bp + di + 57], word 1323
mov [si + 57], word 1323
mov [di + 57], word 1323
mov [bp + 57], word 1323
mov [bx + 57], word 1323

mov [bx + si + 3232], byte 47
mov [bx + di + 3232], byte 47
mov [bp + si + 3232], byte 47
mov [bp + di + 3232], byte 47
mov [si + 3232], byte 47
mov [di + 3232], byte 47
mov [bp + 3232], byte 47
mov [bx + 3232], byte 47

mov [bx + si + 3232], word 1323
mov [bx + di + 3232], word 1323
mov [bp + si + 3232], word 1323
mov [bp + di + 3232], word 1323
mov [si + 3232], word 1323
mov [di + 3232], word 1323
mov [bp + 3232], word 1323
mov [bx + 3232], word 1323
