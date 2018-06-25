
/*
 * Assembler1.s
 *
 * Created: 25/6/2018 17:44:11
 *  Author: camis
 */ 
 
#include <avr/io.h>
#include <avr/iom2560.h>

.global MAIN
.EXTERN angulo

;Definicion de las variables necesarias
#define baudrate  103
#define	B_S3003 1000	;Esto sirve para transformar los valores del acelerometro al PWM
#define	A_S3003 17
#define	B_SG90 1050
#define	A_SG90 11
#define INT_VECTORS_SIZE 114	;Para que la interrupcion y el programa no se pisen en la memoria
#define INT0addr 0x0002			;Posicion de la interrupcion en la memoria


;.dseg
.section .data
#define	AUX		R16
#define	PWML	R30
#define	PWMH	R31
.org 0x300
ejes: .byte 10

;.cseg
.section .text
rjmp MAIN	;Salto al programa principal
.org INT0addr
call INTERRUPT
;.org INT_VECTORS_SIZE

MAIN:
ldi r16,hi8(RAMEND)	;Inicializacion del Stack Pointer
sts SPH, r16
ldi r16, lo8(RAMEND)
sts SPL, r16
;Inicializacion del resto de las funciones
call SETUP_INTERRUPT	;Seteo de la interrupcion
call USART_INIT		;Configuracion del puerto serie
call SETUP_ADC		;Configuracion del ADC para el acelerometro
call CONFIGURE_PWM  ;Configuracion del PWM para los servos

LOOP:
call ACEL		
call DELAY_20MS
call PWM
rjmp LOOP

/********************** ACELEROMETROS *************************/

ACEL:
BEGIN_ADC_1:
	clr r17
	ldi r16,0x01 ;Le aclara al archivo angulo.c que esta en el primer acelerometro
	sts 0X304,r16
	ldi r16, 0xC0 ;La AREF es interna (2,56 V), se usan los bits 0-9 del ADC y (por el momento)
	sts ADMUX, r16;se usa el bit 0
READ_ADC_1:
	ldi r18,0x40 ;(Con el or le agrega unicamente el pin para la conversion)
	lds r19,ADCSRA
	or r18,r19
	sts	ADCSRA,r18 ;Hace la conversion
KEEP_POLING_1:
	lds r18,ADCSRA
	sbrs r18,4	;Chequea si el ADIF esta seteado y si lo esta, pasa a transferir los datos
	rjmp KEEP_POLING_1
	subi r18,0x08 ;Vuelve el ADIF a 0
	sts ADCSRA,r18
	tst r17 ;Es un contador para fijarse si ya paso por Y
	brne Z_AXIS_1
Y_AXIS_1:
	lds r16,ADCL
	sts 0x300,r16
	lds r16,ADCH
	sts 0x301,r16
	ldi r16, 0xC1 ;Mantiene a AREF y la convencion de bits, pero usa el bit 1 (para el eje z)
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
	;Para ver los valores por el puerto serie, descomentar las dos lineas siguientes
;	mov r16,r21	
;	call USART_Transmit
	ret


SETUP_ADC:
	ldi r16, 0x86
	sts ADCSRA, r16 ;Encendido del ADC y uso de una frecuencia de actualizacion de Ck/64=250KHz
	ret

/***************************** PUERTO SERIE *****************************************/


USART_INIT:		;Seteo de la transmision y recepcion mediante puerto serie
	push r16	;Se guarda r16 y r17 en el stack para no perder el valor que poseen
	push r17
	ldi r16,lo8(baudrate) ;Baudrate = 9600 (8 MHz)
	ldi r17,hi8(baudrate)
	sts UBRR0H, r17	;Se guarda el Baudrate en UBRR0	
	sts UBRR0L, r16	;Se utiliza STS en vez de OUT, ya que las direcciones estan en "extended I/O"

	;Habilitacion del receptor y el transmisor
	ldi r16, (1<<RXEN0)|(1<<TXEN0)
	sts UCSR0B, r16

	;Seteo del formato del puerto serie: 8 data, 1 stop bit
	ldi r16, (0<<USBS0)|(3<<UCSZ00)
	sts UCSR0C, r16

	pop r17		;Recuperacion de los valores guardados de r16 y r17
	pop r16
	RET

USART_Transmit:
	push r17	;Se guarda el valor de r17 en el stack para poder utilizarlo (Flags check)
	

check_transmit_buffer_empty:	;Espera a que el buffer de transmision se vacie
	lds r17, UCSR0A
	sbrs r17, UDRE0
	rjmp check_transmit_buffer_empty

	sts UDR0,r16	;Dato cargado antes de la función

	pop r17		;Se recupera el valor anterior de r17
	RET

		
USART_Receive:
	push r17

check_receive_data_completition:
	;Espera a recibir el dato
	lds r17, UCSR0A
	sbrs r17, RXC0
	rjmp check_receive_data_completition

	;Obtiene y devuelve por el buffer el valor recibido
	lds r16, UDR0
	
	
	pop r17
	RET



