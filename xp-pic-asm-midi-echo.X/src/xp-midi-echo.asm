;=============================================================================
; @(#)xp-midi-echo.asm
;                       ________.________
;   ____   ____  ______/   __   \   ____/
;  / ___\ /  _ \/  ___/\____    /____  \ 
; / /_/  >  <_> )___ \    /    //       \
; \___  / \____/____  >  /____//______  /
;/_____/            \/                \/ 
; Copyright (c) 2016 Alessandro Fraschetti (gos95@gommagomma.net).
;
; This file is part of the pic-assembly-midi-xp project:
;     https://github.com/pic-assembly-midi-xp
;
; Author.....: Alessandro Fraschetti
; Company....: gos95
; Target.....: Microchip PICmicro MidRange Microcontroller
; Compiler...: Microchip Assembler (MPASM)
; Version....: 1.0 2016/01/05
; Description: Simple MIDI echo
;=============================================================================
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to deal
; in the Software without restriction, including without limitation the rights
; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
; copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:

; The above copyright notice and this permission notice shall be included in all
; copies or substantial portions of the Software.

; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.
;=============================================================================


    PROCESSOR   16f648a
    INCLUDE     <p16f648a.inc>


;=============================================================================
;  CONFIGURATION
;=============================================================================
    __CONFIG    _CP_OFF & _DATA_CP_OFF & _LVP_OFF & _BOREN_OFF & _MCLRE_ON & _WDT_OFF & _PWRTE_ON & _HS_OSC


;=============================================================================
;  CONSTANT DEFINITIONS
;=============================================================================
    constant    BYTE_RECEIVED = 0x00            ; midi-in byte received flag
    constant    OVERRUN_ERROR = 0x01            ; midi-in overrun error flag
    constant    FRAME_ERROR   = 0x02            ; midi-in frame error flag


;=============================================================================
;  VARIABLE DEFINITIONS
;=============================================================================
XPMIDI_VAR          UDATA
midiInSettlingTime  RES     1                   ; midi-in settling time for start-up
midiInStatus        RES     1                   ; midi-in Status Register
midiInByte          RES     1                   ; midi-in received byte Register


;=============================================================================
;  RESET VECTOR
;=============================================================================
RESET               CODE    0x0000              ; processor reset vector
        pagesel     MAIN                        ; 
        goto        MAIN                        ; go to beginning of program


;=============================================================================
;  INIT ROUTINES VECTOR
;=============================================================================
INIT_ROUTINES       CODE                        ; routines vector

; ---------------------------------------------------------------------------
; Init I/O Ports. Set RB1 (RX) and RB2(TX) as Input, the others PIN as Output
; ---------------------------------------------------------------------------
init_ports
        errorlevel  -302
        ; init PORTB
        movlw       1<<RB2
        banksel     PORTB
        movwf       PORTB                       ; clear output data latches and set RB2=TX

        banksel     TRISB
        movlw       1<<RB2|1<<RB1
        movwf       TRISB                       ; configure RB1 and RB2 as inputs
        errorlevel  +302
        return

; ---------------------------------------------------------------------------
; Init USART
; ---------------------------------------------------------------------------
init_usart
        errorlevel  -302
        banksel     TXSTA
        bcf         TXSTA, TX9                  ; 8-bit tx
        bcf         TXSTA, TXEN                 ; disable tx
        bcf         TXSTA, SYNC                 ; asynchronous mode
        bcf         TXSTA, BRGH                 ; high bound rate

;        movlw      d'07'                        ; 31250 bauds on 4MHz osc. (BRGH=1)
;        movlw      d'39'                        ; 31250 bauds on 20MHz osc. (BRGH=1)
        movlw       d'09'                       ; 31250 bauds on 20MHz osc. (BRGH=0)
        movwf       SPBRG
        bsf         TXSTA, TXEN                 ; enable tx

        banksel     RCSTA
        bsf         RCSTA, SPEN                 ; enable serial port
        bcf         RCSTA, RX9                  ; 8-bit rx
        bsf         RCSTA, CREN                 ; enable continuous rx

        banksel     midiInSettlingTime
        clrf	    midiInSettlingTime          ; provide a settling time for start-up
        decfsz	    midiInSettlingTime, F 
        goto	    $-1 

        banksel     RCREG
        movf	    RCREG, W                    ; flush buffer
        movf	    RCREG, W
        movf	    RCREG, W
        errorlevel  +302
        return


; ---------------------------------------------------------------------------
; TX routines
; ---------------------------------------------------------------------------
send_char_and_wait
        banksel     TXREG
        movwf       TXREG                       ; load tx register with W
;        nop
        btfss       PIR1, TXIF                  ; wait for end of transmission
        goto        $-1
        return

tx_wait
        banksel     PIR1
        btfss       PIR1, TXIF                  ; wait for end of transmission
        goto        $-1
        return

; ---------------------------------------------------------------------------
;  RX routines
; ---------------------------------------------------------------------------
wait_until_receive_char
        banksel     PIR1
        btfss       PIR1, RCIF                  ; wait for data
        goto        $-1

        banksel     RCSTA
        btfsc       RCSTA, OERR                 ; test for overrun error
        goto        errOERR
        btfsc       RCSTA, FERR                 ; test for frame error
        goto        errFERR

        banksel     RCREG
        movf        RCREG, W                    ; read received data
        movwf       midiInByte
        return
errOERR
        banksel     RCSTA
        bcf         RCSTA, CREN
        bsf         RCSTA, CREN
        banksel     midiInStatus
        bsf         midiInStatus, OVERRUN_ERROR	; set overrun error flag
        return
errFERR
        banksel     RCREG
        movf        RCREG, W
        banksel     midiInStatus
        bsf         midiInStatus, FRAME_ERROR	; set frame error flag
        return

; ---------------------------------------------------------------------------
;  RX/TX handler routines
; ---------------------------------------------------------------------------
error_handler
        banksel     midiInStatus
        clrf	    midiInStatus
        return


;=============================================================================
;  MAIN PROGRAM
;=============================================================================
MAINPROGRAM         CODE                        ; begin program
MAIN
        pagesel     init_ports
        call        init_ports
        call        init_usart

        banksel     midiInStatus
        clrf	    midiInStatus

mainloop
        call        wait_until_receive_char     ; read usart data

        movf        midiInStatus, F             ; test for usart errors
        btfss       STATUS, Z
        call        error_handler

;       movf	    midiInByte, W               ; test for system message family
;       andlw       b'11110000'
;       sublw       b'11110000'
;       btfsc       STATUS, Z                   ; skip system message family
;       goto        mainloop

        movf        midiInByte, W               ; echo byte
        call        send_char_and_wait

        goto        mainloop

        END                                     ; end program
