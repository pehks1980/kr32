from nodes import (
    IntLiteral,
    Print,
    Return,
    StringLiteral,
    Function,
    TranslationUnit,
)


# Parser-specific exception.
# We keep syntax errors separate from lexical errors.
class ParserError(Exception):
    pass


class Parser:
    def __init__(self, tokens):
        # Tokens produced by our lexer.
        self.tokens = tokens

        # Index of the token currently being examined.
        self.pos = 0

    def current(self):
        # Return the current token without consuming it.
        return self.tokens[self.pos]

    def advance(self):
        # Consume the current token and move to the next one.
        token = self.current()

        # Do not move beyond EOF.
        if token.kind != "EOF":
            self.pos += 1

        return token

    def expect(self, kind, value=None):
        """
        Require the current token to have a particular kind
        and optionally a particular value.

        For example:
            expect("KEYWORD", "int")
            expect("PUNCT", ";")
            expect("IDENT")
        """

        token = self.current()

        # First check the token category.
        if token.kind != kind:
            raise ParserError(
                f"{token.line}:{token.column}: "
                f"expected {kind}, got {token.kind} ({token.value!r})"
            )

        # If a specific value was requested, check that too.
        if value is not None and token.value != value:
            raise ParserError(
                f"{token.line}:{token.column}: "
                f"expected {value!r}, got {token.value!r}"
            )

        # The token matches. Consume it and return it.
        return self.advance()

    def parse_integer(self, token):
        # Convert the original spelling into a Python integer.
        #
        # Decimal:     "42"   -> 42
        # Hexadecimal: "0x2A" -> 42
        #
        # We handle the formats explicitly so that decimal
        # numbers are always interpreted as decimal.
        if token.value.lower().startswith("0x"):
            return int(token.value, 16)

        return int(token.value, 10)

    def parse_translation_unit(self):
        """
        Parse the complete source file.

        Our first compiler version supports one function only.
        EOF ensures that no unexpected tokens remain afterwards.
        """

        functions = []

        # Parse the function defined in the source.
        functions.append(self.parse_function())

        # The complete input must now be consumed.
        self.expect("EOF")

        return TranslationUnit(functions=functions)

    def parse_function(self):
        """
        Grammar:
            function := "int" IDENT "(" "void" ")" block
        """

        # Function return type.
        return_type = self.expect("KEYWORD", "int").value

        # Function name.
        name = self.expect("IDENT").value

        # Opening parenthesis.
        self.expect("PUNCT", "(")

        # Only main(void) is supported for now.
        self.expect("KEYWORD", "void")

        # Closing parenthesis.
        self.expect("PUNCT", ")")

        # Parse the function body.
        body = self.parse_block()

        return Function(
            return_type=return_type,
            name=name,
            parameters=[],
            body=body,
        )

    def parse_block(self):
        """
        Grammar:
            block := "{" statement* "}"
        """

        self.expect("PUNCT", "{")

        statements = []
        while not (
            self.current().kind == "PUNCT"
            and self.current().value == "}"
        ):
            if self.current().kind == "EOF":
                token = self.current()
                raise ParserError(
                    f"{token.line}:{token.column}: expected '}}' before end of file"
                )
            statements.append(self.parse_statement())

        self.expect("PUNCT", "}")

        return statements

    def parse_statement(self):
        token = self.current()
        if token.kind == "KEYWORD" and token.value == "return":
            return self.parse_return_statement()
        if token.kind == "IDENT" and token.value == "printf":
            return self.parse_printf_statement()
        raise ParserError(
            f"{token.line}:{token.column}: unsupported statement "
            f"starting with {token.value!r}"
        )

    def parse_printf_statement(self):
        """
        Grammar:
            printf_statement := "printf" "(" STRING ")" ";"
        """

        self.expect("IDENT", "printf")
        self.expect("PUNCT", "(")
        value = self.expect("STRING").value
        self.expect("PUNCT", ")")
        self.expect("PUNCT", ";")
        return Print(value=StringLiteral(value=value))

    def parse_return_statement(self):
        """
        Grammar:
            return_statement := "return" INTEGER ";"
        """

        self.expect("KEYWORD", "return")

        # Read the integer token.
        token = self.expect("INT")

        # Convert its textual representation into a number.
        value = self.parse_integer(token)

        # Every return statement must end with a semicolon.
        self.expect("PUNCT", ";")

        # Construct the AST nodes.
        return Return(
            value=IntLiteral(value=value)
        )