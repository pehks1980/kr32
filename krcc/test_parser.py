from lexer import Lexer
from parser import Parser


source = """
int main(void)
{
    printf("Hello from KR32!\\n");
    return 0x2A;
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