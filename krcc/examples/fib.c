// second program to make with c compiler
int main(void) {
	int x,y,z,c;

	c = 1;

	while (1) {
		printf("=====cycle: %d======\n", c);
	 	x = 0;
		y = 1;
		do {
			printf("number:%d\n", x);
			z = x+y;
			x = y;
			y = z;
		} while (x < 1255);
		c = c + 1;	
	}

}

