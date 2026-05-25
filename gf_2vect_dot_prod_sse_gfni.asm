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
;;; gf_2vect_dot_prod_sse_gfni(len, vec, *g_tbls, **buffs, **dests);
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
 %define tmp3  r9
 %define tmp4  r12              ; must be saved and restored
 %define return rax

 %define func(x) x: endbranch
 %macro FUNC_SAVE 0
        push    r12
 %endmacro
 %macro FUNC_RESTORE 0
        pop     r12
 %endmacro
%endif

%ifidn __OUTPUT_FORMAT__, win64
 %define arg0   rcx
 %define arg1   rdx
 %define arg2   r8
 %define arg3   r9

 %define arg4   r12             ; must be saved, loaded and restored
 %define tmp    r11
 %define tmp2   r10
 %define tmp3   r13             ; must be saved and restored
 %define tmp4   r14             ; must be saved and restored
 %define return rax
 %define stack_size  3*8        ; must be an odd multiple of 8
 %define arg(x)      [rsp + stack_size + 8 + 8*x]

 %define func(x) proc_frame x
 %macro FUNC_SAVE 0
        sub     rsp, stack_size
        mov     [rsp+ 0*8], r12 
        mov     [rsp+ 1*8], r13 
        mov     [rsp+ 2*8], r14 
        mov     arg4, arg(4)
 %endmacro

 %macro FUNC_RESTORE 0
        mov     r12, [rsp+ 0*8]
        mov     r13, [rsp+ 1*8]
        mov     r14, [rsp+ 2*8]
        add     rsp, stack_size
 %endmacro
%endif

%define len   arg0
%define vec   arg1
%define mul_array arg2
%define src   arg3
%define dest1  arg4

%define vec_i tmp2
%define ptr   tmp3
%define dest2 tmp4
%define pos   return

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
%define xgft1  xmm3
%define xgft2  xmm4

align 16
mk_global gf_2vect_dot_prod_sse_gfni, function

func(gf_2vect_dot_prod_sse_gfni)
        FUNC_SAVE
        sub     len, 16
        jl      .return_fail
        xor     pos, pos
        sal     vec, 3                  ;vec *= 8. Make vec_i count by 8
        mov     dest2, [dest1+8]
        mov     dest1, [dest1]
.loop16:
        pxor    xp1, xp1
        pxor    xp2, xp2
        mov     tmp, mul_array
        xor     vec_i, vec_i
.next_vect:
        mov     ptr, [src+vec_i]
        add     vec_i, 8
        vpbroadcastq xgft1, [tmp]       ;Load multipliers
        vpbroadcastq xgft2, [tmp+vec*4]
        add     tmp, 32
        XLDR    x0, [ptr+pos]           ;Get next source vector
        vgf2p8affineqb xgft1,x0,xgft1,0 ;Multiply
        vgf2p8affineqb xgft2,x0,xgft2,0
        pxor    xp1, xgft1              ;xp1 += partial
        pxor    xp2, xgft2              ;xp2 += partial
        cmp     vec_i, vec
        jl      .next_vect
        XSTR    [dest1+pos], xp1
        XSTR    [dest2+pos], xp2
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
        mov     return, 0
        FUNC_RESTORE
        ret

.return_fail:
        mov     return, 1
        FUNC_RESTORE
        ret

endproc_frame
