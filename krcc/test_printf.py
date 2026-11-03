from lexer import Lexer
from parser import Parser


# Test printf with one variable argument.
source = r"""
int main(void) {
    int x;

    x = 42;

    printf("%d\n", x);

    return 0;
}
"""

source = r"""
int main(void) {
    int x, y;

    x = 10;
    y = 20;

    printf("x=%d y=%d\n", x, y);
    printf("sum=%d\n", x + y);

    return 0;
}
"""


# Stage 1: Lexical analysis.
tokens = Lexer(source).tokenize()

print("=== TOKENS ===")

for token in tokens:
    print(token)


# Stage 2: Syntax analysis.
parser = Parser(tokens)

ast = parser.parse_translation_unit()

print("\n=== AST ===")
print(ast)