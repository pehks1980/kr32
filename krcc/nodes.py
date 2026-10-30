
from dataclasses import dataclass


# Represents an integer constant in the source, such as 42.
@dataclass
class IntLiteral:
    value: int


@dataclass
class StringLiteral:
    value: str


@dataclass
class Print:
    value: StringLiteral


# Represents a return statement, such as:
#     return 42;
#
# For now, its value is restricted to an integer literal.
# Later, it can hold expressions such as "return a + b;".
@dataclass
class Return:
    value: IntLiteral


# Represents one function definition, for example:
#     int main(void) { return 42; }
@dataclass
class Function:
    return_type: str   # Initially, "int"
    name: str          # Function name, e.g. "main"
    parameters: list   # Empty for the initial main(void) grammar
    body: list         # Statements inside the function


# Represents a complete C source file.
# A translation unit may eventually contain multiple functions
# and global declarations; initially, it contains one function.
@dataclass
class TranslationUnit:
    functions: list
