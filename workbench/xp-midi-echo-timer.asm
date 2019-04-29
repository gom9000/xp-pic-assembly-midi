;=============================================================================
; @(#)xp-midi-echo.asm
;                       ________.________
;   ____   ____  ______/   __   \   ____/
;  / ___\ /  _ \/  ___/\____    /____  \ 
; / /_/  >  <_> )___ \    /    //       \
; \___  / \____/____  >  /____//______  /
;/_____/            \/                \/ 
; Copyright (c) 2016 by Alessandro Fraschetti (gos95@gommagomma.net).
;
; This file is part of the xp-midi project:
;     https://github.com/gos95-electronics/xp-midi
; This code comes with ABSOLUTELY NO WARRANTY.
;
; Author.....: Alessandro Fraschetti
; Company....: gos95
; Target.....: Microchip PICmicro 16F648A Microcontroller
; Compiler...: Microchip Assembler (MPASM)
; Version....: 1.0 2016/01/05
; Description: Simple MIDI echo
;=============================================================================

    PROCESSOR   16f648a
    INCLUDE     <p16f648a.inc>
;    INCLUDE     "../xp-midi-common.X/xp-midi-usart.inc"


;=============================================================================
;  CONFIGURATION
;=============================================================================
    __CONFIG    _CP_OFF & _DATA_CP_OFF & _LVP_OFF & _BOREN_OFF & _MCLRE_ON & _WDT_OFF & _PWRTE_ON & _HS_OSC
;    __CONFIG   _CP_OFF & _DATA_CP_OFF & _LVP_OFF & _BOREN_OFF & _MCLRE_OFF & _WDT_OFF & _PWRTE_ON & _INTOSC_OSC_NOCLKOUT

                ; _CP_[ON/OFF]    : code protect program memory enable/disable
                ; _CPD_[ON/OFF]   : code protect data memory enable/disable
                ; _LVP_[ON/OFF]   : Low Voltage ICSP enable/disable
                ; _BOREN_[ON/OFF] : Brown-Out Reset enable/disable
                ; _WDT_[ON/OFF]   : watchdog timer enable/disable
                ; _MCLRE_[ON/OFF] : MCLR pin function digitalIO/MCLR
                ; _PWRTE_[ON/OFF] : power-up timer enable/disable


;=============================================================================
;  LABEL EQUATES
;=============================================================================
BYTE_RECEIVED       EQU     0x00                ; midi-in byte received flag
OVERRUN_ERROR       EQU     0x06                ; midi-in overrun error flag
FRAME_ERROR         EQU     0x07                ; midi-in frame error flag


;=============================================================================
;  VARIABLE DEFINITIONS
;=============================================================================
DELAY_VAR           UDATA
d1                  RES     1                   ; the delay routine vars
d2                  RES     1                   ;
d3                  RES     1                   ;

XP-MIDI_VAR         UDATA
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
INIT_ROUTINES       CODE
init_ports                                      ; init I/O ports
        errorlevel  -302

        ; set RB1 (RX) and RB2(TX) as Input, the others PIN as Output.
        banksel     PORTB
        movlw       b'00000100'                 ; clear output data latches and set RB2(TX)
        movwf       PORTB
        banksel     TRISB
        movlw       b'00000110'                 ; PORTB input/output
        movwf       TRISB

        errorlevel  +302

        return


;=============================================================================
;  Init Timer0 (internal clock source)
;=============================================================================
init_timer
        errorlevel	-302

        ; Clear the Timer0 registers
        bcf	    STATUS, RP0		    ; select Bank0
        clrf        TMR0                    ; clear module register

        ; Disable interrupts
	clrf	    INTCON		    ; disable interrupts and clear T0IF

        ; Set the Timer0 control register
        bsf	    STATUS, RP0		    ; select Bank1
        movlw       b'10000000'             ; setup prescaler (0) and timer
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

;==== tasks scheduler ========================================================
schedulerloop
        btfss       INTCON, T0IF            ; timer overflow (51.2us)?
        goto        schedulerloop	    ; no, loop!
        bcf         INTCON, T0IF            ; reset overflow flag

; --  scan input -------------------------------------------------------------
begin_task_1
	call	    clear_midi_usart_regs
	call        scan_midi_in_data
end_task_1

; --  echo event -----------------------------------------------------------
begin_task_2
	btfss	    midiInStatus, BYTE_RECEIVED
	goto	    end_task_2
	movf        midiInByte, W
	call	    send_midi_out_data
end_task_2

endloop
        goto        schedulerloop

;==== tasks scheduler ========================================================
        end
