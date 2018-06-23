/*
 * CFile1.c
 *
 * Created: 8/6/2018 19:21:57
 *  Author: marti
 */ 
#include <avr/io.h>
#include <math.h>

#define YLOW 0X300 /*Aca pongo las posiciones de memoria donde busca la gravedad de cada eje*/
#define YHIGH 0X301  /*Que por estar en registros vienen separadas*/
#define ZLOW 0X302
#define ZHIGH 0X303
#define ACELPOS 0X304
#define ANGPOS 0X305


#define pi 3.1415

unsigned int volatile const * yal = (unsigned int *) YLOW;
unsigned int volatile const * yah = (unsigned int *) YHIGH;
unsigned int volatile const * zal = (unsigned int *) ZLOW;
unsigned int volatile const * zah = (unsigned int *) ZHIGH;
unsigned int volatile * const angp = (unsigned int *) ANGPOS;
unsigned int volatile * const acelp = (unsigned int *) ACELPOS;

void angulo(void)
{
	int YMAX,YMIN,ZMAX,ZMIN;
	float y,z;
	int yb,zb,yl,zl,yh,zh,acel;
	unsigned char ang;
	
	
	
	yh=*yah;
	yh=((*yah)<<8);
	yl=(char)(*yal);
	yb=yh;
	yb=yb+yl;

	zh=*zah;
	zh=((*zah)<<8);
	zl=(char)(*zal);
	zb=zh;
	zb=zb+zl;
	
	acel=*acelp;
	if (acel==1) /*Indice*/
	{
		YMAX=996;
		YMIN=336;
		ZMAX=872;
		ZMIN=235;
	}
	if(acel==2) /*Pulgar*/
	{
		YMAX=986; /*ATENCION: Le pongo Y por comodidad, pero me estoy refiriendo al eje x. Tener en cuenta para las conexiones.*/
		YMIN=342;
		ZMAX=866;
		ZMIN=213;
	}
	if(acel==3) /*Mayor*/
	{
		YMAX=997;
		YMIN=347;
		ZMAX=866;
		ZMIN=221;
	}
	if(acel==4) /*Menique y anular*/
	{
		YMAX=999;
		YMIN=372;
		ZMAX=863;
		ZMIN=234;
	}

	/* Quiero yb=844 zb=711 para obtener 45 grados*/
	y=(200000*(yb-YMIN)/(YMAX-YMIN)-100000); /*mapeo multiplicado por 100000 para dar mas resolucion y precision*/
	z=(200000*(zb-ZMIN)/(ZMAX-ZMIN)-100000);
	
	
	if(acel==2)
	{
		ang=180-acos(y/100000)*180/pi;
		if(ang>135)
		{
			ang=135; /*Le pongo esta limitacion porque a partir de este punto empieza a medir mal*/
		}
	}
	else
	{	
		ang=fabs(atan(z/y))*180/pi;
		if(y<0 && z<0)
		{
			ang=180-(fabs(atan(z/y))*180/pi);
		}
		if(y<0 && z>0)
		{
			ang=180;
		}
		if(y>0 && z>0)
		{
			ang=0;
		}	
	}
	
	*angp=(char)ang; /*Va de 0 a 180 grados*/
}
/*
 * CFile1.c
 *
 * Created: 22/6/2018 17:04:19
 *  Author: marti
 */ 
