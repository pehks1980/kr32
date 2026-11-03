from lexer import Lexer
from parser import Parser
from codegen import CodeGenerator

from semantic import SemanticAnalyzer
from layout import StorageLayout


source = """
int main(void) {
    int x;
    int y;
    int result;

    x = 10;
    y = 20;
    result = x + y;

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

# Stage 1: Source code -> tokens
tokens = Lexer(source).tokenize()

# Stage 2: Tokens -> AST
ast = Parser(tokens).parse_translation_unit()

# Pass 1: Resolve identifiers and attach symbols to AST nodes.
semantic = SemanticAnalyzer()
ast = semantic.analyze(ast)

# Pass 2: Assign stack offsets and calculate function frame sizes.
layout = StorageLayout()
ast = layout.layout(ast)

# Debug: inspect the resulting stack frame.
for function in ast.functions:
    print(f"Function: {function.name}")
    print(f"Frame size: {function.frame_size}")

# Pass 3: Generate assembly.
generator = CodeGenerator()
assembly = generator.generate(ast)

# Stage 3: AST -> KR32 assembly
generator = CodeGenerator()
assembly = generator.generate(ast)

print("Generated KR32 assembly:")
print("------------------------")
print(assembly)