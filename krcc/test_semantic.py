from lexer import Lexer
from parser import Parser
from semantic import SemanticAnalyzer, SemanticError


source = r"""
int main(void) {
    int x;
    int y;

    x = 0;
    y = 1;

    do {
        x = x + 1;
        printf("x=%d y=%d\n", x, y);
    } while (x < 10);
    int x;
    return 0;
}
"""
source = r"""
int main(void) {
    int x;

    do {
        int y;
        y = 10;
        x = y;
    } while (x < 20);
    int y;
    y = 30 * y * 1 - x;       // should fail!
    return 0;
}
"""
source = r"""
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

source = r"""
int calculate(int a, int b)
{
    return a + b;
}

int main(void)
{
    int result;
    result = calculate(10,20,30);
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

# Stage 1: Lexical analysis.
tokens = Lexer(source).tokenize()

print("=== TOKENS ===")

#for token in tokens:
   # print(token)

# Stage 2: Parsing.
parser = Parser(tokens)
ast = parser.parse_translation_unit()

print("\n=== AST ===")
print(ast)

# Stage 3: Semantic analysis.
analyzer = SemanticAnalyzer()

try:
    analyzer.analyze(ast)
    print("Semantic analysis successful!")

except SemanticError as error:
    print(f"Semantic error: {error}")