;*********************************************
;* 
;* "DewPoint_cycling" - Measuring dew
;*
;* Description: Program measures the ambient
;* temperature first for a few seconds, 
;* the program than starts cooling the TEC
;* mirror until there's condensation on it,
;* the program keeps polling PD6 ( DPS) 
;* until DPS is high, once DPS is set the
;* LED is turned off than dew point meas is
;* complete.
;*
;*
;* Author: Syed Ahmed and Neil Vaitoonkait
;* Version: 0.0

;*
;* Parameters: Push buttons and associated ADC
;* push button 7 used to select ADC 7
;* push button 6 used to select ADC 6
;* push button 5 used to select ADC 5
;*
;* 
;* Subroutine hex_2_7seg called
;* Subroutine mux_diplay called
;* Subroutine var delay called
;*
;* Notes: 0s turn on digits and 0s turn on segments
;* The segments are a through g at PB6 through
;* PB0 respectively. The digit drivers are 
;* PA2 through PA0 for digits dig2 through dig0.
;* The values inside each register gets changed 
;* permanantely.
;* registers used: r16, r17, r24
;* global registers:
;***************************************************************************

.nolist
.include "m16def.inc"
.list


reset:
	.org RESET				
	rjmp start
	.org int1addr
	rjmp keypress_isr	
	.org 0x0A
	rjmp slow_decrease
start:
	//make pin4 output, else input
	ldi r16, 0b10110000
	out ddrd, r16 ;make portd 10110000
	ldi r16, $ff
	out ddrb, r16 ;make portb output
	//activation of transistors
	ldi r17, $07  ;output for transistors, bit 7 for ADC
	out ddra, r16 ;make pa0-pa2 output
	ldi r17, 0b10110000 ;
	;out ddrc, r17
	//stack
	ldi r17, LOW(RAMEND) ;low byte
	out SPL, r17
	ldi r16, HIGH(RAMEND);high byte
	out SPH, r17
	;read positive trigger
	ldi r16, (1<<ISC11)|(1<<ISC10) ;sense rising edge
	out MCUCR, r16
	ldi r16, 1<<INT1  ;enable interrupt 1
	out GICR, r16
;****************Enable ADC*****************
	ldi r17, $84	 ;enable adc with internal reference volt
	out adcsra, r17
	ldi r17, $C7 	;use internal reference voltage
	out ADMUX, r17

;* registers used: r17, r25
display_post:
	ldi r17, $f8  ;make all leds display 8
	out PORTA, r17
	ldi r25, $00
	out portb, r25
	call var_delay1 ;1 second delay
	ldi r17, $ff ;turn off all leds
	out PORTA, r17
	
;****************Timer0 Overflow*************
	ldi r24, 1<<TOV0 ;enable timeroverflow
	out TIFR, r24
	ldi r24, $02
	out TCCR0, r24
	ldi r24, 1<<TOIE0 ;set timer overflow flag
	out TIMSK, r24
	sei

;****************Timer1 Overflow*************
	ldi r16, 0xFF
	out OCR1AH, r16
	ldi r16, 0xFF
	out OCR1AL, r16 ; sets 0x0FFF as TOP value

	ldi r16, 0xFF
	out OCR1BH, r16
	ldi r16, 0xFF
	out OCR1BL, r16 ; duty cycle begins at ~100% 

	ldi r16, 0x23 ; 00100011
	out TCCR1A, r16 ; non inverting & mode 15
	ldi r16, 0x5A ; 01011010
	out TCCR1B, r16 ; rising edge input capture, mode 14 & clk/8

;* registers used: r16, 
;* global: r0,r1,r2
ADC_loop:
	sei		;enable interrupt calls
	sbi ADCSRA, ADSC ;start conversion
ADC_polling:
	sbis ADCSRA, ADIF ;wait for conversion end
	rjmp ADC_polling ;keep polling
	sbi ADCSRA, ADIF ;stop conversion
	//division
	in r26, ADCL  ;load ADCL
	in r27, ADCH  ;load ADCH
	ldi r25, $00 ;0 for decimal

	lsr r27		;shift most significant to right
	ror r26		;shift least significant to right of decimal
	ror r25		;
	
	lsr r27    ;shift again for *4
	ror r26		;shit again
	ror r25		;shift again

	;***** Subroutine Register Variables

