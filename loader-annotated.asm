; --------------------------------
; "Castle Master 2: The Crypt" loader by Incentive Software Ltd., 1990
; Disassembled by Santiago Ontañón in 2023


L4000_VIDEOMEM_PATTERNS: equ #4000
L5800_VIDEOMEM_ATTRIBUTES: equ #5800

VIDEO_MEMORY_SIZE: equ 6912


; --------------------------------
    org #fe40


    ld sp, #6590

    ; Clear screen:
    ld hl, L4000_VIDEOMEM_PATTERNS
    ld d, h
    ld e, 1
    ld (hl), l  ; l == 0
    ld bc, VIDEO_MEMORY_SIZE - 1
    ldir

    call Lfee5_load_sequence

    ; Unreachable, as Lfee5_load_sequence never returns
    jp #4092


; --------------------------------
; Loads a block of dat from tape.
; Input:
; - ix: address to load to.
; - de: number of bytes to load.
Lfe55_load_from_tape:
    ld a, 0
    scf
    inc d
    ex af, af'
    dec d
    di
    ld a, 15
    out (254), a
    ld hl, 65332  ; #ff34
    push hl
    in a, (254)
    rra
    and 32
    or 2
    ld c, a
    cp a
Lfe6d:
    ret nz
Lfe6e:
    call Lff16
    jr nc, Lfe6d
    ld hl, 1045  ; #0415
Lfe76:
    djnz Lfe76
    dec hl
    ld a, h
    or l
    jr nz, Lfe76
    call Lff12
    jr nc, Lfe6d
Lfe82:
    ld b, 156
    call Lff12
    jr nc, Lfe6d
    ld a, 198
    cp b
    jr nc, Lfe6e
    inc h
    jr nz, Lfe82
Lfe91:
    ld b, 201
    call Lff16
    jr nc, Lfe6d
    ld a, b
    cp 212
    jr nc, Lfe91
    call Lff16
    ret nc
    ld a, c
    xor 3
    ld c, a
    ld h, 0
    ld b, 123
    jr Lfeca
Lfeab:
    ex af, af'
    jr nz, Lfeb5
    jr nc, Lfebf
    ld (ix + 0), l
    jr Lfec4
Lfeb5:
    rl c
    xor l
    ret nz
    ld a, c
    rra
    ld c, a
    inc de
    jr Lfec6
Lfebf:
    ld a, (ix + 0)
    xor l
    ret nz
Lfec4:
    inc ix
Lfec6:
    dec de
    ex af, af'
    ld b, 125
Lfeca:
    ld l, 1
Lfecc:
    call Lff12
    ret nc
    ld a, 142
    cp b
    rl l
    ld b, 123
    jp nc, Lfecc
    ld a, h
    xor l
    ld h, a
    ld a, d
    or e
    jr nz, Lfeab
    ld a, h
    cp 1
    ret


; --------------------------------
Lfee5_load_sequence:
    ; Load title screen:
    ld ix, L4000_VIDEOMEM_PATTERNS
    ld de, VIDEO_MEMORY_SIZE
    call Lfe55_load_from_tape

    ; Load game binary:
    ld ix, #6a00
    ld de, 35328  ; binary size (#8a00)
    push ix  ; Start execution address of the game
    call Lfe55_load_from_tape

    ; Clear screen:
    ld hl, L4000_VIDEOMEM_PATTERNS
    ld d, h
    ld e, 1
    ld (hl), l  ; l == 0
    ld bc, VIDEO_MEMORY_SIZE - 1
    ldir

    ; Load HUD graphics:
    ld ix, L4000_VIDEOMEM_PATTERNS
    ld de, VIDEO_MEMORY_SIZE
    call Lfe55_load_from_tape

    ret  ; jump to #6a00, which was pushed to the stack above


; --------------------------------
Lff12:
    call Lff16
    ret nc
Lff16:
    ld a, 22
Lff18:
    dec a
    jr nz, Lff18
    and a
Lff1c:
    inc b
    ret z
    ld a, 127
    in a, (254)
    rra
    xor c
    and 32
    jr z, Lff1c
    ld a, c
    xor 255
    ld c, a
    and 6
    or 8
    out (254), a
    scf
    ret

    ; reachable?
    jr c, Lff3e
    xor a
Lff37:
    out (254), a
    inc a
    and 7
    jr Lff37
Lff3e:
    xor a
    out (254), a
    ret


; --------------------------------
    nop
    nop
