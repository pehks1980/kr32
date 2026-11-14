from lexer import Lexer
from parser import Parser

source = r"""
int calculate(int a, int b)
{
    return a + b;
}

int helper(int value)
{
    return value * 2;
}

int main(void)
{
    return 0;
}
"""

tokens = Lexer(source).tokenize()
ast = Parser(tokens).parse_translation_unit()

print("Functions:", len(ast.functions))

for function in ast.functions:
    print(f"\nFunction: {function.name}")

    for parameter in function.parameters:
        print(
            f"  Parameter: {parameter.var_type} "
            f"{parameter.name}"
        )