.def	fbin	=r23		;8-bit binary value
.def	tBCDL	=r21		;BCD result MSD
.def	tBCDH	=r17		;BCD result LSD

	mov	fbin, r26			;moves r26 into fbin for BCD
	
	rcall bin2bcd8			;calls BCD subroutine	
	mov r16, r17			;copy bcd value
	andi r16, $0f			;mask unneeded bits
	rcall bcd_7seg			;get segmentted value
	//value for r0		
	mov r2, r16				;send value to r2
	
	mov r16, r23			;copy bcd value
	;swap r16				;make unneeded bits
	andi r16, $0f			;make unneeded bits
	rcall bcd_7seg			;get segmentted value
	mov r1, r16				;send value to r1
	
	in r16, ADCH			;read high byte
	andi r16, $03			;send
	rcall bcd_7seg			;get segmentted value
	//value for r2
	mov r0, r16				;send to mux_display
	rjmp ADC_loop			;jump back



;*******************************************************
;* 
;* "keypress_isr"- Interrupt for keypress
;* ATMega16
;*
;* Description: Detects a keypress from encoder
;* connected to EO of encoder when key press detected
;* the program jumps to ISR for measurement, the 
;* program compares the value entered and goes to the 
;* correct measurand program
;* Author: Syed Ahmed and Neil Vaitoonkait
;* Version: 0.0
;*
;*
;* Parameters: 
;* Usage of the SREG I register
;* r19 to load PIND value
;* reti 
;******************************************************
keypress_isr:
	push r18			;copy register
	in r18, SREG		;copy sreg
	push r18			;copy register
	
	in r19, PIND		;read pin
	andi r19, $07		;mask bits
	
	sbi Portd, 4		;turn on TEC DPH
	
	cpi r19, $00		;read push button 
	breq dew_point		;branch to dew_point

	cpi r19, $01
	breq slow_decrease

return:	
	pop r18				;restore register
	out SREG, r18		;restore register
	pop r18				;restore register
	reti				;return to where interrupt

dew_point:			
	cbi portd, 5		;heat mirror 
	rcall var_delay1	;delay of 1 second
	rcall var_delay1	;delay of 1 second
	sbi portd, 5		;start cooling the mirror
cooling:
	sbis pind, 6		;wait for DPS signal to be high
	rjmp cooling		;keep polling
	cbi portc, 6		;turn on LED
	ldi r29, $c7		;turn on adc7
	out admux, r29		;turn on adc7
	rjmp return			;return back

slow_decrease:
	push r16
	
	//****** when single stepping in simulation, OCR1BH & OCR1BL are swapped!
	ldi r16, 0xD3
	out OCR1BH, r16
	ldi r16, 0xB0
	out OCR1BL, r16 ; changes duty cycle to ~70% to slow down the cooling


	pop r16

;*******************************************************
;* 
;* "bcd_7seg" - Subroutine converts value into segment
;* ATMega16
;*
;* Description: obtains value from adc conversion turns 
;* them into segment value used for displaying the LED
;* the values are loaded onto a table
;* Author: Syed Ahmed and Neil Vaitoonkait
;* Version: 0.0
;*
;*
;* Parameters: 
;* r16 - value to be converted
;* r30 low z pointer
;* r31 high z pointer
;*
;******************************************************

bcd_7seg:
	push r17		;copy register
	ldi ZH, high(hextable * 2)	;load high byte
	ldi ZL, low (hextable * 2)	;load high byte
	ldi r17, $00		;load 0's
	adc ZH, r17			;load 0's to zh
	add ZL, r16			;read the value coming in
	lpm r16, Z			;load hex value from table
	pop r17				;restore
	ret					;return back 
	hextable: .db $01, $4f, $12, $06, $4c, $24, $60, $0f, $00, $0c, $08, $80, $b1, $81, $b0, $b8

