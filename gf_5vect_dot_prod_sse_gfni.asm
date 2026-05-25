;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;  Copyright(c) 2011-2015 Intel Corporation All rights reserved.
;
;  Redistribution and use in source and binary forms, with or without
;  modification, are permitted provided that the following conditions
;  are met:
;    * Redistributions of source code must retain the above copyright
;      notice, this list of conditions and the following disclaimer.
;    * Redistributions in binary form must reproduce the above copyright
;      notice, this list of conditions and the following disclaimer in
;      the documentation and/or other materials provided with the
;      distribution.
;    * Neither the name of Intel Corporation nor the names of its
;      contributors may be used to endorse or promote products derived
;      from this software without specific prior written permission.
;
;  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
;  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
;  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
;  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
;  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
;  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;
;;; gf_5vect_dot_prod_sse_gfni(len, vec, *g_tbls, **buffs, **dests);
;;;

%include "reg_sizes.asm"

%ifidn __OUTPUT_FORMAT__, elf64
 %define arg0  rdi
 %define arg1  rsi
 %define arg2  rdx
 %define arg3  rcx
 %define arg4  r8
 %define arg5  r9

 %define tmp   r11
 %define tmp2  r10
 %define tmp3  r13              ; must be saved and restored
 %define tmp4  r12              ; must be saved and restored
 %define tmp5  r14              ; must be saved and restored
 %define tmp6  r15              ; must be saved and restored
 %define tmp7  rbp              ; must be saved and restored
 %define return rax

 %define func(x) x: endbranch
 %macro FUNC_SAVE 0
        push    r12
        push    r13
        push    r14
        push    r15
 %endmacro
 %macro FUNC_RESTORE 0
        pop     r15
        pop     r14
        pop     r13
        pop     r12
 %endmacro
%endif

%ifidn __OUTPUT_FORMAT__, win64
 %define arg0   rcx
 %define arg1   rdx
 %define arg2   r8
 %define arg3   r9
 %define arg4   r10             ; must be saved, loaded and restored
 %define arg5   r11             ; must be saved and restored
 %define tmp    r12             ; must be saved and restored
 %define tmp2   r13             ; must be saved and restored
 %define tmp3   r14             ; must be saved and restored
 %define tmp4   r15             ; must be saved and restored
 %define tmp5   rdi             ; must be saved and restored
 %define tmp6   rsi             ; must be saved and restored
 %define tmp7   rbp             ; must be saved and restored
 %define tmp8   rbx             ; must be saved and restored
 %define return rax
 %define stack_size  5*16 + 9*8 ; must be an odd multiple of 8
 %define arg(x)      [rsp + stack_size + 8 + 8*x]

 %define func(x) proc_frame x
 %macro FUNC_SAVE 0
        sub     rsp, stack_size
        movdqa  [rsp + 0*16], xmm6
        movdqa  [rsp + 1*16], xmm7
        movdqa  [rsp + 2*16], xmm8
        movdqa  [rsp + 3*16], xmm9
        movdqa  [rsp + 4*16], xmm10
        mov     [rsp + 5*16 + 0*8], r12
        mov     [rsp + 5*16 + 1*8], r13
        mov     [rsp + 5*16 + 2*8], r14
        mov     [rsp + 5*16 + 3*8], r15
        mov     [rsp + 5*16 + 4*8], rdi
        mov     [rsp + 5*16 + 5*8], rsi
        mov     [rsp + 5*16 + 6*8], rbp
        mov     [rsp + 5*16 + 7*8], rbx
        mov     arg4, arg(4)
 %endmacro

 %macro FUNC_RESTORE 0
        movdqa  xmm6, [rsp + 0*16]
        movdqa  xmm7, [rsp + 1*16]
        movdqa  xmm8, [rsp + 2*16]
        movdqa  xmm9, [rsp + 3*16]
        movdqa  xmm10, [rsp + 4*16]
        mov     r12,  [rsp + 5*16 + 0*8]
        mov     r13,  [rsp + 5*16 + 1*8]
        mov     r14,  [rsp + 5*16 + 2*8]
        mov     r15,  [rsp + 5*16 + 3*8]
        mov     rdi,  [rsp + 5*16 + 4*8]
        mov     rsi,  [rsp + 5*16 + 5*8]
        mov     rbp,  [rsp + 5*16 + 6*8]
        mov     rbx,  [rsp + 5*16 + 7*8]
        add     rsp, stack_size
 %endmacro
