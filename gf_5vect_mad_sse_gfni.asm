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
;;; gf_5vect_mad_sse_gfni(len, vec, vec_i, gtbl, src, dest);
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
 %define dst2  r13
 %define dst3  r14
 %define dst4  r15
 %define tmp   rbx
 
 %define return rax
 %define stack_size 14*16+5*8
 %define arg(x)  [rsp + stack_size + 8 + 8*x]
 %define func(x) proc_frame x

%macro FUNC_SAVE 0
	sub	rsp, stack_size
	movdqa	[rsp+ 5*16],xmm6
	movdqa	[rsp+ 6*16],xmm7
	movdqa	[rsp+ 7*16],xmm8
	movdqa	[rsp+ 8*16],xmm9
	movdqa	[rsp+ 9*16],xmm10
	movdqa	[rsp+10*16],xmm11
	movdqa	[rsp+11*16],xmm12
	movdqa	[rsp+12*16],xmm13
	movdqa	[rsp+13*16],xmm14
	mov     [rsp+14*16+0*8], r12
	mov     [rsp+14*16+1*8], r13
	mov     [rsp+14*16+2*8], r14
	mov     [rsp+14*16+3*8], r15
	mov     [rsp+14*16+4*8], rbx
	mov	arg4, arg(4)
	mov	arg5, arg(5)
%endmacro

%macro FUNC_RESTORE 0
	movdqa	xmm6,  [rsp+ 5*16]
	movdqa	xmm7,  [rsp+ 6*16]
	movdqa	xmm8,  [rsp+ 7*16]
	movdqa	xmm9,  [rsp+ 8*16]
	movdqa	xmm10, [rsp+ 9*16]
	movdqa	xmm11, [rsp+10*16]
	movdqa	xmm12, [rsp+11*16]
	movdqa	xmm13, [rsp+12*16]
	movdqa	xmm14, [rsp+13*16]
	mov	r12,   [rsp+14*16+0*8]
	mov	r13,   [rsp+14*16+1*8]
	mov	r14,   [rsp+14*16+2*8]
	mov	r15,   [rsp+14*16+3*8]
	mov	rbx,   [rsp+14*16+4*8]
	add	rsp, stack_size
%endmacro

%elifidn __OUTPUT_FORMAT__, elf64
 %define arg0     rdi
 %define arg1     rsi
 %define arg2     rdx
 %define arg3     rcx
 %define arg4     r8
 %define arg5     r9
 %define dst1     r10
 %define dst2     r11
 %define dst3     r12
 %define dst4     r13
 %define tmp      r14
 %define return   rax

 %define func(x) x: endbranch
 %define FUNC_SAVE
 %define FUNC_RESTORE
%endif

;;; gf_5vect_mad_sse_gfni(len, vec, vec_i, gtbl, src, dest)
%define len     arg0
%define vec     arg1
%define vec_i   arg2
%define gtbl    arg3
%define	src     arg4
%define dst0    arg5
%define dst4    gtbl
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
%define xm0     xmm1
%define xm1     xmm2
%define xm2     xmm3
%define xm3     xmm4
%define xm4     xmm5
%define xd0     xmm6
%define xd1     xmm7
%define xd2     xmm8
%define xd3     xmm9
%define xd4     xmm10
%define xp0     xmm11
%define xp1     xmm12
%define xp2     xmm13
%define xp3     xmm14
%define xp4     xs

align 16
mk_global gf_5vect_mad_sse_gfni, function
func(gf_5vect_mad_sse_gfni)
	FUNC_SAVE
        mov     tmp, len                ;tmp = len
	sub	len, 16                 ;len -=16
	jl	.return_fail
        sal     vec_i, 5                ;Load multipliers
        sal     vec, 5
        add     gtbl,vec_i
        lea     pos,[gtbl+2*vec]
        vpbroadcastq xm0, [gtbl      ]
        vpbroadcastq xm1, [gtbl+1*vec]
        vpbroadcastq xm2, [gtbl+2*vec]
        vpbroadcastq xm3, [pos +1*vec]
        vpbroadcastq xm4, [pos +2*vec]
        mov     dst4,[dst0+32]          ;Get dest pointers
        mov     dst3,[dst0+24]
        mov     dst2,[dst0+16]
        mov     dst1,[dst0+ 8]
        mov     dst0,[dst0   ]
	xor	pos, pos
	XLDR	xd0, [dst0+len]	        ;Save last 16 bytes
	XLDR	xd1, [dst1+len]
	XLDR	xd2, [dst2+len]
	XLDR	xd3, [dst3+len]
	XLDR	xd4, [dst4+len]
        movdqa  [rsp     ], xd0
        movdqa  [rsp+1*16], xd1
        movdqa  [rsp+2*16], xd2
        movdqa  [rsp+3*16], xd3
        movdqa  [rsp+4*16], xd4
.loop16:
        XLDR    xd0, [dst0+pos]         ;Get next dest vectors
        XLDR    xd1, [dst1+pos]
        XLDR    xd2, [dst2+pos]
        XLDR    xd3, [dst3+pos]
        XLDR    xd4, [dst4+pos]
.loop16_overlap:
        XLDR    xs, [src+pos]           ;Get next source vector
        vgf2p8affineqb xp0,xs,xm0,0     ;Multply
        vgf2p8affineqb xp1,xs,xm1,0
        vgf2p8affineqb xp2,xs,xm2,0
        vgf2p8affineqb xp3,xs,xm3,0
        vgf2p8affineqb xp4,xs,xm4,0
        pxor    xd0, xp0                ;Xor
        pxor    xd1, xp1
        pxor    xd2, xp2
        pxor    xd3, xp3
        pxor    xd4, xp4
        XSTR    [dst0+pos], xd0         ;Store
        XSTR    [dst1+pos], xd1
        XSTR    [dst2+pos], xd2
        XSTR    [dst3+pos], xd3
        XSTR    [dst4+pos], xd4
	add	pos, 16			;Loop on 16 bytes at a time
	cmp	pos, len
	jle	.loop16
	cmp	pos, tmp
	je	.return_pass
	;; Tail len
        movdqa  xd0,[rsp     ]          ;Restore last 16 bytes
        movdqa  xd1,[rsp+1*16]
        movdqa  xd2,[rsp+2*16]
        movdqa  xd3,[rsp+3*16]
        movdqa  xd4,[rsp+4*16]
	mov	pos, len	        ;Overlapped offset length-16
	jmp	.loop16_overlap	        ;Do one more overlap pass

.return_pass:
	mov	return, 0
	FUNC_RESTORE
	ret

.return_fail:
	mov	return, 1
	FUNC_RESTORE
	ret

endproc_frame

