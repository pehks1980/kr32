
from lexer import Lexer


# A minimal C program to use as input for the lexer.
source = r"""
int main(void) {
	int x,y,z;

	while (1) {
	 	x = 0;
		y = 1;
		do {
			printf("%d\n", x);
			z = x+y;
			x = y;
			y = z;
		} while (x < 255);	
	}

}
"""

# Print every token so we can inspect the categories,
# values, and source positions produced by the lexer.
for token in Lexer(source).tokenize():
    print(token)
