
from lexer import Lexer


# A minimal C program to use as input for the lexer.
source = """
int main(void)
{
    // one time
    return 42;
}
"""

# Print every token so we can inspect the categories,
# values, and source positions produced by the lexer.
for token in Lexer(source).tokenize():
    print(token)
