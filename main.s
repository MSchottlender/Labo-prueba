#include <avr/io.h>
#include <avr/iom2560.h>
;#include <avr/interrupt.h>

.global main
.EXTERN angulo

 ;Aca irian los .equ (no se si son defines)
#define baudrate  103
#define	B_S3003 1000
#define	A_S3003 17
#define	B_SG90 1050
#define	A_SG90 11
#define INT_VECTORS_SIZE 114
#define INT0addr 0x0002


;.dseg
.section .data
#define	AUX		R16
#define	PWML	R30
#define	PWMH	R31
.org 0x300
ejes: .byte 10

;.cseg
.section .text
main:
LDI r16,hi8(RAMEND)	;Inicializo Stack Pointer
	sts SPH, r16
	LDI r16, lo8(RAMEND)
	sts SPL, r16
call USART_Init ;Inicializo demas funciones
call SETUP_ADC
call configure_pwm

todo:
call acel
call DELAY_1S
call pwm
call DELAY_1S
rjmp todo

/********************** ACELEROMETROS *************************/

acel:
BEGIN_ADC_1:
	clr r17
	ldi r16,0x01 ;Esto es para pasarle al .c que esta en el primer acelerometro
	sts 0X304,r16
	ldi r16, 0xC0 ;Esto implica que la AREF es interna (2,56 V), que se usan los bits 0-9 del ADC y (por el momento)
	sts ADMUX, r16;que se usa el bit 0. RECOMENDADO USAR CAPACITOR DE 100nF PARA MEJORAR PRECISION
READ_ADC_1:
	ldi r18,0x40 ;(Con el or le agrega unicamente el pin para la conversion)
	lds r19,ADCSRA
	or r18,r19
	sts	ADCSRA,r18 ;Hace la conversion
KEEP_POLING_1:
	lds r18,ADCSRA
	sbrs r18,4; Me fijo si el ADIF esta set y si lo esta pasa a transferir los datos
	rjmp KEEP_POLING_1
	subi r18,0x08 ;Vuelvo el ADIF a 0
	sts ADCSRA,r18
	tst r17 ;es un contador para fijarse si ya paso por Y
	brne Z_AXIS_1
Y_AXIS_1:
	lds r16,ADCL
	sts 0x300,r16
	lds r16,ADCH
	sts 0x301,r16
	ldi r16, 0xC1 ;Mantiene lo del AREF y la convencion de bits, pero usa el bit 1 (para el eje z)
	sts ADMUX, r16
	ldi r17, 0x01 ;Para que ponga los proximos datos en Z
	rjmp READ_ADC_1
Z_AXIS_1:
	lds r16,ADCL
	sts 0x302,r16
	lds r16,ADCH
	sts 0x303,r16
	rcall angulo
	lds r21, 0x305 ;Aca sale el angulo de 1
	;ldi r21,0x5A
	mov r16,r21
	call USART_Transmit
	call DELAY_20MS ; LALALALALALALA
	ret


SETUP_ADC:
	ldi r16, 0x87 
	sts ADCSRA, r16 ;Enciendo el ADC y uso una frecuencia de actualizacion de Ck/128=125KHz
	ret

/***************************** PUERTO SERIE *****************************************/


USART_Init:		; Seteo de la transmision y recepcion mediante puerto serie
	push r16	; Guardo r16 y r17 en el stack para que no perder el valor que poseen
	push r17
	ldi r16,lo8(103) ; Baud rate = 9600 (8 MHz)
	ldi r17,hi8(103)
	sts UBRR0H, r17	; Guardo el Baudrate en UBRR0	
	sts UBRR0L, r16	; Utilizo STS en vez de OUT, ya que las direcciones estan en "extended I/O"

	; Habilito el receptor y transmisor
	ldi r16, (1<<RXEN0)|(1<<TXEN0)
	sts UCSR0B, r16

	; Seteamos el formato del puerto serie: 8 data, 1 stop bit
	ldi r16, (0<<USBS0)|(3<<UCSZ00)
	sts UCSR0C, r16

	pop r17		; Recuperamos los valores guardados de r16 y r17
	pop r16
	RET