/*********************** DELAYS *********************************/

DELAY_20MS:
	ldi r16,150
	ldi r17,160
	ldi r18,2
	Loop1:
		dec r16
		brne Loop1
		dec r17
		brne Loop1
		dec r18
		brne Loop1
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
	
PWM:
	call Transformar_angulo
	call set_pwm_uno
	call set_pwm_dos
	call set_pwm_tres
	call set_pwm_cuatro
	call Transformar_angulo_pulgar
	call set_pwm_cinco
	ret

		
CONFIGURE_PWM: 

	ldi r16, 0xFF

	sbi _SFR_IO_ADDR(DDRB),6 ;Se coloca como salida el pin OC1B por donde va a salir la señal del PWM (pin digital 12)
	sts DDRH,r16 ;Se coloca como salida el pin OC4B y OC4C por donde va a salir la señal del PWM (pin digital 7 y 8)
	sts DDRL,r16 ;Se coloca como salida el pin OC5B y OC5C por donde va a salir la señal del PWM (pin digital 45 y 44)

	;;;;;;;;;;;;;;;;;;CONFIG SERVO 1: pin digital 12 (dedo indice);;;;;;;;;;;;;;
	lds AUX,TCCR1A
	ori AUX,(1<<COM1B1)|(1<<WGM11)|(1<<WGM10) ;Set en modo non-inverting, WGM11 y WGM10 en 1 para setear el modo Fast PWM
	sts TCCR1A,AUX	;La salida es OC1B

	lds AUX,TCCR1B
	ori AUX,(1<<WGM13)|(1<<WGM12) ;WGM13 y WGM12 en 1 para setear el modo Fast PWM, el contador se resetea cuando llega a OCR1A
	ori AUX, (1<<CS11) ;Set prescaler en 8
	sts TCCR1B,AUX

	;Poniendo el prescaler en 8, y con una frecuencia de 16MHz, contar hasta 40000 tarda 20ms
	;40000/(16Mega/8) = 0.02
	ldi PWMH, hi8(40000)
	ldi PWML, lo8(40000) 
	sts OCR1AH,PWMH
	sts OCR1AL,PWML
	
	;;;;;;;;;;;;;;;;;;CONFIG SERVO 2: pin digital 7 (dedo pulgar);;;;;;;;;;;;;;
	
	lds AUX,TCCR4A
	ori AUX,(1<<COM4B1)|(1<<WGM41)|(1<<WGM40) ; Set en modo non-inverting, WGM41 y WGM40 en 1 para setear el modo Fast PWM
	sts TCCR4A,AUX	;La salida es OC4B

	lds AUX,TCCR4B
	ori AUX,(1<<WGM43)|(1<<WGM42) ; WGM43 y WGM42 en 1 para setear el modo Fast PWM, el contador se resetea cuando llega a OCR4A
	ori AUX, (1<<CS41) ; Set prescaler en 8
	sts TCCR4B,AUX

	; Poniendo el prescaler en 8, y con una frecuencia de 16MHz,contar hasta 40000 tarda 20ms
	; 40000/(16Mega/8) = 0.02
	ldi PWMH, hi8 (40000)
	ldi PWML, lo8 (40000) 
	sts OCR4AH,PWMH
	sts OCR4AL,PWML

	;;;;;;;;;;;;;;;;;;CONFIG SERVO 3: pin digital 8 (dedo mayor);;;;;;;;;;;;;;
	;Ya  esta todo seteado previamente
	lds AUX,TCCR4A
	ori AUX,(1<<COM4C1)|(1<<WGM41)|(1<<WGM40) ; Set en modo non-inverting, WGM41 y WGM40 en 1 para setear el modo Fast PWM
	sts TCCR4A,AUX ;La salida es OC4C

	;;;;;;;;;;;;;;;;;;CONFIG SERVO 4: pin digital 45 (dedos anular y meñique);;;;;;;;;;;;;;
	
	lds AUX,TCCR5A
	ori AUX,(1<<COM5B1)|(1<<WGM51)|(1<<WGM50) ; Set en modo non-inverting, WGM31 y WGM30 en 1 para setear el modo Fast PWM
	sts TCCR5A,AUX ;La salida es OC5B

	lds AUX,TCCR5B
	ori AUX,(1<<WGM53)|(1<<WGM52) ; Set en modo Fast PWM, el contador se resetea cuando llega a OCR3A
	ori AUX, (1<<CS51) ; Set prescaler en 8
	sts TCCR5B,AUX

	; Poniendo el prescaler en 8, y con una frecuencia de 16MHz,contar hasta 40000 tarda 20ms
	; 40000/(16Mega/8) = 0.02
	ldi PWMH, hi8 (40000)
	ldi PWML, lo8 (40000) 
	sts OCR5AH,PWMH
	sts OCR5AL,PWML

	;;;;;;;;;;;;;;;;;;CONFIG SERVO 5: pin 44 (dedo pulgar, microservo);;;;;;;;;;;;;;
	lds AUX,TCCR5A
	ori AUX,(1<<COM5C1)|(1<<WGM51)|(1<<WGM50) ; Set en modo non-inverting, WGM31 y WGM30 en 1 para setear el modo Fast PWM
	sts TCCR5A,AUX ;La salida es OC5C


	;;;;;Inicializacion de todos los servos abiertos;;;;;
	ldi PWMH, hi8(1000)
	ldi PWML, lo8(1000) ;Inicio del ancho de pulso en 0.3 ms
	call set_pwm_uno	;A estas funciones se las llama cada vez que se quiera modificar el ancho de pulso de cada servo
	call set_pwm_dos
	call set_pwm_tres
	call set_pwm_cuatro
	ldi PWMH, hi8(1050)
	ldi PWML, lo8(1050) ;Inicio del ancho de pulso en 1 ms para el microservo del pulgar
	call set_pwm_cinco
	ret
  
  
