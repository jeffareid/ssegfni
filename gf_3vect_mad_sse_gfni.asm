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
;;; gf_3vect_mad_sse_gfni(len, vec, vec_i, gtbl, src, dest);
;;;

%include "reg_sizes.asm"

%ifidn __OUTPUT_FORMAT__, win64
 %define arg0  rcx
 %define arg1  rdx
 %define arg2  r8
 %define arg3  r9
 %define arg4  r10
 %define arg5  r11
 %define dst1  r12
 %define tmp   r13
 %define return rax
 %define stack_size 6*16+3*8
 %define arg(x)  [rsp + stack_size + 8 + 8*x]
 %define func(x) proc_frame x

%macro FUNC_SAVE 0
        sub     rsp, stack_size
        movdqa  [rsp+0*16],xmm6
        movdqa  [rsp+1*16],xmm7
        movdqa  [rsp+2*16],xmm8
        movdqa  [rsp+3*16],xmm9
        movdqa  [rsp+4*16],xmm10
        movdqa  [rsp+5*16],xmm11
        mov     [rsp+6*16+0*8], r12
        mov     [rsp+6*16+1*8], r13
        mov     arg4, arg(4)
        mov     arg5, arg(5)
%endmacro

%macro FUNC_RESTORE 0
        movdqa  xmm6, [rsp+0*16]
        movdqa  xmm7, [rsp+1*16]
        movdqa  xmm8, [rsp+2*16]
        movdqa  xmm9, [rsp+3*16]
        movdqa  xmm10, [rsp+4*16]
        movdqa  xmm11, [rsp+5*16]
        mov     r12, [rsp+6*16+0*8]
        mov     r13, [rsp+6*16+1*8]
        add     rsp, stack_size
%endmacro

%elifidn __OUTPUT_FORMAT__, elf64
 %define arg0     rdi
 %define arg1     rsi
 %define arg2     rdx
 %define arg3     rcx
 %define arg4     r8
 %define arg5     r9
 %define dst1     r10
 %define tmp      r11
 %define return   rax

 %define func(x) x: endbranch
 %define FUNC_SAVE
 %define FUNC_RESTORE
%endif

;;; gf_3vect_mad_sse_gfni(len, vec, vec_i, gtbl, src, dest)
%define len     arg0
%define vec     arg1
%define vec_i   arg2
%define gtbl    arg3
%define src     arg4
%define dst0    arg5
%define dst2    gtbl
%define pos     return

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

%define xs      xmm0
%define xd0     xmm1
%define xd1     xmm2
%define xd2     xmm3
%define xt0     xmm4
%define xt1     xmm5
%define xt2     xmm6
%define xm0     xmm7
%define xm1     xmm8
%define xm2     xmm9
%define xp0     xmm10
%define xp1     xmm11
%define xp2     xs
align 16
mk_global gf_3vect_mad_sse_gfni, function
func(gf_3vect_mad_sse_gfni)
        FUNC_SAVE
        mov     tmp, len                ;tmp = len
        sub     len, 16                 ;len -=16
        jl      .return_fail
        sal     vec_i, 5                ;Load multipliers
        sal     vec, 5
        add     gtbl,vec_i
        vpbroadcastq xm0, [gtbl      ]
        vpbroadcastq xm1, [gtbl+  vec]
        vpbroadcastq xm2, [gtbl+2*vec]
        mov     dst2,[dst0+16]          ;Get dest pointers
        mov     dst1,[dst0+8]
        mov     dst0,[dst0]
        xor     pos, pos
        XLDR    xt0, [dst0+len]         ;Backup last 16 bytes
        XLDR    xt1, [dst1+len]
        XLDR    xt2, [dst2+len]
.loop16:
        XLDR    xd0, [dst0+pos]         ;Get next dest vectors
        XLDR    xd1, [dst1+pos]
        XLDR    xd2, [dst2+pos]
.loop16_overlap:
        XLDR    xs, [src+pos]           ;Get next source vector
        vgf2p8affineqb xp0,xs,xm0,0     ;Multiply
        vgf2p8affineqb xp1,xs,xm1,0
        vgf2p8affineqb xp2,xs,xm2,0
        pxor    xd0, xp0                ;Xor
        pxor    xd1, xp1
        pxor    xd2, xp2
        XSTR    [dst0+pos], xd0         ;Store
        XSTR    [dst1+pos], xd1
        XSTR    [dst2+pos], xd2
        add     pos, 16                 ;Loop on 16 bytes at a time
        cmp     pos, len
        jle     .loop16
        cmp     pos, tmp
        je      .return_pass
        ;; Tail len
        mov     pos, len                ;Overlapped offset length-16
        movdqa  xd0, xt0                ;Restore save dest vectors
        movdqa  xd1, xt1
        movdqa  xd2, xt2
        jmp     .loop16_overlap         ;Do one more overlap pass

.return_pass:
        mov     return, 0
        FUNC_RESTORE
        ret

.return_fail:
        mov     return, 1
        FUNC_RESTORE
        ret

endproc_frame

