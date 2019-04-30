;=============================================================================
; @(#)xp-midi-routines.asm
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
; Description: MIDI protocol utility routines
; 
;                                              ----- voice message
;                   ---- channel message -----|
;                  |                           ----- mode message
;                  |
; MIDI message ----| 
;                  |                           ---- common message
;                   ----- system message -----|---- real-time message
;                                              ---- exclusive message
;
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
    ; XPMIDI_STATUS register flags
    constant    XPMIDI_RXF = 0x00               ; midi-in byte received flag
    constant    XPMIDI_OEF = 0x01               ; midi-in overrun error flag
    constant    XPMIDI_FEF = 0x02               ; midi-in frame error flag
    constant    XPMIDI_TXF = 0x05               ; midi-out byte transmitted flag

    ; XPMIDI_EVENT register flags
    constant    XPMIDI_BYTE0  = 0x02            ; event byte0 (status) received flag
    constant    XPMIDI_BYTE1  = 0x03            ; event byte1 (data1) received flag
    constant    XPMIDI_BYTE2  = 0x04            ; event byte2 (data2) received flag
    constant    XPMIDI_EFULL  = 0x05            ; event full received flag
    constant    XPMIDI_FAMILY = 0x06            ; event family: 0=Channel Message, 1=System Message

    ; XPMIDI common constants
    constant    XPMIDI_CHANNEL_MSG = 0          ; event family: Channel Message
    constant    XPMIDI_SYSTEM_MSG  = 1          ; event family: System Message

    constant    XPMIDI_STATUS_BYTE_MASK = b'11110000'
    constant    XPMIDI_CHANNEL_MASK = b'00001111'
    constant    XPMIDI_SYSTEM_MESS_MASK = b'11110000'

    ; Channel Messages
    constant    XPMIDI_NOTE_OFF = 0x80
    constant    XPMIDI_NOTE_ON = 0x90
    constant    XPMIDI_POLY_PRESSURE = 0xA
    constant    XPMIDI_CONTROL_CHANGE = 0xB
    constant    XPMIDI_PROGRAM_CHANGE = 0xC
    constant    XPMIDI_CHANNEL_PRESSURE = 0xD
    constant    XPMIDI_PITCH_BEND = 0xE

    ; System Real-Time Messages
    ; System Common Messages
    ; System Exclusive Message


;=============================================================================
;  VARIABLE DEFINITIONS
;=============================================================================
XPMIDI_DATA         UDATA
XPMIDI_STATUS       RES     1                   ; midi usart Status Register
                                                ; <0> : In Byte Received Flag
                                                ; <1> : In Overrun Error Flag
                                                ; <2> : In Frame Error Flag
                                                ; <5> : Out Byte Transmitted Flag

XPMIDI_EVENT        RES     1                   ; midi events status register
                                                ; <0-1> : size of event received
                                                ; <2-4> : event bytes 1-3 received Flags
                                                ; <5>   : event full received Flag
                                                ; <6>   : event family Flag

midiInSettlingTime  RES     1                   ; midi-in settling time for start-up
midiInByte          RES     1                   ; midi-in received byte
eventInByte0        RES     1                   ; midi-in received event byte0 (status)
eventInByte1        RES     1                   ; midi-in received event byte1 (data1)
eventInByte2        RES     1                   ; midi-in received event byte2 (data2)


;=============================================================================
;  RESET VECTOR
;=============================================================================
RESET_CODE          CODE    0x0000              ; processor reset vector
        pagesel     MAIN                        ; 
        goto        MAIN                        ; go to beginning of program


;=============================================================================
;  XPMIDI INIT ROUTINES CODE VECTOR
;=============================================================================
XPMIDI_INIT_CODE    CODE                        ; routines code vector

; ---------------------------------------------------------------------------
; Clear All Registers
; ---------------------------------------------------------------------------
xpmidi_clear_regs
        banksel     XPMIDI_STATUS
        clrf        XPMIDI_STATUS
        clrf        XPMIDI_EVENT
        clrf        midiInByte
        clrf        eventInByte0
        clrf        eventInByte1
        clrf        eventInByte2
        return

; ---------------------------------------------------------------------------
; Init Midi Port. Set RB1 (RX) and RB2(TX) as Input, the others PIN as Output
; ---------------------------------------------------------------------------
xpmidi_init_port
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
; Init Midi USART
; ---------------------------------------------------------------------------
xpmidi_init_usart
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


;=============================================================================
;  XP-MIDI USART TX/RX ROUTINES CODE VECTOR
;=============================================================================
XPMIDI_USART_CODE   CODE                        ; routines code vector

; ---------------------------------------------------------------------------
; Midi TX routines
; ---------------------------------------------------------------------------
xpmidi_send
        banksel     TXREG
        movwf       TXREG                       ; load tx register with W
        return

xpmidi_send_and_wait
        banksel     TXREG
        movwf       TXREG                       ; load tx register with W
;        nop
xpmidi_tx_wait
        banksel     PIR1
        btfss       PIR1, TXIF                  ; wait for end of transmission
        goto        $-1
        return

; ---------------------------------------------------------------------------
;  Midi RX routines
; ---------------------------------------------------------------------------
xpmidi_scan
        banksel     PIR1
        btfss       PIR1, RCIF                  ; wait for data
        return

        banksel     RCSTA
        btfsc       RCSTA, OERR                 ; test for overrun error
        goto        errOERR
        btfsc       RCSTA, FERR                 ; test for frame error
        goto        errFERR

        banksel     RCREG
        movf        RCREG, W                    ; read received data
        banksel     midiInByte
        movwf       midiInByte
        bsf         XPMIDI_STATUS, XPMIDI_RXF   ; set midi-in status flag
        return

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
        banksel     midiInByte
        movwf       midiInByte
        bsf         XPMIDI_STATUS, XPMIDI_RXF   ; set midi-in status flag
        return

errOERR
        banksel     RCSTA
        bcf         RCSTA, CREN
        bsf         RCSTA, CREN
        banksel     XPMIDI_STATUS
        bsf         XPMIDI_STATUS, XPMIDI_OEF	; set overrun error flag
        return

errFERR
        banksel     RCREG
        movf        RCREG, W
        banksel     XPMIDI_STATUS
        bsf         XPMIDI_STATUS, XPMIDI_FEF	; set frame error flag
        return

; ---------------------------------------------------------------------------
;  RX/TX handler routines
; ---------------------------------------------------------------------------
error_handler
        banksel     XPMIDI_STATUS
        clrf	    XPMIDI_STATUS
        return


;=============================================================================
;  XP-MIDI MESSAGES ROUTINES CODE VECTOR
;=============================================================================
XPMIDI_MSG_CODE     CODE                        ; routines code vector

; ---------------------------------------------------------------------------
; Parse midi-in Event
; ---------------------------------------------------------------------------
xpmidi_parse
        banksel     midiInByte
        movf        midiInByte, W               ; test for statusbyte
        andlw       XPMIDI_STATUS_BYTE_MASK
        btfss       STATUS, Z
        goto        found_statusbyte            ; is statusbyte, check data
        btfss       XPMIDI_EVENT, XPMIDI_BYTE0  ; isn't. Test if a statusbyte was received
        return                                  ; ... lost data byte received
        btfss       XPMIDI_EVENT, XPMIDI_BYTE1  ; test for databyte order
        goto        found_databyte1             ; is databyte1, check data
        btfss       XPMIDI_EVENT, XPMIDI_BYTE2  ; test for databyte order
        goto        found_databyte2             ; is databyte2, check data
        return                                  ; ... lost data byte received

found_statusbyte
        movf        midiInByte, W               ; test for system message
        andlw       XPMIDI_STATUS_BYTE_MASK     ; or channel message
        sublw       XPMIDI_SYSTEM_MESS_MASK
        btfsc       STATUS, Z
        goto        found_system_message

        clrf        XPMIDI_EVENT                ; reset status register
        clrf        eventInByte1                ; reset databyte registers
        clrf        eventInByte2
        movf        midiInByte, W               ; save statusbyte
        movwf       eventInByte0
        bsf         XPMIDI_EVENT, XPMIDI_BYTE0  ; and update status register
check_note_off
        movf        eventInByte0, W             ; test for channel voice message
        andlw       XPMIDI_STATUS_BYTE_MASK     ; note off
        sublw       XPMIDI_NOTE_OFF
        btfss       STATUS, Z
        goto        check_note_on
        movf        XPMIDI_EVENT, W             ; set # of expected bytes
        addlw       0x03
        movwf       XPMIDI_EVENT
        return
check_note_on
        movf        eventInByte0, W             ; test for channel voice message
        andlw       XPMIDI_STATUS_BYTE_MASK     ; note on
        sublw       XPMIDI_NOTE_ON
        btfss       STATUS, Z   
        goto        check_poly_pressure
        movf        XPMIDI_EVENT, W             ; set # of expected bytes
        addlw       0x03
        movwf       XPMIDI_EVENT
        return
check_poly_pressure
        movf        eventInByte0, W             ; test for channel voice message
        andlw       XPMIDI_STATUS_BYTE_MASK     ; polyphonic key pressure
        sublw       XPMIDI_POLY_PRESSURE
        btfss       STATUS, Z
        goto        check_control_change
        movf        XPMIDI_EVENT, W             ; set # of expected bytes
        addlw       0x03
        movwf       XPMIDI_EVENT
        return
check_control_change
        movf        eventInByte0, W             ; test for channel voice message
        andlw       XPMIDI_STATUS_BYTE_MASK     ; control change
        sublw       XPMIDI_CONTROL_CHANGE
        btfss       STATUS, Z
        goto        check_program_change
        movf        XPMIDI_EVENT, W             ; set # of expected bytes
        addlw       0x03
        movwf       XPMIDI_EVENT
        return
check_program_change
        movf        eventInByte0, W             ; test for channel voice message
        andlw       XPMIDI_STATUS_BYTE_MASK     ; program change
        sublw       XPMIDI_PROGRAM_CHANGE
        btfss       STATUS, Z
        goto        check_channel_pressure
        movf        XPMIDI_EVENT, W             ; set # of expected bytes
        addlw       0x02
        movwf       XPMIDI_EVENT
        return
check_channel_pressure
        movf        eventInByte0, W             ; test for channel voice message
        andlw       XPMIDI_STATUS_BYTE_MASK     ; channel pressure
        sublw       XPMIDI_CHANNEL_PRESSURE
        btfss       STATUS, Z
        goto        check_pitch_bend_change
        movf        XPMIDI_EVENT, W             ; set # of expected bytes
        addlw       0x02
        movwf       XPMIDI_EVENT
        return
check_pitch_bend_change
        movf        eventInByte0, W             ; test for channel voice message
        andlw       XPMIDI_STATUS_BYTE_MASK     ; pitch bend change
        sublw       XPMIDI_PITCH_BEND
        btfss       STATUS, Z
        return
        movf        XPMIDI_EVENT, W             ; set # of expected bytes
        addlw       0x03
        movwf       XPMIDI_EVENT
        return

found_system_message
        bsf         XPMIDI_EVENT, XPMIDI_FAMILY ; system message

;	movf	    eventInByte0, W		    ; test for system real-time message
;	andlw       b'11111000'
;        sublw       b'11111000'
;        btfss       STATUS, Z
;        goto        check_system_common_message
;	movf	    eventInStatus, W		    ; set # of expected bytes
;	addlw	    0x01
;	movwf	    eventInStatus
;	bsf	    eventInStatus, EVENT_RECEIVED   ; event fully received
        return
check_system_common_message
        return

found_databyte1
        movf        midiInByte, W               ; save databyte
        movwf       eventInByte1
        bsf         XPMIDI_EVENT, XPMIDI_BYTE1  ; and update status register
        movf        XPMIDI_EVENT, W             ; test for expected bytes
        andlw       b'00000011'
        sublw       b'00000010'
        btfss       STATUS, Z                   ; waiting for databyte2
        return
        bsf         XPMIDI_EVENT, XPMIDI_EFULL  ; event fully received
        return

found_databyte2
        movf        midiInByte, W               ; save databyte
        movwf       eventInByte2
        bsf         XPMIDI_EVENT, XPMIDI_BYTE2  ; and update status register
        movf        XPMIDI_EVENT, W             ; test for expected bytes
        andlw       b'00000011'
        sublw       b'00000011'
        btfss       STATUS, Z                   ; waiting for...?
        return
        bsf         XPMIDI_EVENT, XPMIDI_EFULL  ; event fully received
        return


;=============================================================================
;  MAIN PROGRAM
;=============================================================================
MAINPROGRAM         CODE                        ; begin program
MAIN
        pagesel     xpmidi_init_port
        call        xpmidi_init_port            ; init the PIC modules (port and usart)
        call        xpmidi_init_usart

        pagesel     xpmidi_clear_regs
        call        xpmidi_clear_regs           ; clear the xp-midi registers

mainloop
        pagesel     wait_until_receive_char
        call        wait_until_receive_char     ; read usart data

        banksel     XPMIDI_STATUS
        movf        XPMIDI_STATUS, F            ; test for usart errors
        btfss       STATUS, Z
        call        error_handler

;       movf	    midiInByte, W               ; test for system message family
;       andlw       b'11110000'
;       sublw       b'11110000'
;       btfsc       STATUS, Z                   ; skip system message family
;       goto        mainloop

        pagesel     xpmidi_parse
        call        xpmidi_parse

        banksel     midiInByte
        movf        midiInByte, W               ; echo byte
        pagesel     xpmidi_send_and_wait
        call        xpmidi_send_and_wait

        pagesel     $
        goto        mainloop

        END                                     ; end program