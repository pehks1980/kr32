
from lexer import Lexer
from parser import Parser
from semantic import SemanticAnalyzer
from layout import StorageLayout

from ast_printer import print_ast



source = r"""
int main(void) {
    int x;
    int y;

    x = 10;
    y = 20;

    do {
        int result;
        result = x + y;
        printf("result=%d\n", result);
    } while (x < 20);

    return result;
}
"""

source = r"""
int main(void)
{
    printf("Hello from KR32!\n");
    printf("How dy we have c now! what a impression\n");
    return 0;
}
"""

# Stage 1: Lexing
tokens = Lexer(source).tokenize()

# Stage 2: Parsing
parser = Parser(tokens)
ast = parser.parse_translation_unit()

print("\n=== AST ===")
print_ast(ast)

#print("\n=== AST ===")
#print(ast)

# Stage 3: Semantic analysis
analyzer = SemanticAnalyzer()
analyzer.analyze(ast)

# Stage 4: Storage layout
layout = StorageLayout()
layout.layout(ast)

# Display results
for function in ast.functions:
    print(f"\nFunction: {function.name}")
    print(f"Stack frame size: {function.frame_size} bytes")

    def show_layout(statements):
        for statement in statements:

            if hasattr(statement, "symbols"):
                for symbol in statement.symbols:
                    print(
                        f"  {symbol.name:10} "
                        f"offset={symbol.stack_offset}"
                    )

            if hasattr(statement, "body"):
                show_layout(statement.body)

    show_layout(function.body)
