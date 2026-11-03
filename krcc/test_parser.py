from lexer import Lexer
from parser import Parser


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
source = r"""
int main(void) {
    int x, y, z;
    return 0;
}
"""
source = r"""
int main(void) {
    int x, y, z;

    x = 10;
    y = 20;
    z = x + y * 2;

    return 0;
}
"""

source = r"""
int main(void) {
    int x;

    x = 0;

    while (x < 10) {
        x = x + 1;
    }

    return 0;
}
"""

source = r"""
int main(void) {
    int x;
    int y;

    x = 0;
    y = 1;

    do {
        x = x + 1;
        printf("x=%d y=%d\n", x, y);
        // printf("sum=%d\n", x + y);
    } while (x < 10);

    return x*y;
}
"""

# Stage 1: Lexical analysis
tokens = Lexer(source).tokenize()
print(tokens)

# Stage 2: Syntax analysis
parser = Parser(tokens)
ast = parser.parse_translation_unit()

# Display the resulting Abstract Syntax Tree
print(ast)