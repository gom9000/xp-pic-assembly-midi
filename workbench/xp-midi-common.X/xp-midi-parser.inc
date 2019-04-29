;=============================================================================
; @(#)xp-midi-parser.inc  0.1  2016/01/06
;   ________        _________________.________
;  /  _____/  ____ /   _____/   __   \   ____/
; /   \  ___ /  _ \\_____  \\____    /____  \
; \    \_\  (  <_> )        \  /    //       \
;  \______  /\____/_______  / /____//______  /
;         \/              \/               \/
; Copyright (c) 2016 by Alessandro Fraschetti.
; All Rights Reserved.
;
; Description: Simple MIDI event parser
; Target.....: Microchip PIC 16F6x8a Microcontroller
; Compiler...: Microchip Assembler (MPASM)
; Note.......:
;=============================================================================


; TODO manages system messages (common, real-time and sysex)


;;	; eventInStatus Flags
;;	BYTE_0_RECEIVED	equ	0x02	    ; event byte 0 (status) received flag
;;	BYTE_1_RECEIVED	equ	0x03	    ; event byte 1 (data1) received flag
;;	BYTE_2_RECEIVED	equ	0x04	    ; event byte 2 (data2) received flag
;;	EVENT_RECEIVED  equ     0x05	    ; event full received flag
;;	SYSTEM_MESSAGE  equ	0x06	    ; event family (0=Channel Message, 1=System Message)
;;
;;	eventInStatus			    ; midi-in event Status Register
;;	eventInByte0			    ; midi-in event byte 0 (status) Register
;;	eventInByte1			    ; midi-in event byte 1 (data1) Register
;;	eventInByte2			    ; midi-in event byte 2 (data2) Register


;=============================================================================
;  Clear Midi parser Registers
;=============================================================================
clear_midi_parser_regs:
	clrf	    eventInStatus
	return


;=============================================================================
;  parse midi-in event
;=============================================================================
parse_midi_in_event:
        movf	    midiInByte, W		    ; test for statusbyte
        andlw       b'10000000'
        btfss       STATUS, Z
        goto        found_statusbyte		    ; is statusbyte, check data
        btfss       eventInStatus, BYTE_0_RECEIVED  ; isn't. Test if a statusbyte was received
        return
        btfss       eventInStatus, BYTE_1_RECEIVED  ; test for databyte
        goto        found_databyte1		    ; is databyte1, check data
        goto        found_databyte2		    ; is databyte2, check data

found_statusbyte
	movf	    midiInByte, W		    ; test for system message
	andlw       b'11110000'			    ; or channel message
        sublw       b'11110000'
        btfsc       STATUS, Z
        goto        found_system_message

        clrf        eventInStatus		    ; reset status register
	clrf        eventInByte1		    ; reset databyte registers
        clrf        eventInByte2		    ;
        movf        midiInByte, W		    ; save statusbyte
        movwf	    eventInByte0		    ;
        bsf         eventInStatus, BYTE_0_RECEIVED  ; and update status register
check_note_off
        movf	    eventInByte0, W		    ; test for channel voice message
	andlw       b'11110000'			    ; note off
        sublw       b'10000000'
        btfss       STATUS, Z
        goto        check_note_on
	movf	    eventInStatus, W		    ; set # of expected bytes
	addlw	    0x03
	movwf	    eventInStatus
        return
check_note_on
        movf	    eventInByte0, W		    ; test for channel voice message
	andlw       b'11110000'			    ; note on
        sublw       b'10010000'
        btfss       STATUS, Z
        goto        check_poly_pressure
	movf	    eventInStatus, W		    ; set # of expected bytes
	addlw	    0x03
	movwf	    eventInStatus
        return
check_poly_pressure
        movf	    eventInByte0, W		    ; test for channel voice message
	andlw       b'11110000'			    ; polyphonic key pressure
        sublw       b'10100000'
        btfss       STATUS, Z
        goto        check_control_change
	movf	    eventInStatus, W		    ; set # of expected bytes
	addlw	    0x03
	movwf	    eventInStatus
        return
check_control_change
        movf	    eventInByte0, W		    ; test for channel voice message
	andlw       b'11110000'			    ; control change
        sublw       b'10110000'
        btfss       STATUS, Z
        goto        check_program_change
	movf	    eventInStatus, W		    ; set # of expected bytes
	addlw	    0x03
	movwf	    eventInStatus
        return
check_program_change
        movf	    eventInByte0, W		    ; test for channel voice message
	andlw       b'11110000'			    ; program change
        sublw       b'11000000'
        btfss       STATUS, Z
        goto        check_channel_pressure
	movf	    eventInStatus, W		    ; set # of expected bytes
	addlw	    0x02
	movwf	    eventInStatus
        return
check_channel_pressure
        movf	    eventInByte0, W		    ; test for channel voice message
	andlw       b'11110000'			    ; channel pressure
        sublw       b'11010000'
        btfss       STATUS, Z
        goto        check_pitch_bend_change
	movf	    eventInStatus, W		    ; set # of expected bytes
	addlw	    0x02
	movwf	    eventInStatus
        return
check_pitch_bend_change
        movf	    eventInByte0, W		    ; test for channel voice message
	andlw       b'11110000'			    ; pitch bend change
        sublw       b'11010000'
        btfss       STATUS, Z
        return
	movf	    eventInStatus, W		    ; set # of expected bytes
	addlw	    0x03
	movwf	    eventInStatus
        return

found_system_message
	bsf         eventInStatus, SYSTEM_MESSAGE   ; system message

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
        movf        midiInByte, W		    ; save databyte
        movwf	    eventInByte1		    ;
        bsf         eventInStatus, BYTE_1_RECEIVED  ; and update status register
	movf	    eventInStatus, W		    ; test for expected bytes
	andlw       b'00000011'
        sublw       b'00000010'
        btfss       STATUS, Z			    ; waiting for databyte2
        return
	bsf	    eventInStatus, EVENT_RECEIVED   ; event fully received
	return

found_databyte2
        movf        midiInByte, W		    ; save databyte
        movwf	    eventInByte2		    ;
        bsf         eventInStatus, BYTE_2_RECEIVED  ; and update status register
	movf	    eventInStatus, W		    ; test for expected bytes
	andlw       b'00000011'
        sublw       b'00000011'
        btfss       STATUS, Z			    ; waiting for...?
        return
	bsf	    eventInStatus, EVENT_RECEIVED   ; event fully received
	return