%endif

%define len    arg0
%define vec    arg1
%define mul_array arg2
%define src    arg3
%define dest1  arg4
%define ptr    arg5
%define dest2  tmp2
%define dest3  tmp3
%define dest4  tmp4
%define dest5  tmp5
%define vec_i  tmp6
%define vskip3 tmp7
%define vskip4 tmp8
%define pos    return

%ifndef EC_ALIGNED_ADDR
;;; Use Un-aligned load/store
 %define XLDR movdqu
 %define XSTR movdqu
%else
;;; Use Non-temporal load/stor
 %ifdef NO_NT_LDST
  %define XLDR movdqa
  %define XSTR movdqa
 %else
  %define XLDR movntdqa
  %define XSTR movntdq
 %endif
%endif

default rel

[bits 64]
section .text

%define x0     xmm0
%define xp1    xmm1
%define xp2    xmm2
%define xp3    xmm3
%define xp4    xmm4
%define xp5    xmm5
%define xgft1  xmm6
%define xgft2  xmm7
%define xgft3  xmm8
%define xgft4  xmm9
%define xgft5  xmm10

align 16
mk_global gf_5vect_dot_prod_sse_gfni, function
func(gf_5vect_dot_prod_sse_gfni)
        FUNC_SAVE
        sub     len, 16
        jl      .return_fail
        xor     pos, pos
        mov     vskip3, vec
        imul    vskip3, 3*32
        mov     vskip4, vec
        imul    vskip4, 4*32
        sal     vec, 3                  ;vec *= 8. Make vec_i count by 8
        mov     dest2, [dest1+1*8]
        mov     dest3, [dest1+2*8]
        mov     dest4, [dest1+3*8]
        mov     dest5, [dest1+4*8]
        mov     dest1, [dest1]
.loop16:
        mov     tmp, mul_array
        xor     vec_i, vec_i
        pxor    xp1, xp1
        pxor    xp2, xp2
        pxor    xp3, xp3
        pxor    xp4, xp4
        pxor    xp5, xp5
.next_vect:
        mov     ptr, [src+vec_i]
        add     vec_i, 8
        XLDR    x0, [ptr+pos]           ;Get next source vector
        vpbroadcastq xgft1, [tmp]       ;Load multipliers
        vpbroadcastq xgft2, [tmp+vec*4]
        vpbroadcastq xgft3, [tmp+vec*8]
        vpbroadcastq xgft4, [tmp+vskip3]
        vpbroadcastq xgft5, [tmp+vskip4]
        add     tmp, 32
        vgf2p8affineqb xgft1,x0,xgft1,0 ;Multiply
        vgf2p8affineqb xgft2,x0,xgft2,0
        vgf2p8affineqb xgft3,x0,xgft3,0
        vgf2p8affineqb xgft4,x0,xgft4,0
        vgf2p8affineqb xgft5,x0,xgft5,0
        pxor    xp1, xgft1              ;xp1 += partial
        pxor    xp2, xgft2              ;xp2 += partial
        pxor    xp3, xgft3              ;xp3 += partial
        pxor    xp4, xgft4              ;xp4 += partial
        pxor    xp5, xgft5              ;xp5 += partial
        cmp     vec_i, vec
        jl      .next_vect
        XSTR    [dest1+pos], xp1
        XSTR    [dest2+pos], xp2
        XSTR    [dest3+pos], xp3
        XSTR    [dest4+pos], xp4
        XSTR    [dest5+pos], xp5
        add     pos, 16                 ;Loop on 16 bytes at a time
        cmp     pos, len
        jle     .loop16
        lea     tmp, [len + 16]
        cmp     pos, tmp
        je      .return_pass
        ;; Tail len
        mov     pos, len                ;Overlapped offset length-16
        jmp     .loop16                 ;Do one more overlap pass

.return_pass:
        FUNC_RESTORE
        mov     return, 0
        ret

.return_fail:
        FUNC_RESTORE
        mov     return, 1
        ret

endproc_frame

section .data

align 16
mask0f: dq 0x0f0f0f0f0f0f0f0f, 0x0f0f0f0f0f0f0f0f
