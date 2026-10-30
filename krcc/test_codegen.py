from lexer import Lexer
from parser import Parser
from codegen import CodeGenerator


source = """
int main(void)
{
    return 42;
}
"""

# Stage 1: Source code -> tokens
tokens = Lexer(source).tokenize()

# Stage 2: Tokens -> AST
ast = Parser(tokens).parse_translation_unit()

# Stage 3: AST -> KR32 assembly
generator = CodeGenerator()
assembly = generator.generate(ast)

print("Generated KR32 assembly:")
print("------------------------")
print(assembly)