USART_Transmit:
	push r17	; Guardo el valor de r17 en el stack para poder utilizarlo (Flags check)
	

check_transmit_buffer_empty:	; Espero a que el buffer de transmision se vacie
	lds r17, UCSR0A
	sbrs r17, UDRE0
	rjmp check_transmit_buffer_empty

	sts UDR0,r16	; Dato cargado antes de la función

	pop r17		; Recupero el valor anterior de r17
	RET

		
USART_Receive:
	push r17

check_receive_data_completition:
	; Wait for data to be received
	lds r17, UCSR0A
	sbrs r17, RXC0
	rjmp check_receive_data_completition

	; Get and return received data from buffer
	lds r16, UDR0
	
	
	pop r17
	RET



/*********************** DELAYS *********************************/

DELAY_20MS:
	ldi r16,150
	ldi r17,160
	ldi r18,2
	Loop:
		dec r16
		brne Loop
		dec r17
		brne Loop
		dec r18
		brne Loop
	nop
	ret


DELAY_1S:
	ldi r16,3
	ldi r17,44
	ldi r18,82
	Loop2:
		dec r16
		brne Loop2
		dec r17
		brne Loop2
		dec r18
		brne Loop2
	ret



/**************************** SERVO *************************************/
	
pwm:
	call Transformar_angulo
	call set_pwm_uno
	ret

/*Abierto:
	ldi r17,180; Inicio el ancho de pulso en 1ms
	call Transformar_angulo
	call set_pwm_uno
	ret*/

		
configure_pwm: ; Primero seteo el T/C para que se resetee cada 20ms y que hasta que encuentre OCR1B este en 1 (Ancho de pulso variable para el servo)

	; Fast PWM (WGM[3:0] = 15) y en modo non-inverting para el registro OC1B, lo limpia cuando matchea y lo setea de vuelta en BOTTOM
	ldi r16, 0xFF

	sbi _SFR_IO_ADDR(DDRB),6   ; Pongo como salida el pin OC1B por donde va a salir la señal del PWM pin 12
	
	;;;;;;;;;;;;;;;;;;CONFIG SERVO 1: pin 12, OC1B;;;;;;;;;;;;;;
	lds AUX,TCCR1A
	ori AUX,(1<<COM1B1)|(1<<WGM11)|(1<<WGM10) ; Set en modo non-inverting, WGM11 y WGM10 en 1 para setear el modo Fast PWM
	sts TCCR1A,AUX

	lds AUX,TCCR1B
	ori AUX,(1<<WGM13)|(1<<WGM12) ; Set en modo Fast PWM, el contador se resetea cuando llega a OCR1A
	ori AUX, (1<<CS11) ; Set prescaler en 8
	sts TCCR1B,AUX

	; Poniendo el prescaler en 8, y con una frecuencia de 16MHz,contar hasta 40000 tarda 20ms
	; 40000/(16Mega/8) = 0.02
	ldi PWMH, hi8(40000)
	ldi PWML, lo8(40000) 
	sts OCR1AH,PWMH
	sts OCR1AL,PWML


	;;;;;Inicializo todos los servos abiertos;;;;;
	ldi PWMH, hi8(3000)
	ldi PWML, lo8(3000) ; Inicio el ancho de pulso en 1ms
	call set_pwm_uno	;A esta funcion se la llama cada vez que se quiera modificar el ancho de pulso
	ret
  
set_pwm_uno: ; El registro OCR1B es el que determina el ancho de pulso. Con esta funcion actualizo ese registro con lo que hay en PWMH/L

	sts OCR1BH,PWMH
	sts OCR1BL,PWML
	ret

Transformar_angulo:
	ldi r18, lo8(B_S3003)
	ldi r19, hi8(B_S3003)
	ldi r20, A_S3003	
	mul r21, r20
	add	r18,r0
	adc r19,r1
	/*ldi r19,0x0A ;HARDCODEADO 45 GRADOS
	ldi	r18,0xCD*/
	mov PWMH, r19
	mov PWML, r18 /*Probar poner codigo de setpwmuno aca*/
	ret

