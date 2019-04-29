;=============================================================================
; @(#)xp-midi-parser.asm  0.2  2016/01/06
;   ________        _________________.________
;  /  _____/  ____ /   _____/   __   \   ____/
; /   \  ___ /  _ \\_____  \\____    /____  \
; \    \_\  (  <_> )        \  /    //       \
;  \______  /\____/_______  / /____//______  /
;         \/              \/               \/
; Copyright (c) 2016 by Alessandro Fraschetti.
; All Rights Reserved.
;
; Description: Simple MIDI Event Parser
; Target.....: Microchip PIC 16F6x8a Microcontroller
; Compiler...: Microchip Assembler (MPASM)
; Note.......:
;=============================================================================

        processor   16f628A
        __CONFIG   _CP_OFF & _CPD_OFF & _LVP_OFF & _BOREN_OFF & _MCLRE_ON & _WDT_OFF & _PWRTE_ON & _HS_OSC
                    ; _CP_[ON/OFF]    : code protect program memory enable/disable
                    ; _CPD_[ON/OFF]   : code protect data memory enable/disable
                    ; _LVP_[ON/OFF]   : Low Voltage ICSP enable/disable
                    ; _BOREN_[ON/OFF] : Brown-Out Reset enable/disable
                    ; _WDT_[ON/OFF]   : watchdog timer enable/disable
                    ; _MCLRE_[ON/OFF] : MCLR pin function  digital IO/MCLR
                    ; _PWRTE_[ON/OFF] : power-up timer enable/disable


;=============================================================================
;  Label equates
;=============================================================================
        #include    <p16f628a.inc>          ; standard labels

        errorlevel  -207

	; xp-midi-usart labels
        ; midiInStatus Flags
        BYTE_RECEIVED	equ	0x00	    ; midi-in byte received flag
        OVERRUN_ERROR   equ     0x06	    ; midi-in overrun error flag
	FRAME_ERROR     equ     0x07	    ; midi-in frame error flag

	; xp-midi-parser labels
	; eventInStatus Flags
	BYTE_0_RECEIVED	equ	0x02	    ; event byte 0 (status) received flag
	BYTE_1_RECEIVED	equ	0x03	    ; event byte 1 (data1) received flag
	BYTE_2_RECEIVED	equ	0x04	    ; event byte 2 (data2) received flag
	EVENT_RECEIVED  equ     0x05	    ; event full received flag
	SYSTEM_MESSAGE  equ	0x06	    ; event family: 0=Channel Message, 1=System Message

        errorlevel  +207


;=============================================================================
;  File register use
;=============================================================================
        cblock      h'20'
            w_temp                          ; variable used for context saving
            status_temp                     ; variable used for context saving
            pclath_temp                     ; variable used for context saving
            d1, d2, d3                      ; delay routine vars

	    ; xp-midi-usart registers
	    midiInSettlingTime		    ; midi-in settling time for start-up
	    midiInStatus		    ; midi-in Status Register
	    midiInByte			    ; midi-in received byte Register

	    ; xp-midi-parser registers
	    eventInStatus		    ; midi-in event Status Register
	    eventInByte0		    ; midi-in event byte 0 (status) Register
	    eventInByte1		    ; midi-in event byte 1 (data1) Register
	    eventInByte2		    ; midi-in event byte 2 (data2) Register
        endc


;=============================================================================
;  Start of code
;=============================================================================
;start
        org         h'0000'                 ; processor reset vector
        goto        main                    ; jump to the main routine

        org         h'0004'                 ; interrupt vector location
        movwf       w_temp                  ; save off current W register contents
        swapf       STATUS, W               ; move status register into W register
        movwf       status_temp             ; save off contents of STATUS register
        swapf       PCLATH, W               ; move pclath register into W register
        movwf       pclath_temp             ; save off contents of PCLATH register

        ; isr code can go here or be located as a call subroutine elsewhere

        swapf       pclath_temp, W          ; retrieve copy of PCLATH register
        movwf       PCLATH                  ; restore pre-isr PCLATH register contents
        swapf       status_temp, W          ; retrieve copy of STATUS register
        movwf       STATUS                  ; restore pre-isr STATUS register contents
        swapf       w_temp, F
        swapf       w_temp, W               ; restore pre-isr W register contents
        retfie                              ; return from interrupt


;=============================================================================
;  Includes
;=============================================================================
	#include    "../xp-midi-common.X/xp-midi-usart.inc"   ; midi usart routines
	#include    "../xp-midi-common.X/xp-midi-parser.inc"  ; midi event parser routines


;=============================================================================
;  Init I/O ports
;    set RB1 (RX) and RB2(TX) as Input, the others PIN as Output.
;=============================================================================
init_ports:

        errorlevel  -302

        bcf         STATUS, RP0             ; select Bank0
        movlw       b'00000100'             ; initialize PORTB by clearing output data latches and set RB2(TX)
        movwf       PORTB
        bsf         STATUS, RP0             ; select Bank1
        movlw       b'00000110'             ; PORTB input/output
        movwf       TRISB
        bcf         STATUS, RP0             ; select Bank0

        errorlevel  +302

        return


;=============================================================================
;  Init Timer0 (internal clock source)
;=============================================================================
init_timer:
        errorlevel	-302

        ; Clear the Timer0 registers
        bcf	    STATUS, RP0		    ; select Bank0
        clrf        TMR0                    ; clear module register

        ; Disable interrupts
	clrf	    INTCON		    ; disable interrupts and clear T0IF

        ; Set the Timer0 control register
        bsf	    STATUS, RP0		    ; select Bank1
        movlw       b'10000000'             ; setup prescaler (1:8) and timer
        movwf       OPTION_REG
        bcf	    STATUS, RP0		    ; select Bank0

        errorlevel  +302

        return


;=============================================================================
;  RX/TX error handler routines
;=============================================================================
error_handler:
	call	    clear_midi_usart_regs
        return


;=============================================================================
;  main routine
;=============================================================================
main
        call        init_ports
        call        init_midi_usart
	call	    init_timer

	call	    clear_midi_usart_regs
	call	    clear_midi_parser_regs

;==== tasks scheduler ========================================================
schedulerloop
        btfss       INTCON, T0IF            ; timer overflow (51.2us)
        goto        schedulerloop	    ; no, loop!
        bcf         INTCON, T0IF            ; clear overflow flag

; --  scan midi-in -----------------------------------------------------------
begin_task_1
	call	    clear_midi_usart_regs
	call        scan_midi_in_data
end_task_1

; --  parse midi-in event ----------------------------------------------------
begin_task_2
        btfss	    midiInStatus, BYTE_RECEIVED
	goto	    end_task_2
	
;	movf	    midiInByte, W		; test for system message family
;	andlw       b'11110000'
;        sublw       b'11110000'
;        btfsc       STATUS, Z			; skip system message family
;	goto        endloop

        call        parse_midi_in_event
	
	btfsc	    eventInStatus, SYSTEM_MESSAGE
	goto	    endloop
end_task_2

; --  echo message -----------------------------------------------------------
begin_task_3
	;; verificare il corretto # di bytes da inviare
	btfss	    eventInStatus, EVENT_RECEIVED
	goto	    end_task_3

	;movf        eventInByte0, W
	movlw	    b'10010000'
	call	    send_midi_out_data
	;movf        eventInByte1, W
	movlw	    32
	call	    send_midi_out_data
	;movf        eventInByte2, W
	movlw	    64
	call	    send_midi_out_data
	call	    clear_midi_parser_regs
end_task_3

endloop
        goto        schedulerloop

;==== tasks scheduler ========================================================
        end


;; da sistemare:
;;	- TX routine: non è necessario attendere qui il completamento dell'invio, quindi
;;		va gestito altrove nello scheduler loop...