;*******************************************************
;* 
;* "mux_display" - subroutine for display
;*
;* Description: subroutine outputs value to portb
;* value is multiplexed so digits are visible each
;* digit is turned on with its respective bcd value
;* delay fixes the flicker frequency
;*
;* Author: Syed Ahmed Neil Vaitoonkait
;*
;* Parameters: 
;* r0 - digit 0
;* r1 - digit 1
;* r2 - digit 2
;* r20 - counter
;*
;******************************************************
mux_display:
	push r28		;copy register	
	in r28, SREG	;copy sreg
	push r28		;copy register
	push r20		;copy register

	ldi r20, $FE		;turn on porta transistor
	out PORTA, r20		;turn on porta
	out PORTB, r0		;output value for r0
	//dig0
	rcall var_delay		;delay for mux display
	ldi r20, $fd		;turn on porta transistor
	out porta, r20		;turn on porta transistor
	out portb, r1		;output value for r1
	//dig1
	rcall var_delay		;delay for mux display
	ldi r20, $fb		;turn on porta transistor
	out porta, r20		;turn on porta transistor
	out portb, r2		;output value for r2
	//dig2
	rcall var_delay		;delay for mux display
	pop r20				;restore register
	pop r28				;restore register
	out SREG, r28		;restore sreg
	pop r28				;restore sreg
	reti				;return for isr
;*******************************************************
;* 
;* "var_delay" - subroutine for delay
;*
;* Description: subroutine creates a delay so there's
;* no flicker frequency and displays are lit with no 
;* ghosting the delay is created through occupying 
;* clock cycles
;*
;* Author: Syed Ahmed Neil Vaitoonkait
;*
;* Parameters: 
;* r21 - outter loop 
;* r27 - innter loop
;*
;******************************************************
var_delay:
	push r21		;copy register
	push r27		;copy register
	ldi r21, 45		;45 decrements
outter_loop:			
	ldi r27, 45		;decrement until 0
inner_loop:
	dec r27			;decrement until 0
	brne inner_loop	;branch out if 0
	dec r21			;decrement until 0
	brne outter_loop ;branch out if 0
	pop r27			;restore register
	pop r21			;restore register
	ret				;return to where subroutine called

var_delay1:		
		push r17	;copy register
		push r16	;copy register
		ldi r17, 246 ;246 decrements
	outer_loop1:
		ldi r16, 246 ;246 decrements
	inner_loop1:
		dec r16		;keep decrementing
		brne inner_loop1 ;branch out when 0
		dec r17		;keep decrementing
		brne outer_loop1	;branch out when 0
		pop r16		;restore register
		pop r17		;restore register
		ret			;return subroutine
;***************************************************************************
;* Author: ATMEL
;* Modified/Used by: Syed Ahmed & Neil Vaitoonkait
;* "mpy8u" - 8x8 Bit Unsigned Multiplication
;*
;* This subroutine multiplies the two register variables mp8u and mc8u.
;* The result is placed in registers m8uH, m8uL
;*  
;* Number of words	:9 + return
;* Number of cycles	:58 + return
;* Low registers used	:None
;* High registers used  :4 (mp8u,mc8u/m8uL,m8uH,mcnt8u)	
;*
;* Note: Result Low byte and the multiplier share the same register.
;* This causes the multiplier to be overwritten by the result.
;*
;***************************************************************************

bin2bcd8:
	clr	tBCDH		;clear result MSD
bBCD8_1:subi	fbin,10		;input = input - 10
	brcs	bBCD8_2		;abort if carry set
	inc	tBCDH		;inc MSD
;---------------------------------------------------------------------------
;				;Replace the above line with this one
;				;for packed BCD output				
;	subi	tBCDH,-$10 	;tBCDH = tBCDH + 10
;---------------------------------------------------------------------------
	rjmp	bBCD8_1		;loop again
bBCD8_2:subi	fbin,-10	;compensate extra subtraction
;---------------------------------------------------------------------------
;				;Add this line for packed BCD output
;	add	fbin,tBCDH	
;---------------------------------------------------------------------------	
	ret



















