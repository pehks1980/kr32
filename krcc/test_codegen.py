from codegen import CodeGenerator
from layout import StorageLayout
from lexer import Lexer
from parser import Parser
from semantic import SemanticAnalyzer


source = r"""
int main(int a, int b)
{
    int x, y;

    x = 10;
    y = 20;

    printf("x=%d y=%d sum=%d\n", x, y, x+y);

    return 0;
}
"""

source = r"""
int calculate(int a, int b)
{
    return a + b;
}

int helper(int value)
{
    return value + 2;
}

int main(void)
{
    return 0;
}
"""
source = r"""
int calculate(int a, int b)
{
    return a + b;
}

int main(void)
{
    int result;
    result = calculate(10, 20);
    return result;
}
"""
source = r"""
int main(void)
{
    int result;

    result = 2 + 3 * 4;

    return result;
}
"""


tokens = Lexer(source).tokenize()
ast = Parser(tokens).parse_translation_unit()
ast = SemanticAnalyzer().analyze(ast)
ast = StorageLayout().layout(ast)
assembly = CodeGenerator().generate(ast)

print("Generated KR32 assembly:")
print("------------------------")
print(assembly)