set_pwm_uno: ;El registro OCR1B es el que determina el ancho de pulso. Con esta funcion actualizo ese registro con lo que hay en PWMH/L

	sts OCR1BH,PWMH
	sts OCR1BL,PWML
	ret

set_pwm_dos: ;El registro OCR4B es el que determina el ancho de pulso. Con esta funcion actualizo ese registro con lo que hay en PWMH/L

	sts OCR4BH,PWMH
	sts OCR4BL,PWML
	ret


set_pwm_tres: ;El registro OCR4C es el que determina el ancho de pulso. Con esta funcion actualizo ese registro con lo que hay en PWMH/L

	sts OCR4CH,PWMH
	sts OCR4CL,PWML
	ret
	
set_pwm_cuatro: ;El registro OCR5B es el que determina el ancho de pulso. Con esta funcion actualizo ese registro con lo que hay en PWMH/L

	sts OCR5BH,PWMH
	sts OCR5BL,PWML
	ret
	
set_pwm_cinco: ;El registro OCR5C es el que determina el ancho de pulso. Con esta funcion actualizo ese registro con lo que hay en PWMH/L

	sts OCR5CH,PWMH
	sts OCR5CL,PWML
	ret
	
Transformar_angulo:
	ldi r18, lo8(B_S3003)
	ldi r19, hi8(B_S3003)
	ldi r20, A_S3003	
	cpi r21, 0		;Se chequea si el valor es nulo (se meten ceros entre cada medicion al unir ACEL con PWM)
	breq cero		;Si recibe un cero, vuelve a medir
	mul r21, r20
	add	r18,r0
	adc r19,r1
	mov PWMH, r19
	mov PWML, r18 
	ret

cero:
	jmp LOOP
	
Transformar_angulo_pulgar:
	ldi r18, lo8(B_SG90)
	ldi r19, hi8(B_SG90)
	ldi r20, A_SG90
	cpi r21, 0		;Se chequea si el valor es nulo (se meten ceros entre cada medicion al unir ACEL con PWM)
	breq cero		;Si recibe un cero, vuelve a medir
	mul r21, r20
	add	r18,r0
	adc r19,r1
	mov PWMH, r19
	mov PWML, r18 
	ret


Abierto: ;Esta funcion abre todos los dedos a la vez
	ldi r17,0 ;Seteo del angulo en 0 grados
	call Transformar_angulo
	call set_pwm_uno
	call set_pwm_dos
	call set_pwm_tres
	call set_pwm_cuatro
	call Transformar_angulo_pulgar
	call set_pwm_cinco
	ret

Cerrado: ;Esta funcion cierra todos los dedos a la vez
	ldi r17,180 ;Seteo del angulo en 180 grados
	call Transformar_angulo
	call set_pwm_uno
	call set_pwm_dos
	call set_pwm_tres
	call set_pwm_cuatro
	ldi r17,90
	call Transformar_angulo_pulgar
	call set_pwm_cinco
	ret
	

/**************************** INTERRUPCION *************************************/


SETUP_INTERRUPT:
	sei		;Seteo del flag I del registro SREG para habilitar las interrupciones
	ldi AUX, 0x01
	out EIMSK, AUX	;Se habilita la interrupcion INT0
	ldi AUX, 0x02
	sts EICRA, AUX	;Se configura que la interrupcion se habilite con flanco ascendente
	ldi AUX, 0x00
	out EIFR, AUX	;Se limpian las banderas que indican que una interrupcion se lleva a cabo
	ret

INTERRUPT:

	lds r21, SREG	;Se guardan los registros en el stack para no perderlos si se utilizan en la interrupcion
	push r21
	push r16
	push r17
	push r18
	push r19
	push r20

	call Abierto	;Se abren todos los dedos
	call DELAY_1S

	pop r16
	pop r17
	pop r18
	pop r19
	pop r20
	pop r21
	sts SREG, r21	;Se recuperan los registros que se guardaron en el stack

	reti	;Se vuelve de la interrupcion
	