from lexer import Lexer
from parser import Parser

source = """
int calculate(void) {
    return 42;
}

int helper(void) {
    return 100;
}

int main(void) {
    return 0;
}
"""

tokens = Lexer(source).tokenize()
ast = Parser(tokens).parse_translation_unit()

print("Functions:", len(ast.functions))

for function in ast.functions:
    print("Function:", function.name)