;=============================================================================
; @(#)xp-midi-usart.inc  0.1  2016/01/06
;   ________        _________________.________
;  /  _____/  ____ /   _____/   __   \   ____/
; /   \  ___ /  _ \\_____  \\____    /____  \
; \    \_\  (  <_> )        \  /    //       \
;  \______  /\____/_______  / /____//______  /
;         \/              \/               \/
; Copyright (c) 2016 by Alessandro Fraschetti.
; All Rights Reserved.
;
; Description: Simple MIDI USART Routines
; Target.....: Microchip PIC 16F6x8a Microcontroller
; Compiler...: Microchip Assembler (MPASM)
; Note.......:
;=============================================================================


;;      ; midiInStatus Flags
;;      BYTE_RECEIVED	equ	0x00	    ; midi-in byte received flag
;;      OVERRUN_ERROR   equ     0x06	    ; midi-in overrun error flag
;;	FRAME_ERROR     equ     0x07	    ; midi-in frame error flag
;;
;;	midiInSettlingTime		    ; midi-in settling time for start-up
;;	midiInStatus			    ; midi-in Status Register
;;	midiInByte			    ; midi-in Received Byte Register


;=============================================================================
;  Init Midi USART
;=============================================================================
init_midi_usart:
        errorlevel  -302

        bsf         STATUS, RP0             ; select Bank1
        bcf         TXSTA, TX9              ; 8-bit tx
        bcf         TXSTA, TXEN             ; disable tx
        bcf         TXSTA, SYNC             ; asynchronous mode
        bcf         TXSTA, BRGH             ; high bound rate
;        movlw      d'07'                   ; 31250 bauds on 4MHz osc. (BRGH=1)
;        movlw      d'39'                   ; 31250 bauds on 20MHz osc. (BRGH=1)
        movlw       d'09'                   ; 31250 bauds on 20MHz osc. (BRGH=0)
        movwf       SPBRG                   ;
        bsf         TXSTA, TXEN             ; enable tx

        bcf         STATUS, RP0             ; select Bank0
        bsf         RCSTA, SPEN             ; enable serial port
        bcf         RCSTA, RX9              ; 8-bit rx
        bsf         RCSTA, CREN             ; enable continuous rx
        bcf         STATUS, RP0             ; select Bank0

	clrf	    midiInSettlingTime	    ; provide a settling time for start-up
	decfsz	    midiInSettlingTime, F 
        goto	    $-1 

        movf	    RCREG, W		    ; flush buffer
        movf	    RCREG, W
        movf	    RCREG, W

        errorlevel  +302

        return


;=============================================================================
;  Clear Midi USART Registers
;=============================================================================
clear_midi_usart_regs:
	clrf	    midiInStatus
	clrf	    midiInByte
	return


;=============================================================================
;  Midi TX routines
;=============================================================================
send_midi_out_data:
        movwf       TXREG                   ; load tx register with W
        btfss       PIR1, TXIF              ; wait for end of transmission
        goto        $-1
        return


;=============================================================================
;  Midi RX routines
;=============================================================================
scan_midi_in_data:
        btfss       PIR1, RCIF			    ; test for incoming data
        return

        btfsc       RCSTA, OERR			    ; test for overrun error
        goto        errOERR
        btfsc       RCSTA, FERR			    ; test for frame error
        goto        errFERR

        movf	    RCREG, W			    ; set midi-in Byte Register
	movwf	    midiInByte			    ;
	bsf	    midiInStatus, BYTE_RECEIVED	    ; set midi-in status flag
        return

errOERR
        bcf         RCSTA, CREN
        bsf         RCSTA, CREN
        bsf	    midiInStatus, OVERRUN_ERROR	    ; set overrun error flag
        return

errFERR
        movf        RCREG, W
        bsf	    midiInStatus, FRAME_ERROR	    ; set frame error flag
        return



